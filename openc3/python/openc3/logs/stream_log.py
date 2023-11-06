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

import copy
from datetime import datetime, timezone
from .log_writer import LogWriter
from openc3.environment import OPENC3_SCOPE
from openc3.utilities.time import to_nsec_from_epoch
from openc3.utilities.logger import Logger


# Creates a log file of stream data for either reads or writes. Can automatically
# cycle the log based on when the log file reaches a predefined size or based on time.
class StreamLog(LogWriter):
    # # self.return [String] Original name passed to stream log
    # attr_reader :orig_name

    # The allowable log types
    LOG_TYPES = ["READ", "WRITE"]

    # self.param log_name [String] The name of the stream log. Typically matches the
    #    name of the corresponding interface
    # self.param log_type [Symbol] The type of log to create. Must be 'READ'
    #   or 'WRITE'.
    # self.param cycle_time [Integer] The amount of time in seconds before creating
    #   a new log file. This can be combined with cycle_size.
    # self.param cycle_size [Integer] The size in bytes before creating a new log
    #   file. This can be combined with cycle_time.
    # self.param cycle_hour [Integer] The time at which to cycle the log. Combined with
    #   cycle_minute to cycle the log daily at the specified time. If None, the log
    #   will be cycled hourly at the specified cycle_minute.
    # self.param cycle_minute [Integer] The time at which to cycle the log. See cycle_hour
    #   for more information.
    def __init__(
        self,
        log_name,
        log_type,
        cycle_time=600,  # 10 minutes, matches time in target_model
        cycle_size=50_000_000,  # 50MB, matches size in target_model
        cycle_hour=None,
        cycle_minute=None,
    ):
        if log_type not in StreamLog.LOG_TYPES:
            raise RuntimeError("log_type must be 'READ' or 'WRITE'")

        super().__init__(
            f"{OPENC3_SCOPE}/stream_logs/",
            True,  # Start with logging enabled
            cycle_time,
            cycle_size,
            cycle_hour,
            cycle_minute,
        )

        self.log_type = log_type
        self.name = log_name

    @property
    def name(self):
        return self.log_name

    @name.setter
    def name(self, name):
        self.orig_name = name
        self.log_name = name.lower() + "_stream_" + self.log_type.lower()

    # Create a clone of this object with a new name
    def clone(self):
        stream_log = copy.copy(self)
        stream_log.name = stream_log.orig_name
        return stream_log

    # Write to the log file.
    #
    # If no log file currently exists in the filesystem, a new file will be
    # created.
    #
    # self.param data [String] String of data
    def write(self, data):
        if not self.logging_enabled:
            return
        if data is None or len(data) <= 0:
            return

        try:
            with self.mutex:
                time_nsec_since_epoch = to_nsec_from_epoch(datetime.now(timezone.utc))
                self.prepare_write(time_nsec_since_epoch, len(data))
                if self.file:
                    self.write_entry(time_nsec_since_epoch, data)
        except RuntimeError as error:
            Logger.error(f"Error writing {self.filename} : {repr(error)}")
            # OpenC3.handle_critical_exception(err)

    def write_entry(self, time_nsec_since_epoch, data):
        self.file.write(data)
        self.file_size += len(data)
        if not self.first_time:
            self.first_time = time_nsec_since_epoch
        self.last_time = time_nsec_since_epoch

    def bucket_filename(self):
        return f"{self.first_timestamp()}__{self.log_name}" + self.extension()

    def extension(self):
        return ".bin"
