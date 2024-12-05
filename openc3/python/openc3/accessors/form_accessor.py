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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from .accessor import Accessor
import urllib.parse


class FormAccessor(Accessor):
    @classmethod
    def read_item(cls, item, buffer):
        ary = urllib.parse.parse_qsl(buffer)
        value = None
        for key, ary_value in ary:
            if key.decode() == item.key:
                # Handle the case of multiple values for the same key
                # and build up an array of values
                if value:
                    # Second time through value is not a list yet
                    if type(value) is not list:
                        value = [value]
                    value.append(ary_value)
                else:
                    value = ary_value
        return value

    @classmethod
    def write_item(cls, item, value, buffer):
        ary = urllib.parse.parse_qsl(buffer)
        # Remove existing item and bad keys from list
        ary = [ary_value for ary_value in ary if (ary_value[0] != item.key) and (str(ary_value[0])[0] != "\u0000")]

        if isinstance(value, list):
            for value_value in value:
                ary.append((item.key, value_value))
        else:
            ary.append((item.key, value))
        buffer[:] = urllib.parse.urlencode(ary).encode()
        return value

    # If this is set it will enforce that buffer data is encoded
    # in a specific encoding
    def enforce_encoding(self):
        return None

    # This affects whether the Packet class enforces the buffer
    # length at all.  Set to false to remove any correlation between
    # buffer length and defined sizes of items in COSMOS
    def enforce_length(self):
        return False

    # This sets the short_buffer_allowed flag in the Packet class
    # which allows packets that have a buffer shorter than the defined size.
    # Note that the buffer is still resized to the defined length
    def enforce_short_buffer_allowed(self):
        return True

    # If this is true it will enforce that COSMOS DERIVED items must have a
    # write_conversion to be written
    def enforce_derived_write_conversion(self, _item):
        return True
