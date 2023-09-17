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


# Class that implments the following methods= read, write(data),
# connect, connected? and disconnect. Streams are simply data sources which
# {Protocol} classes read and write to. This separation of concerns
# allows Streams to simply focus on getting and sending raw data while the
# higher level processing occurs in {Protocol}.
class Stream:
    # Expected to return any amount of data on success, or a blank string on
    # closed/EOF, and may raise Timeout='E'rror, or other errors
    def read(self):
        raise RuntimeError("read not defined by Stream")

    # Expected to always return immediately with data if available or an empty string
    # Should not raise errors
    def read_nonblock(self):
        raise RuntimeError("read_nonblock not defined by Stream")

    # Expected to write complete set of data.  May raise TimeoutError
    # or other errors.
    #
    # self.param data [String] Binary data to write to the stream
    def write(self, data):
        raise RuntimeError("write not defined by Stream")

    # Connects the stream
    def connect(self):
        raise RuntimeError("connect not defined by Stream")

    # Disconnects the stream
    # Note that streams are not designed to be reconnected and must be recreated
    def disconnect(self):
        raise RuntimeError("disconnect not defined by Stream")
