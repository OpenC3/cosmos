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

# Adds IO streams and then defers to the streams when using any of the Python
# output methods such as print

import sys


class IoMultiplexer:
    STDOUT = sys.stdout
    STDERR = sys.stderr

    # Create the empty stream array
    def __init__(self):
        self.streams = []

    # Delegate all unknown methods to all streams
    def __getattr__(self, func):
        def method(*args, **kwargs):
            first = True
            result = None
            for stream in self.streams:
                if first:
                    result = getattr(stream, func)(*args, **kwargs)
                    if result == stream:
                        result = self
                    first = False
                else:
                    getattr(stream, func)(*args, **kwargs)
            return result

        return method

    # Removes STDOUT and STDERR from the array of streams
    def remove_default_io(self):
        if self.STDOUT in self.streams:
            self.streams.remove(self.STDOUT)
        if self.STDERR in self.streams:
            self.streams.remove(self.STDERR)

    # @param stream [IO] The stream to add
    def add_stream(self, stream):
        if stream not in self.streams:
            self.streams.append(stream)

    # @param stream [IO] The stream to remove
    def remove_stream(self, stream):
        if stream in self.streams:
            self.streams.remove(stream)
