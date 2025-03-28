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
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1953

import re
from .accessor import Accessor
from openc3.top_level import get_class_from_module
from openc3.utilities.string import class_name_to_filename, filename_to_module, filename_to_class_name


class HttpAccessor(Accessor):
    def __init__(self, packet, body_accessor="openc3/accessors/form_accessor.py", *body_accessor_args):
        super().__init__(packet)
        self.args.append(body_accessor)
        for arg in body_accessor_args:
            self.args.append(arg)
        try:
            klass = get_class_from_module(
                filename_to_module(body_accessor),
                filename_to_class_name(body_accessor),
            )
        # Fall back to the deprecated behavior of passing the ClassName
        except ModuleNotFoundError:
            filename = class_name_to_filename(body_accessor)
            klass = get_class_from_module(f"openc3.accessors.{filename}", body_accessor)

        self.body_accessor = klass(packet, *body_accessor_args)

    def read_item(self, item, buffer):
        if item.name in [
            "HTTP_STATUS",
            "HTTP_PATH",
            "HTTP_METHOD",
            "HTTP_PACKET",
            "HTTP_ERROR_PACKET",
        ]:
            if not self.packet.extra:
                return None
            return self.packet.extra[item.name]

        item_name = item.name
        if re.match(r"^HTTP_QUERY_", item_name):
            if not self.packet.extra:
                return None
            if re.match(r"^HTTP_QUERY_", item.key):
                query_name = item_name[11:].lower()
            else:
                query_name = item.key
            queries = self.packet.extra.get("HTTP_QUERIES")
            if queries:
                return queries[query_name]
            else:
                return None

        if re.match(r"^HTTP_HEADER_", item_name):
            if not self.packet.extra:
                return None
            if re.match(r"^HTTP_HEADER_", item.key):
                header_name = item_name[12:].lower()
            else:
                header_name = item.key
            headers = self.packet.extra.get("HTTP_HEADERS")
            if headers:
                return headers[header_name]
            else:
                return None

        return self.body_accessor.read_item(item, buffer)

    def write_item(self, item, value, buffer):
        if item.name == "HTTP_STATUS":
            self.packet.extra = self.packet.extra or {}
            self.packet.extra[item.name] = int(value)
            return self.packet.extra[item.name]

        if item.name in [
            "HTTP_PATH",
            "HTTP_METHOD",
            "HTTP_PACKET",
            "HTTP_ERROR_PACKET",
        ]:
            self.packet.extra = self.packet.extra or {}
            value = str(value)
            if item.name == "HTTP_METHOD":
                value = value.lower()
            elif item.name in ["HTTP_PACKET", "HTTP_ERROR_PACKET"]:
                value = value.upper()
            self.packet.extra[item.name] = value
            return self.packet.extra[item.name]

        item_name = item.name
        if re.match(r"^HTTP_QUERY_", item_name):
            self.packet.extra = self.packet.extra or {}
            if re.match(r"^HTTP_QUERY_", item.key):
                query_name = item_name[11:].lower()
            else:
                query_name = item.key
            self.packet.extra["HTTP_QUERIES"] = self.packet.extra.get("HTTP_QUERIES", {})
            queries = self.packet.extra["HTTP_QUERIES"]
            queries[query_name] = str(value)
            return queries[query_name]

        if re.match(r"^HTTP_HEADER_", item_name):
            self.packet.extra = self.packet.extra or {}
            if re.match(r"^HTTP_HEADER_", item.key):
                header_name = item_name[12:].lower()
            else:
                header_name = item.key
            self.packet.extra["HTTP_HEADERS"] = self.packet.extra.get("HTTP_HEADERS", {})
            headers = self.packet.extra["HTTP_HEADERS"]
            headers[header_name] = str(value)
            return headers[header_name]

        self.body_accessor.write_item(item, value, buffer)
        return value

    def read_items(self, items, buffer):
        result = {}
        body_items = []
        for item in items:
            if item.name[0:4] == "HTTP_":
                result[item.name] = self.read_item(item, buffer)
            else:
                body_items.append(item)
        body_result = self.body_accessor.read_items(body_items, buffer)
        return result | body_result  # Merge Body accessor read items with HTTP_ items

    def write_items(self, items, values, buffer):
        body_items = []
        for item, index in enumerate(items):
            if item.name[0:4] == "HTTP_":
                self.write_item(item, values[index], buffer)
            else:
                body_items.append(item)
        self.body_accessor.write_items(body_items, values, buffer)
        return values

    # If this is set it will enforce that buffer data is encoded
    # in a specific encoding
    def enforce_encoding(self):
        return self.body_accessor.enforce_encoding()

    # This affects whether the Packet class enforces the buffer
    # length at all.  Set to false to remove any correlation between
    # buffer length and defined sizes of items in COSMOS
    def enforce_length(self):
        return self.body_accessor.enforce_length()

    # This sets the short_buffer_allowed flag in the Packet class
    # which allows packets that have a buffer shorter than the defined size.
    # Note that the buffer is still resized to the defined length
    def enforce_short_buffer_allowed(self):
        return self.body_accessor.enforce_short_buffer_allowed()

    # If this is true it will enforce that COSMOS DERIVED items must have a
    # write_conversion to be written
    def enforce_derived_write_conversion(self, item):
        if item.name in [
            "HTTP_STATUS",
            "HTTP_PATH",
            "HTTP_METHOD",
            "HTTP_PACKET",
            "HTTP_ERROR_PACKET",
        ]:
            return False
        if re.match(r"^HTTP_QUERY_", item.name) or re.match(r"^HTTP_HEADER_", item.name):
            return False

        return self.body_accessor.enforce_derived_write_conversion(item)
