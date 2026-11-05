import os
import gzip
import struct
import shutil

from openc3.api.tlm_api import inject_tlm
from openc3.interfaces.file_interface import FileInterface

PKT_ID = 10000
FILE_HEADER_SIZE = 20  # five 32 bit fields
RECORD_HEADER_SIZE = 20  # five 32 bit fields
TOTAL_HEADER_SIZE = FILE_HEADER_SIZE + RECORD_HEADER_SIZE


class ArchiveInterface(FileInterface):
    def __init__(
        self,
        command_write_folder,
        telemetry_read_folder,
        telemetry_archive_folder,
        file_read_size=65536,
        stored=True,
        protocol_type=None,
        protocol_args=None,
        archive_target_name="TGT",
        archive_packet_name="PKT",
    ):
        super().__init__(
            command_write_folder,
            telemetry_read_folder,
            telemetry_archive_folder,
            file_read_size,
            stored,
            protocol_type,
            protocol_args,
        )
        self.archive_target_name = archive_target_name
        self.archive_packet_name = archive_packet_name

    # Most of this is simply copying the existing read_interface implementation
    def read_interface(self):
        while True:
            if self.file:
                data = self.file.read(self.file_read_size)
                if self.throttle and self.sleeper.sleep(self.throttle):
                    return None, None
                if data is not None and len(data) > 0:
                    self.read_interface_base(data, None)
                    return data, None
                else:
                    self.finish_file()

            file = self.get_next_telemetry_file()
            if file:
                if file.endswith(".gz"):
                    self.file = gzip.open(file, "rb")
                else:
                    self.file = open(file, "rb")
                self.file_path = file
                if self.discard_file_header_bytes is not None:
                    self.file.read(self.discard_file_header_bytes)
                self._consume_file_header()  # <!- NEW METHOD
                continue

            result = self.queue.get()
            if result is None:
                return None, None

    # This is where we read the file header and save it as a packet
    def _consume_file_header(self):
        header = self.file.read(TOTAL_HEADER_SIZE)
        if len(header) < TOTAL_HEADER_SIZE:
            return
        item_hash = self._parse_file_header(header)
        inject_tlm(self.archive_target_name, self.archive_packet_name, item_hash)

    @staticmethod
    def _parse_file_header(header):
        (length, record_count, dump_id, time_seconds, time_subseconds) = struct.unpack(">IIIII", header[0:20])
        return {
            "PKT_ID": PKT_ID,
            "LENGTH": length,
            "RECORD_COUNT": record_count,
            "DUMP_ID": dump_id,
            "TIME_SECONDS": time_seconds,
            "TIME_SUBSECONDS": time_subseconds,
        }

    # Override finish_file before COSMOS 7.2 to change os.rename which raised EXDEV / "Cross-device link"
    # on separate Docker bind mounts to shutil.move which uses copy+delete across filesystems
    # This issue was fixed in the COSMOS 7.2 release and this is no longer needed.
    def finish_file(self):
        self.file.close()
        self.file = None
        if self.telemetry_archive_folder == "DELETE":
            os.remove(self.file_path)
        else:
            new_path = os.path.join(self.telemetry_archive_folder, os.path.basename(self.file_path))
            shutil.move(self.file_path, new_path)
        self.file_path = None