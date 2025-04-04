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

from openc3.packets.packet_item import PacketItem

class TableItem(PacketItem):
    """
    Implements the attributes that are unique to a TableItem such as editable
    and hidden. All other functionality is inherited from PacketItem.
    """

    def __init__(
        self,
        name,
        bit_offset,
        bit_size,
        data_type,
        endianness,
        array_size=None,
        overflow="ERROR"
    ):
        """
        Constructor

        Args:
            name: The name of the item. Used by the accessor methods to grab data.
            bit_offset: The offset in bits where this item is found in the packet
            bit_size: The size in bits of this item
            data_type: The data type of this item. Must be one of :INT, :UINT, :FLOAT, or :STRING, :BLOCK
            endianness: Must be one of :BIG_ENDIAN or :LITTLE_ENDIAN
            array_size: Set to a value if this item is to be an array. Default is nil.
            overflow: How to handle value overflows. Must be one of :ERROR, :ERROR_ALLOW_HEX, :TRUNCATE, :SATURATE
        """
        super().__init__(
            name,
            bit_offset,
            bit_size,
            data_type,
            endianness,
            array_size,
            overflow,
        )
        self.display_type = None
        self._editable = True
        self._hidden = False

    @property
    def editable(self):
        """Whether this item is editable"""
        return self._editable

    @editable.setter
    def editable(self, editable):
        """
        Set whether this item can be edited

        Args:
            editable: Boolean indicating if item is editable

        Raises:
            TypeError if editable is not a boolean
        """
        if not isinstance(editable, bool):
            raise TypeError(f"{self.name}: editable must be a boolean but is a {type(editable).__name__}")
        self._editable = editable

    @property
    def hidden(self):
        """Whether this item is hidden (not displayed)"""
        return self._hidden

    @hidden.setter
    def hidden(self, hidden):
        """
        Set whether this item should be hidden

        Args:
            hidden: Boolean indicating if item is hidden

        Raises:
            TypeError if hidden is not a boolean
        """
        if not isinstance(hidden, bool):
            raise TypeError(f"{self.name}: hidden must be a boolean but is a {type(hidden).__name__}")
        self._hidden = hidden

    def clone(self):
        """
        Make a light weight clone of this item

        Returns:
            Cloned TableItem
        """
        item = super().clone()
        item.editable = self.editable
        item.hidden = self.hidden
        return item

    def as_json(self, *args, **kwargs):
        """
        Create a hash of this item's attributes

        Returns:
            Dict representing the item
        """
        hash_val = super().as_json(*args, **kwargs)
        hash_val['editable'] = self.editable
        hash_val['hidden'] = self.hidden
        return hash_val