# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.io import IoMultiplexor

# Adds STDOUT to the multiplexed streams
class Stderr(IoMultiplexor):
    my_instance = None

    def __init__(self):
        super().__init__()
        self.streams.append(self.STDERR)
        self.my_instance = self

    # @return [Stdout] Returns a single instance of Stdout
    @classmethod
    def instance(cls):
        if not cls.my_instance:
            cls()
        return cls.my_instance
