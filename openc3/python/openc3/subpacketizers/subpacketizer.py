# Copyright 2025 OpenC3, Inc.
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


class Subpacketizer:
    """Base class for subpacketizers.

    Subpacketizers are used to break up packets into subpackets before decommutation.
    This is typically used for channelized data where one packet contains data for
    multiple channels that need to be processed independently.
    """

    def __init__(self, packet=None):
        """Initialize the subpacketizer with empty args list."""
        self.packet = packet
        self.args = []

    def call(self, packet):
        """Break packet into subpackets.

        Subclass and implement this method to break packet into array of subpackets.
        Subpackets should be fully identified and defined.

        Args:
            packet: The packet object to subpacketize

        Returns:
            list: List of packet objects (default implementation returns single packet)
        """
        return [packet]

    def as_json(self):
        """Convert subpacketizer to JSON-serializable dict.

        Returns:
            dict: Dictionary with 'class' and 'args' keys
        """
        return {"class": self.__class__.__name__, "args": self.args}
