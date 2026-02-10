# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.io.io_multiplexer import IoMultiplexer


# Adds STDOUT to the multiplexed streams
class Stderr(IoMultiplexer):
    my_instance = None

    def __init__(self):
        super().__init__()
        self.streams.append(self.STDERR)
        Stderr.my_instance = self

    # @return [Stdout] Returns a single instance of Stdout
    @classmethod
    def instance(cls):
        if not Stderr.my_instance:
            cls()
        return Stderr.my_instance

    @property
    def encoding(self):
        return self.STDERR.encoding
