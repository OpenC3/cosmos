#!/usr/bin/env python3

# Copyright 2023 OpenC3, Inc.
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

import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.accessors.xml_accessor import XmlAccessor
from collections import namedtuple


class TestXmlAccessor(unittest.TestCase):
    def setUp(self):
        self.data1 = bytearray(
            '<html><head><script src="test.js"></script><noscript>No Script Detected</noscript></head><body><img src="test.jpg"/><p><ul><li>1</li><li>3.14</li></ul></p></body></html>',
            encoding="utf-8",
        )
        self.Xml = namedtuple("Xml", ("name", "key", "data_type"))

    def test_should_handle_various_keys(self):
        item = self.Xml("ITEM", "/html/head/script/@src", "STRING")
        self.assertEqual(XmlAccessor.class_read_item(item, self.data1), "test.js")

        item = self.Xml("ITEM", "/html/head/noscript/text()", "STRING")
        self.assertEqual(
            XmlAccessor.class_read_item(item, self.data1), "No Script Detected"
        )

        item = self.Xml("ITEM", "/html/body/img/@src", "STRING")
        self.assertEqual(XmlAccessor.class_read_item(item, self.data1), "test.jpg")

        item = self.Xml("ITEM", "/html/body/p/ul/li[1]/text()", "UINT")
        self.assertEqual(XmlAccessor.class_read_item(item, self.data1), 1)

        item = self.Xml("ITEM", "/html/body/p/ul/li[2]/text()", "FLOAT")
        self.assertEqual(XmlAccessor.class_read_item(item, self.data1), 3.14)

    def test_should_read_a_collection_of_items(self):
        item1 = self.Xml("ITEM1", "/html/head/script/@src", "STRING")
        item2 = self.Xml("ITEM2", "/html/head/noscript/text()", "STRING")
        item3 = self.Xml("ITEM3", "/html/body/img/@src", "STRING")
        item4 = self.Xml("ITEM4", "/html/body/p/ul/li[1]/text()", "UINT")
        item5 = self.Xml("ITEM5", "/html/body/p/ul/li[2]/text()", "FLOAT")

        items = [item1, item2, item3, item4, item5]

        results = XmlAccessor.class_read_items(items, self.data1)
        self.assertEqual(results["ITEM1"], "test.js")
        self.assertEqual(results["ITEM2"], "No Script Detected")
        self.assertEqual(results["ITEM3"], "test.jpg")
        self.assertEqual(results["ITEM4"], 1)
        self.assertEqual(results["ITEM5"], 3.14)

    def test_should_write_different_types(self):
        item = self.Xml("ITEM", "/html/head/script/@src", "STRING")
        XmlAccessor.class_write_item(item, "different.js", self.data1)
        self.assertEqual(XmlAccessor.class_read_item(item, self.data1), "different.js")

        item = self.Xml("ITEM", "/html/head/noscript/text()", "STRING")
        XmlAccessor.class_write_item(item, "Nothing Here", self.data1)
        self.assertEqual(XmlAccessor.class_read_item(item, self.data1), "Nothing Here")

        item = self.Xml("ITEM", "/html/body/img/@src", "STRING")
        XmlAccessor.class_write_item(item, "other.png", self.data1)
        self.assertEqual(XmlAccessor.class_read_item(item, self.data1), "other.png")

        item = self.Xml("ITEM", "/html/body/p/ul/li[1]/text()", "UINT")
        XmlAccessor.class_write_item(item, 15, self.data1)
        self.assertEqual(XmlAccessor.class_read_item(item, self.data1), 15)

        item = self.Xml("ITEM", "/html/body/p/ul/li[2]/text()", "FLOAT")
        XmlAccessor.class_write_item(item, 1.234, self.data1)
        self.assertEqual(XmlAccessor.class_read_item(item, self.data1), 1.234)

    def test_should_write_multiple_items(self):
        item1 = self.Xml("ITEM1", "/html/head/script/@src", "STRING")
        item2 = self.Xml("ITEM2", "/html/head/noscript/text()", "STRING")
        item3 = self.Xml("ITEM3", "/html/body/img/@src", "STRING")
        item4 = self.Xml("ITEM4", "/html/body/p/ul/li[1]/text()", "UINT")
        item5 = self.Xml("ITEM5", "/html/body/p/ul/li[2]/text()", "FLOAT")

        items = [item1, item2, item3, item4, item5]
        values = ["different.js", "Nothing Here", "other.png", 15, 1.234]
        XmlAccessor.class_write_items(items, values, self.data1)

        self.assertEqual(XmlAccessor.class_read_item(item1, self.data1), "different.js")
        self.assertEqual(XmlAccessor.class_read_item(item2, self.data1), "Nothing Here")
        self.assertEqual(XmlAccessor.class_read_item(item3, self.data1), "other.png")
        self.assertEqual(XmlAccessor.class_read_item(item4, self.data1), 15)
        self.assertEqual(XmlAccessor.class_read_item(item5, self.data1), 1.234)
