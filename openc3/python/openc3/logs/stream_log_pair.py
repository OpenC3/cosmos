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

from .stream_log import StreamLog


class StreamLogPair:
    """Holds a read/write pair of stream logs"""

    # self.param name [String] name to be added to log filenames
    # self.param params [Array] stream log writer parameters or empty array
    def __init__(self, name, params=[]):
        self.read_log = StreamLog(name, "READ", *params)
        self.write_log = StreamLog(name, "WRITE", *params)

    @property
    def name(self):
        return self.__name

    @name.setter
    def name(self, name):
        self.__name = name
        self.read_log.name = name
        self.write_log.name = name

    # Start stream logs
    def start(self):
        self.read_log.start()
        self.write_log.start()

    # Close any open stream log files
    def stop(self):
        self.read_log.stop()
        self.write_log.stop()

    def shutdown(self):
        self.read_log.shutdown()
        self.write_log.shutdown()

    # TODO: Simply copy.copy
    # Clone the stream log pair
    # def clone(self):
    #   stream_log_pair = super.clone()
    #   stream_log_pair.read_log = self.read_log.clone
    #   stream_log_pair.write_log = self.write_log.clone
    #   stream_log_pair.read_log.start if self.read_log.logging_enabled:
    #   stream_log_pair.write_log.start if self.write_log.logging_enabled:
    #   stream_log_pair
