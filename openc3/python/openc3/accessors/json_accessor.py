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

import json
from jsonpath_ng import parse
from .accessor import Accessor


class JsonAccessor(Accessor):
    @classmethod
    def class_read_item(cls, item, buffer):
        if item.data_type == "DERIVED":
            return None
        try:
            buffer = json.loads(buffer.decode())
        except (UnicodeDecodeError, AttributeError):
            pass
        result = parse(item.key).find(buffer)
        if len(result) == 0:
            return None
        return cls.convert_to_type(result[0].value, item)

    @classmethod
    def class_write_item(cls, item, value, buffer):
        if item.data_type == "DERIVED":
            return None
        try:
            decoded = json.loads(buffer.decode())
        except (UnicodeDecodeError, AttributeError):
            decoded = buffer
        except json.decoder.JSONDecodeError:
            decoded = {}

        print(f"json key:{item.key} value:{value} decoded:{decoded}")
        value = cls.convert_to_type(value, item)
        result = parse(item.key).update(decoded, value)

        if type(buffer) is bytearray:
            buffer[0:] = bytearray(json.dumps(result), encoding="utf-8")

    @classmethod
    def class_read_items(cls, items, buffer):
        try:
            buffer = json.loads(buffer.decode())
        except (UnicodeDecodeError, AttributeError):
            pass
        return super().class_read_items(items, buffer)

    @classmethod
    def class_write_items(cls, items, values, buffer):
        try:
            decoded = json.loads(buffer.decode())
        except (UnicodeDecodeError, AttributeError):
            decoded = buffer
        except json.decoder.JSONDecodeError:
            decoded = {}
        super().class_write_items(items, values, decoded)
        if type(buffer) is bytearray:
            buffer[0:] = bytearray(json.dumps(decoded), encoding="utf-8")

    def enforce_encoding(self):
        return None

    def enforce_length(self):
        return False

    def enforce_short_buffer_allowed(self):
        return True

    def enforce_derived_write_conversion(self, item):
        return True
