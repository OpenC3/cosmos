# Copyright 2024 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from cbor2 import dumps, loads
from .json_accessor import JsonAccessor


class CborAccessor(JsonAccessor):
    @classmethod
    def class_read_item(cls, item, buffer):
        if item.data_type == "DERIVED":
            return None
        if isinstance(buffer, bytearray):
            parsed = loads(buffer)
        else:
            parsed = buffer
        return super().class_read_item(item, parsed)

    @classmethod
    def class_write_item(cls, item, value, buffer):
        if item.data_type == "DERIVED":
            return None
        if isinstance(buffer, bytearray):
            decoded = loads(buffer)
        else:
            decoded = buffer

        super().class_write_item(item, value, decoded)

        if isinstance(buffer, bytearray):
            # buffer[0:] syntax so we copy into the buffer
            buffer[0:] = dumps(decoded)
        return value

    @classmethod
    def class_read_items(cls, items, buffer):
        return super().class_read_items(items, loads(buffer))

    @classmethod
    def class_write_items(cls, items, values, buffer):
        decoded = loads(buffer)
        super().class_write_items(items, values, decoded)
        # buffer[0:] syntax so we copy into the buffer
        buffer[0:] = dumps(decoded)
        return values
