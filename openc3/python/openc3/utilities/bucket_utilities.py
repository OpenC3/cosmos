# Copyright 2023 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.utilities.bucket import Bucket
from openc3.utilities.target_file import TargetFile
from openc3.utilities.logger import Logger
from openc3.models.reducer_model import ReducerModel
from openc3.environment import OPENC3_SCOPE, OPENC3_LOGS_BUCKET
import zlib
import os
import time
import threading


class BucketUtilities:
    FILE_TIMESTAMP_FORMAT = "%Y%m%d%H%M%S%N"
    DIRECTORY_TIMESTAMP_FORMAT = "%Y%m%d"

    @classmethod
    def bucket_load(cls, *args, scope=OPENC3_SCOPE):
        if not scope:
            scope = OPENC3_SCOPE
        path = args[0]

        # Only support TARGET files
        if path[0] == "/" or str(path.split("/")[0]).upper() != path.split("/")[0]:
            raise ImportError(f"only relative TARGET files are allowed -- {path}")
        extension = os.path.splitext(path)[1]
        if not extension or extension == "":
            path = path + ".py"

        # Retrieve the text of the script from S3
        text = TargetFile.body(scope, path)
        if not text:
            raise ImportError(f"Bucket file {path} not found for scope {scope}")

        # Execute the script directly without instrumentation because we are doing require/load
        exec(text)

        # Successful load/require returns true
        return True

    @classmethod
    def move_log_file_to_bucket_thread(cls, filename, bucket_key, metadata={}):
        try:
            client = Bucket.getClient()

            orig_filename = None
            if os.path.splitext(filename)[1] != ".txt":
                orig_filename = filename
                filename = cls.compress_file(filename)
                bucket_key += ".gz"

            retry_count = 0
            while retry_count < 3:
                try:
                    # We want to open this as a file and pass that to put_object to allow
                    # this to work with really large files. Otherwise the entire file has
                    # to be held in memory!
                    with open(filename, "rb") as file:
                        client.put_object(
                            bucket=OPENC3_LOGS_BUCKET,
                            key=bucket_key,
                            body=file,
                            metadata=metadata,
                        )
                    break
                except Exception as err:
                    # Try to upload file three times
                    retry_count += 1
                    if retry_count >= 3:
                        raise err
                    Logger.warn(
                        f"Error saving log file to bucket - retry {retry_count}: {filename}\n{str(err)}"
                    )
                    time.sleep(1)

            Logger.debug(f"wrote {OPENC3_LOGS_BUCKET}/{bucket_key}")
            ReducerModel.add_file(bucket_key)  # Record the new file for data reduction

            if orig_filename:
                os.remove(orig_filename)
            os.remove(filename)
        except Exception as err:
            Logger.error(f"Error saving log file to bucket: {filename}\n{str(err)}")

    @classmethod
    def move_log_file_to_bucket(cls, filename, bucket_key, metadata={}):
        thread = threading.Thread(
            target=cls.move_log_file_to_bucket_thread,
            args=[filename, bucket_key, metadata],
        )
        thread.start()
        return thread

    @classmethod
    def compress_file(cls, filename, chunk_size=50_000_000):
        zipped = f"{filename}.gz"

        obj = zlib.compressobj()
        with open(zipped, "wb") as zip_file:
            with open(filename, "rb") as file:
                while True:
                    chunk = file.read(chunk_size)
                    if chunk:
                        compressed = obj.compress(chunk)
                        zip_file.write(compressed)
                    else:
                        compressed = obj.flush()
                        if compressed:
                            zip_file.write(compressed)
                        break

        return zipped
