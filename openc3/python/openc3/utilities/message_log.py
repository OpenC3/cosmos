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

import os
import time
from datetime import datetime, timezone
from threading import Lock
from openc3.utilities.bucket_utilities import BucketUtilities
from openc3.utilities.logger import Logger
from openc3.environment import OPENC3_SCOPE


# Handles writing message logs to a file
class MessageLog:
    @classmethod
    def build_timestamped_filename(cls, tags=None, extension=".txt", time=None):
        if time is None:
            time = datetime.now(timezone.utc)
        timestamp = time.strftime("%Y_%m_%d_%H_%M_%S")
        tags = tags or []
        tags = [i for i in tags if i is not None]  # Remove Nones
        combined_tags = "_".join(tags)
        filename = None
        if len(combined_tags) > 0:
            filename = timestamp + "_" + combined_tags + extension
        else:
            filename = timestamp + extension
        return filename

    # @param tool_name [String] The name of the tool creating the message log.
    #   This will be inserted into the message log filename to help identify it.
    # @param log_dir [String] The filesystem path to store the message log file.
    # @param tags [Array<String>] Array of strings to put into the filename
    def __init__(self, tool_name, log_dir, tags=["messages"], scope=OPENC3_SCOPE):
        self.remote_log_directory = f"{scope}/tool_logs/{tool_name}/"
        self.tags = [tool_name] + tags
        self.log_dir = log_dir
        self.filename = ""
        self.file = None
        self.start_day = None
        self.mutex = Lock()

    # Ensures the log file is opened and ready to write. It then writes the
    # message to the log and flushes it to force the write.
    #
    # @param message [String] Message to write to the log
    def write(self, message, flush=False):
        with self.mutex:
            if self.file is None or self.file.closed or not os.path.exists(self.filename):
                self.start(False)

            self.file.write(message)
            if flush:
                self.file.flush()

    # Closes the message log and marks it read only
    def stop(self, take_mutex=True, metadata={}):
        if take_mutex:
            self.mutex.acquire()
        if self.file and not self.file.closed:
            self.file.close()
            os.chmod(self.filename, 0o444)
            bucket_key = os.path.join(
                self.remote_log_directory,
                self.start_day,
                os.path.basename(self.filename),
            )
            try:
                thread = BucketUtilities.move_log_file_to_bucket(self.filename, bucket_key, metadata=metadata)
                thread.join()
            except Exception as e:
                Logger.error(str(e))

        if take_mutex:
            self.mutex.release()

    # Creates a new message log and sets the filename
    def start(self, take_mutex=True):
        if take_mutex:
            self.mutex.acquire()
        # Prevent starting files too fast
        while True:
            if os.path.exists(os.path.join(self.log_dir, self.build_timestamped_filename(self.tags))):
                time.sleep(0.1)
            else:
                break
        self.stop(False)
        timed_filename = self.build_timestamped_filename(self.tags)
        self.start_day = timed_filename[0:10].replace("_", "")  # YYYYMMDD
        self.filename = os.path.join(self.log_dir, timed_filename)
        self.file = open(self.filename, "a")
        if take_mutex:
            self.mutex.release()
