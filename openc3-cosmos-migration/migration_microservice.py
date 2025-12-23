# Copyright 2025 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

"""
Migration microservice for ingesting historical bin file data into QuestDB.

This microservice:
- Pulls decom_logs bin files from S3-compatible storage
- Parses COSMOS5 binary format
- Ingests data into QuestDB with schema protection
- Processes files in reverse chronological order (newest first)
- Moves processed files to a processed/ folder
- Tracks progress in Redis for resume capability
- Rate-limits ingestion to avoid overwhelming the operational system
"""

import gzip
import io
import json
import os
import sys
import time
import traceback
from datetime import datetime, timezone

from openc3.environment import OPENC3_SCOPE
from openc3.utilities.bucket import Bucket
from openc3.utilities.logger import Logger
from openc3.utilities.questdb_client import QuestDBClient
from openc3.utilities.store import Store

# Import from local module
from bin_file_processor import BinFileProcessor, extract_timestamp_from_filename, parse_target_packet_from_filename


# Environment variable configuration
MIGRATION_ENABLED = os.environ.get("MIGRATION_ENABLED", "false").lower() == "true"
MIGRATION_BATCH_SIZE = int(os.environ.get("MIGRATION_BATCH_SIZE", "1000"))
MIGRATION_SLEEP_SECONDS = float(os.environ.get("MIGRATION_SLEEP_SECONDS", "0.5"))
MIGRATION_FILES_BEFORE_PAUSE = int(os.environ.get("MIGRATION_FILES_BEFORE_PAUSE", "10"))
MIGRATION_PAUSE_SECONDS = float(os.environ.get("MIGRATION_PAUSE_SECONDS", "30"))
MIGRATION_SCOPE = os.environ.get("OPENC3_SCOPE", "DEFAULT")

# Redis key for progress tracking
MIGRATION_PROGRESS_KEY = f"OPENC3__{MIGRATION_SCOPE}__MIGRATION__PROGRESS"


class MigrationMicroservice:
    """
    Migration microservice for ingesting historical bin file data into QuestDB.
    """

    def __init__(self):
        self.logger = Logger()
        self.logger.scope = MIGRATION_SCOPE
        self.bucket = Bucket.getClient()
        self.questdb = QuestDBClient(logger=self.logger)
        self.bin_processor = BinFileProcessor(logger=self.logger)

        self.cancel_thread = False
        self.error = None

        # Valid targets/packets (current system definitions)
        self.valid_targets = set()
        self.valid_packets = {}  # {target_name: set(packet_names)}

        # Statistics
        self.files_processed = 0
        self.packets_ingested = 0
        self.errors_count = 0
        self.migrated_columns = []

    def _load_valid_targets_packets(self):
        """Load current target/packet definitions from the system."""
        try:
            from openc3.api.target_api import get_target_names
            from openc3.api.tlm_api import get_all_tlm_names

            self.valid_targets = set(get_target_names())
            self.valid_packets = {}
            for target in self.valid_targets:
                try:
                    self.valid_packets[target] = set(get_all_tlm_names(target))
                except Exception:
                    self.valid_packets[target] = set()

            self.logger.info(
                f"Loaded {len(self.valid_targets)} targets with "
                f"{sum(len(p) for p in self.valid_packets.values())} total packets"
            )
        except Exception as e:
            self.logger.error(f"Failed to load target/packet definitions: {e}")
            raise

    def _should_process_file(self, filename: str) -> bool:
        """Check if a file should be processed based on current system definitions."""
        target_name, packet_name = parse_target_packet_from_filename(filename)
        if target_name is None or packet_name is None:
            self.logger.debug(f"Could not parse target/packet from filename: {filename}")
            return False

        if target_name not in self.valid_targets:
            self.logger.debug(f"Skipping obsolete target: {target_name}")
            return False

        if packet_name not in self.valid_packets.get(target_name, set()):
            self.logger.debug(f"Skipping obsolete packet: {target_name}/{packet_name}")
            return False

        return True

    def _get_progress(self) -> dict:
        """Get migration progress from Redis."""
        try:
            progress_json = Store.get(MIGRATION_PROGRESS_KEY)
            if progress_json:
                return json.loads(progress_json)
        except Exception:
            pass
        return {}

    def _save_progress(self, last_file: str):
        """Save migration progress to Redis."""
        progress = {
            "last_file": last_file,
            "files_processed": self.files_processed,
            "packets_ingested": self.packets_ingested,
            "errors_count": self.errors_count,
            "started_at": getattr(self, "started_at", datetime.now(timezone.utc).isoformat()),
            "last_updated": datetime.now(timezone.utc).isoformat(),
        }
        try:
            Store.set(MIGRATION_PROGRESS_KEY, json.dumps(progress))
        except Exception as e:
            self.logger.warn(f"Failed to save progress: {e}")

    def _list_decom_files(self) -> list:
        """List all decom log files in the bucket, sorted by timestamp descending (newest first)."""
        files = []
        logs_bucket = os.environ.get("OPENC3_LOGS_BUCKET", "logs")

        # List files in decom_logs/tlm/ directory
        try:
            prefix = f"{MIGRATION_SCOPE}/decom_logs/tlm/"
            file_list = self.bucket.list_files(bucket=logs_bucket, path=prefix)

            for file_info in file_list:
                filename = file_info if isinstance(file_info, str) else file_info.get("name", "")
                if filename.endswith(".bin") or filename.endswith(".bin.gz"):
                    files.append(filename)
        except Exception as e:
            self.logger.error(f"Error listing decom_logs/tlm/: {e}")

        # Also check decom_logs/cmd/ if we want to migrate commands
        try:
            prefix = f"{MIGRATION_SCOPE}/decom_logs/cmd/"
            file_list = self.bucket.list_files(bucket=logs_bucket, path=prefix)

            for file_info in file_list:
                filename = file_info if isinstance(file_info, str) else file_info.get("name", "")
                if filename.endswith(".bin") or filename.endswith(".bin.gz"):
                    files.append(filename)
        except Exception as e:
            self.logger.debug(f"No decom_logs/cmd/ or error: {e}")

        # Sort by timestamp descending (newest first)
        files.sort(key=lambda f: extract_timestamp_from_filename(f), reverse=True)

        self.logger.info(f"Found {len(files)} decom log files to process")
        return files

    def _download_file(self, bucket_path: str) -> bytes:
        """Download a file from the bucket and return its contents."""
        logs_bucket = os.environ.get("OPENC3_LOGS_BUCKET", "logs")
        response = self.bucket.get_object(bucket=logs_bucket, key=bucket_path)

        if isinstance(response, dict) and "Body" in response:
            data = response["Body"].read()
        else:
            data = response

        # Decompress if gzipped
        if bucket_path.endswith(".gz"):
            data = gzip.decompress(data)

        return data

    def _move_to_processed(self, original_path: str):
        """Move a processed file to the processed/ folder."""
        logs_bucket = os.environ.get("OPENC3_LOGS_BUCKET", "logs")

        # Replace decom_logs with processed/decom_logs
        processed_path = original_path.replace("/decom_logs/", "/processed/decom_logs/", 1)

        try:
            # Copy to processed location
            self.bucket.copy_object(
                src_bucket=logs_bucket, src_key=original_path, dest_bucket=logs_bucket, dest_key=processed_path
            )
            # Delete original
            self.bucket.delete_object(bucket=logs_bucket, key=original_path)
            self.logger.debug(f"Moved {original_path} to {processed_path}")
        except Exception as e:
            self.logger.warn(f"Failed to move file to processed: {e}")

    def _process_file(self, file_path: str) -> int:
        """
        Process a single bin file and ingest its data into QuestDB.

        Returns the number of packets ingested.
        """
        packets_in_file = 0

        try:
            # Download and decompress file
            data = self._download_file(file_path)

            # Process the file
            batch_count = 0
            for packet in self.bin_processor.process_bytes(data):
                if self.cancel_thread:
                    break

                # Get table name
                table_name, _ = QuestDBClient.sanitize_table_name(packet.target_name, packet.packet_name)

                # Convert JSON data to QuestDB columns
                columns = self.questdb.process_json_data(packet.json_data)

                if not columns:
                    continue

                # Write with schema protection
                success, migrated = self.questdb.write_row_with_schema_protection(
                    table_name, columns, packet.time_nsec
                )

                if success:
                    packets_in_file += 1
                    batch_count += 1
                    self.migrated_columns.extend(migrated)

                # Flush and sleep periodically
                if batch_count >= MIGRATION_BATCH_SIZE:
                    self.questdb.flush()
                    time.sleep(MIGRATION_SLEEP_SECONDS)
                    batch_count = 0

            # Final flush
            self.questdb.flush()

        except Exception as e:
            self.logger.error(f"Error processing file {file_path}: {e}\n{traceback.format_exc()}")
            self.errors_count += 1

        return packets_in_file

    def run(self):
        """Main run loop."""
        if not MIGRATION_ENABLED:
            self.logger.info("Migration is disabled. Set MIGRATION_ENABLED=true to enable.")
            return

        self.logger.info("Starting QuestDB migration microservice")
        self.started_at = datetime.now(timezone.utc).isoformat()

        try:
            # Connect to QuestDB
            self.questdb.connect_ingest()
            self.questdb.connect_query()

            # Load current target/packet definitions
            self._load_valid_targets_packets()

            # Get list of files to process
            files = self._list_decom_files()

            # Filter to valid targets/packets
            files = [f for f in files if self._should_process_file(f)]
            self.logger.info(f"After filtering: {len(files)} files to process")

            # Check for resume point
            progress = self._get_progress()
            last_processed = progress.get("last_file")
            if last_processed:
                self.logger.info(f"Resuming from: {last_processed}")
                # Skip files that were already processed (newer than last_processed)
                last_timestamp = extract_timestamp_from_filename(last_processed)
                files = [f for f in files if extract_timestamp_from_filename(f) < last_timestamp]
                self.files_processed = progress.get("files_processed", 0)
                self.packets_ingested = progress.get("packets_ingested", 0)
                self.errors_count = progress.get("errors_count", 0)

            # Process files
            files_since_pause = 0
            for file_path in files:
                if self.cancel_thread:
                    break

                self.logger.info(f"Processing: {file_path}")

                packets = self._process_file(file_path)
                self.packets_ingested += packets
                self.files_processed += 1
                files_since_pause += 1

                # Move to processed folder
                self._move_to_processed(file_path)

                # Save progress
                self._save_progress(file_path)

                self.logger.info(
                    f"Completed: {file_path} - {packets} packets "
                    f"(total: {self.packets_ingested} packets, {self.files_processed} files)"
                )

                # Periodic pause to let operational system catch up
                if files_since_pause >= MIGRATION_FILES_BEFORE_PAUSE:
                    self.logger.info(f"Pausing for {MIGRATION_PAUSE_SECONDS}s to reduce system load...")
                    time.sleep(MIGRATION_PAUSE_SECONDS)
                    files_since_pause = 0

            # Final summary
            self.logger.info(
                f"Migration complete! "
                f"Files: {self.files_processed}, "
                f"Packets: {self.packets_ingested}, "
                f"Errors: {self.errors_count}"
            )

            if self.migrated_columns:
                self.logger.warn(f"Schema migrations occurred for columns: {set(self.migrated_columns)}")

        except Exception as e:
            self.error = e
            self.logger.error(f"Migration error: {e}\n{traceback.format_exc()}")
        finally:
            self.questdb.close()

    def shutdown(self):
        """Graceful shutdown."""
        self.cancel_thread = True
        self.questdb.close()


def main():
    """Entry point for the migration microservice."""
    service = MigrationMicroservice()
    try:
        service.run()
    except KeyboardInterrupt:
        service.shutdown()
    except Exception as e:
        print(f"Fatal error: {e}")
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
