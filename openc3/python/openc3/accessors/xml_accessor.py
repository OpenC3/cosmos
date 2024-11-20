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

from .accessor import Accessor
# HtmlAccessor uses lxml.html
import lxml.etree as ET


class XmlAccessor(Accessor):
    @classmethod
    def class_read_item(cls, item, buffer):
        if item.data_type == "DERIVED":
            return None
        doc = cls._buffer_to_doc(buffer)
        doc_value = doc.xpath(item.key)
        # The xpath method returns a boolean, float, string, or list of items
        # If it's a list then just grab the first value to convert
        if isinstance(doc_value, list):
            doc_value = doc_value[0]
        return cls.convert_to_type(doc_value, item)

    @classmethod
    def class_write_item(cls, item, value, buffer):
        if item.data_type == "DERIVED":
            return None
        doc = cls._buffer_to_doc(buffer)
        cls._update_doc(doc, item, value)
        buffer[0:] = cls._doc_to_buffer(doc)

    @classmethod
    def class_read_items(cls, items, buffer):
        doc = cls._buffer_to_doc(buffer)
        result = {}
        for item in items:
            if item.data_type == "DERIVED":
                result[item.name] = None
            else:
                doc_value = doc.xpath(item.key)
                # The xpath method returns a boolean, float, string, or list of items
                # If it's a list then just grab the first value to convert
                if isinstance(doc_value, list):
                    doc_value = doc_value[0]
                result[item.name] = cls.convert_to_type(doc_value, item)
        return result

    @classmethod
    def class_write_items(cls, items, values, buffer):
        doc = cls._buffer_to_doc(buffer)
        for index, item in enumerate(items):
            cls._update_doc(doc, item, values[index])
        buffer[0:] = cls._doc_to_buffer(doc)

    @classmethod
    def _buffer_to_doc(cls, buffer):
        return ET.fromstring(buffer.decode())

    @classmethod
    def _doc_to_buffer(cls, doc):
        return bytearray(ET.tostring(doc))

    @classmethod
    def _update_doc(cls, doc, item, value):
        # Split the attribute or text selector from the xpath so we get a
        # lxml.etree._Element that we can operate on. Otherwise we get a
        # lxml.etree._ElementUnicodeResult which is read-only.
        parts = item.key.split("/")
        path = "/".join(parts[0:-1])
        node = doc.xpath(path)[0]
        # Determine what the selector was trying to set
        if "@" in parts[-1]:
            node.attrib[parts[-1][1:]] = str(value)
        elif "text()" == parts[-1]:
            node.text = str(value)
        else:
            raise RuntimeError(f"Unknown selector: {item.key}")

    def enforce_encoding(self):
        return None

    def enforce_length(self):
        return False

    def enforce_short_buffer_allowed(self):
        return True

    def enforce_derived_write_conversion(self, item):
        return True
