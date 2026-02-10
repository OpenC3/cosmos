# Copyright 2023, OpenC3, Inc.
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
class Stdout(IoMultiplexer):
    my_instance = None

    def __init__(self):
        super().__init__()
        self.streams.append(self.STDOUT)
        Stdout.my_instance = self

    # @return [Stdout] Returns a single instance of Stdout
    @classmethod
    def instance(cls):
        if not Stdout.my_instance:
            cls()
        return Stdout.my_instance

    @property
    def encoding(self):
        return self.STDOUT.encoding
