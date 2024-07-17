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

import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.accessors.cbor_accessor import CborAccessor
from collections import namedtuple
from cbor2 import dumps, loads
from openc3.packets.packet import Packet
from openc3.packets.packet_item import PacketItem


class TestCborAccessor(unittest.TestCase):
    def setUp(self):
        self.rawData1 = {
            "packet": {
                "item1": 1,
                "item2": 1.234,
                "item3": "a string",
                "item4": [1, 2, 3, 4],
                "item5": {"another": "object"},
            }
        }
        self.data1 = bytearray(dumps(self.rawData1))
        self.data2 = bytearray(
            dumps(
                [
                    {
                        "packet": {
                            "item1": 1,
                            "item2": 1.234,
                            "item3": "a string",
                            "item4": [1, 2, 3, 4],
                            "item5": {"another": "object"},
                        }
                    },
                    {
                        "packet": {
                            "item1": 2,
                            "item2": 2.234,
                            "item3": "another string",
                            "item4": [5, 6, 7, 8],
                            "item5": {"another": "packet"},
                        }
                    },
                ]
            )
        )
        self.hash_data = bytearray(dumps({"test": "one"}))
        self.array_data = bytearray(dumps([4, 3, 2, 1]))
        self.Cbor = namedtuple("Cbor", ("name", "key", "data_type", "array_size"))

    def test_should_return_None_for_an_item_that_does_not_exist(self):
        item = self.Cbor("item", "$.packet.nope", "INT", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.hash_data), None)

    def test_should_write_into_a_packet(self):
        p = Packet("tgt", "pkt")
        pi = PacketItem("item1", 0, 16, "UINT", "BIG_ENDIAN")
        pi.key = "$.packet.item1"
        p.define(pi)
        pi = PacketItem("item2", 16, 32, "FLOAT", "BIG_ENDIAN")
        pi.key = "$.packet.item2"
        p.define(pi)
        pi = PacketItem("item3", 48, 128, "STRING", "BIG_ENDIAN")
        pi.key = "$.packet.item3"
        p.define(pi)
        pi = PacketItem("item4", 176, 8, "UINT", "BIG_ENDIAN", 32)
        pi.key = "$.packet.item4"
        p.define(pi)
        pi = PacketItem("item5", 184, 0, "BLOCK", "BIG_ENDIAN")
        pi.key = "$.packet.item5"
        p.define(pi)
        p.accessor = CborAccessor()
        p.template = self.data1
        p.restore_defaults()
        data = loads(p.buffer)
        self.assertEqual(data, self.rawData1)
        p.write("item1", 5)
        p.write("item2", 1.23)
        p.write("item3", "CBOR")
        p.write("item4", [1, 2, 3, 4])
        data = loads(p.buffer)
        self.assertEqual(data["packet"]["item1"], 5)
        self.assertEqual(data["packet"]["item2"], 1.23)
        self.assertEqual(data["packet"]["item3"], "CBOR")
        self.assertEqual(data["packet"]["item4"], [1, 2, 3, 4])

    def test_should_read_a_top_level_hash(self):
        item = self.Cbor("item", "$", "OBJECT", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.hash_data), ({"test": "one"}))

    def test_should_read_a_top_level_array(self):
        item = self.Cbor("item", "$", "INT", 32)
        self.assertEqual(CborAccessor.class_read_item(item, self.array_data), ([4, 3, 2, 1]))

    def test_should_handle_various_keys(self):
        item = self.Cbor("item", "$.packet.item1", "INT", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), 1)
        item = self.Cbor("item", "$.packet.item1", "FLOAT", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), 1.0)
        item = self.Cbor("item", "$.packet.item1", "STRING", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), "1")

        item = self.Cbor("item", "$.packet.item2", "INT", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), 1)
        item = self.Cbor("item", "$.packet.item2", "FLOAT", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), 1.234)
        item = self.Cbor("item", "$.packet.item2", "STRING", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), "1.234")

        item = self.Cbor("item", "$.packet.item3", "INT", None)
        with self.assertRaisesRegex(ValueError, "could not convert string to float"):
            CborAccessor.class_read_item(item, self.data1)
        item = self.Cbor("item", "$.packet.item3", "STRING", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), "a string")

        item = self.Cbor("item", "$.packet.item4", "INT", 32)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), [1, 2, 3, 4])
        item = self.Cbor("item", "$.packet.item4", "FLOAT", 32)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), [1.0, 2.0, 3.0, 4.0])
        item = self.Cbor("item", "$.packet.item4", "STRING", 32)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), ["1", "2", "3", "4"])

        item = self.Cbor("item", "$.packet.item5", "OBJECT", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), ({"another": "object"}))

        item = self.Cbor("item", "$.packet.item5.another", "STRING", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), "object")

        item = self.Cbor("item", "$.packet.item4[3]", "INT", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), 4)

        item = self.Cbor("item", "$[0].packet.item1", "UINT", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 1)

        item = self.Cbor("item", "$[0].packet.item2", "FLOAT", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 1.234)

        item = self.Cbor("item", "$[0].packet.item3", "STRING", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), "a string")

        item = self.Cbor("item", "$[0].packet.item4", "INT", 32)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), [1, 2, 3, 4])

        item = self.Cbor("item", "$[0].packet.item5", "OBJECT", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), ({"another": "object"}))

        item = self.Cbor("item", "$[0].packet.item5.another", "STRING", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), "object")

        item = self.Cbor("item", "$[0].packet.item4[3]", "INT", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 4)

        item = self.Cbor("item", "$[1].packet.item1", "UINT", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 2)

        item = self.Cbor("item", "$[1].packet.item2", "FLOAT", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 2.234)

        item = self.Cbor("item", "$[1].packet.item3", "STRING", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), "another string")

        item = self.Cbor("item", "$[1].packet.item4", "UINT", 32)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), [5, 6, 7, 8])

        item = self.Cbor("item", "$[1].packet.item5", "OBJECT", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), ({"another": "packet"}))

        item = self.Cbor("item", "$[1].packet.item5.another", "STRING", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), "packet")

        item = self.Cbor("item", "$[1].packet.item4[3]", "INT", None)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 8)

    def test_should_read_a_collection_of_items(self):
        item1 = self.Cbor("ITEM1", "$.packet.item1", "INT", None)
        item2 = self.Cbor("ITEM2", "$.packet.item2", "FLOAT", None)
        item3 = self.Cbor("ITEM3", "$.packet.item3", "STRING", None)
        item4 = self.Cbor("ITEM4", "$.packet.item4", "INT", 32)
        item5 = self.Cbor("ITEM5", "$.packet.item5", "OBJECT", None)
        item6 = self.Cbor("ITEM6", "$.packet.item5.another", "STRING", None)
        item7 = self.Cbor("ITEM7", "$.packet.item4[3]", "UINT", None)

        result = CborAccessor.class_read_items([item1, item2, item3, item4, item5, item6, item7], self.data1)
        self.assertEqual(len(result), 7)
        self.assertEqual(result["ITEM1"], 1)
        self.assertEqual(result["ITEM2"], 1.234)
        self.assertEqual(result["ITEM3"], "a string")
        self.assertEqual(result["ITEM4"], [1, 2, 3, 4])
        self.assertEqual(result["ITEM5"], ({"another": "object"}))
        self.assertEqual(result["ITEM6"], "object")
        self.assertEqual(result["ITEM7"], 4)

        item1 = self.Cbor("ITEM1", "$[0].packet.item1", "INT", None)
        item2 = self.Cbor("ITEM2", "$[0].packet.item2", "FLOAT", None)
        item3 = self.Cbor("ITEM3", "$[0].packet.item3", "STRING", None)
        item4 = self.Cbor("ITEM4", "$[0].packet.item4", "INT", 32)
        item5 = self.Cbor("ITEM5", "$[0].packet.item5", "OBJECT", None)
        item6 = self.Cbor("ITEM6", "$[0].packet.item5.another", "STRING", None)
        item7 = self.Cbor("ITEM7", "$[0].packet.item4[3]", "INT", None)
        item8 = self.Cbor("ITEM8", "$[1].packet.item1", "UINT", None)
        item9 = self.Cbor("ITEM9", "$[1].packet.item2", "FLOAT", None)
        item10 = self.Cbor("ITEM10", "$[1].packet.item3", "STRING", None)
        item11 = self.Cbor("ITEM11", "$[1].packet.item4", "INT", 32)
        item12 = self.Cbor("ITEM12", "$[1].packet.item5", "OBJECT", None)
        item13 = self.Cbor("ITEM13", "$[1].packet.item5.another", "STRING", None)
        item14 = self.Cbor("ITEM14", "$[1].packet.item4[3]", "INT", None)

        result = CborAccessor.class_read_items(
            [
                item1,
                item2,
                item3,
                item4,
                item5,
                item6,
                item7,
                item8,
                item9,
                item10,
                item11,
                item12,
                item13,
                item14,
            ],
            self.data2,
        )
        self.assertEqual(len(result), 14)
        self.assertEqual(result["ITEM1"], 1)
        self.assertEqual(result["ITEM2"], 1.234)
        self.assertEqual(result["ITEM3"], "a string")
        self.assertEqual(result["ITEM4"], [1, 2, 3, 4])
        self.assertEqual(result["ITEM5"], ({"another": "object"}))
        self.assertEqual(result["ITEM6"], "object")
        self.assertEqual(result["ITEM7"], 4)
        self.assertEqual(result["ITEM8"], 2)
        self.assertEqual(result["ITEM9"], 2.234)
        self.assertEqual(result["ITEM10"], "another string")
        self.assertEqual(result["ITEM11"], [5, 6, 7, 8])
        self.assertEqual(result["ITEM12"], ({"another": "packet"}))
        self.assertEqual(result["ITEM13"], "packet")
        self.assertEqual(result["ITEM14"], 8)

    def test_should_write_different_types(self):
        item = self.Cbor("item", "$.packet.item1", "INT", None)
        CborAccessor.class_write_item(item, 3, self.data1)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), 3)

        item = self.Cbor("item", "$.packet.item2", "FLOAT", None)
        CborAccessor.class_write_item(item, 3.14, self.data1)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), 3.14)

        item = self.Cbor("item", "$.packet.item3", "STRING", None)
        CborAccessor.class_write_item(item, "something different", self.data1)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), "something different")

        item = self.Cbor("item", "$.packet.item4", "INT", 32)
        CborAccessor.class_write_item(item, [7, 8, 9, 10], self.data1)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), [7, 8, 9, 10])

        item = self.Cbor("item", "$.packet.item5", "OBJECT", None)
        CborAccessor.class_write_item(item, {"good": "times"}, self.data1)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), ({"good": "times"}))

        item = self.Cbor("item", "$.packet.item5.good", "STRING", None)
        CborAccessor.class_write_item(item, "friends", self.data1)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), "friends")

        item = self.Cbor("item", "$.packet.item4[3]", "INT", None)
        CborAccessor.class_write_item(item, 15, self.data1)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), 15)

        item = self.Cbor("item", "$[0].packet.item1", "INT", None)
        CborAccessor.class_write_item(item, 5, self.data2)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 5)

        item = self.Cbor("item", "$[0].packet.item2", "FLOAT", None)
        CborAccessor.class_write_item(item, 5.05, self.data2)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 5.05)

        item = self.Cbor("item", "$[0].packet.item3", "STRING", None)
        CborAccessor.class_write_item(item, "something", self.data2)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), "something")

        item = self.Cbor("item", "$[0].packet.item4", "STRING", None)
        CborAccessor.class_write_item(item, "string", self.data2)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), "string")

        item = self.Cbor("item", "$[0].packet.item5", "OBJECT", None)
        CborAccessor.class_write_item(item, {"bill": "ted"}, self.data2)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), ({"bill": "ted"}))

        # TODO: This doesn't work because the above overwrites the item5
        # Ruby seems to add but Python replaces ...
        # item = self.Cbor("item", "$[0].packet.item5.another", "STRING", None)
        # CborAccessor.class_write_item(item, "money", self.data2)
        # self.assertEqual(CborAccessor.class_read_item(item, self.data2), "money")

        # TODO: This doesn't work because the above overwrites the item5
        # item = self.Cbor("item", "$[0].packet.item4[3]", "STRING", None)
        # CborAccessor.class_write_item(item, 25, self.data2)
        # self.assertEqual(CborAccessor.class_read_item(item, self.data2), 25)

        item = self.Cbor("item", "$[1].packet.item1", "INT", None)
        CborAccessor.class_write_item(item, 7, self.data2)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 7)

        item = self.Cbor("item", "$[1].packet.item2", "FLOAT", None)
        CborAccessor.class_write_item(item, 3.13, self.data2)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 3.13)

        item = self.Cbor("item", "$[1].packet.item3", "STRING", None)
        CborAccessor.class_write_item(item, "small", self.data2)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), "small")

        item = self.Cbor("item", "$[1].packet.item4", "INT", 32)
        CborAccessor.class_write_item(item, [101, 102, 103, 104], self.data2)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), [101, 102, 103, 104])

        item = self.Cbor("item", "$[1].packet.item5", "OBJECT", None)
        CborAccessor.class_write_item(item, {"happy": "sad"}, self.data2)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), ({"happy": "sad"}))

        item = self.Cbor("item", "$[1].packet.item5.happy", "OBJECT", None)
        CborAccessor.class_write_item(item, "art", self.data2)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), "art")

        item = self.Cbor("item", "$[1].packet.item4[3]", "INT", None)
        CborAccessor.class_write_item(item, 14, self.data2)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 14)

    def test_should_write_multiple_items(self):
        item1 = self.Cbor("item1", "$.packet.item1", "INT", None)
        item2 = self.Cbor("item2", "$.packet.item2", "FLOAT", None)
        item3 = self.Cbor("item3", "$.packet.item3", "STRING", None)
        item4 = self.Cbor("item4", "$.packet.item4", "UINT", 32)
        item5 = self.Cbor("item5", "$.packet.item5", "OBJECT", None)
        item6 = self.Cbor("item6", "$.packet.item5.good", "STRING", None)
        item7 = self.Cbor("item7", "$.packet.item4[3]", "UINT", None)

        items = [item1, item2, item3, item4, item5, item6, item7]
        values = [
            3,
            3.14,
            "something different",
            [7, 8, 9, 10],
            {"good": "friends"},
            "friends",
            15,
        ]
        CborAccessor.class_write_items(items, values, self.data1)
        self.assertEqual(CborAccessor.class_read_item(item1, self.data1), 3)
        self.assertEqual(CborAccessor.class_read_item(item2, self.data1), 3.14)
        self.assertEqual(CborAccessor.class_read_item(item3, self.data1), "something different")
        # item7 writes 15 over the 10 in the array
        self.assertEqual(CborAccessor.class_read_item(item4, self.data1), [7, 8, 9, 15])
        self.assertEqual(CborAccessor.class_read_item(item5, self.data1), ({"good": "friends"}))
        self.assertEqual(CborAccessor.class_read_item(item6, self.data1), "friends")
        self.assertEqual(CborAccessor.class_read_item(item7, self.data1), 15)

        item1 = self.Cbor("item1", "$[0].packet.item1", "INT", None)
        item2 = self.Cbor("item2", "$[0].packet.item2", "FLOAT", None)
        item3 = self.Cbor("item3", "$[0].packet.item3", "STRING", None)
        item4 = self.Cbor("item4", "$[0].packet.item4", "INT", 32)
        item5 = self.Cbor("item5", "$[0].packet.item5", "OBJECT", None)
        item6 = self.Cbor("item6", "$[0].packet.item5.bill", "STRING", None)
        item7 = self.Cbor("item7", "$[0].packet.item4[3]", "INT", None)
        item8 = self.Cbor("item8", "$[1].packet.item1", "UINT", None)
        item9 = self.Cbor("item9", "$[1].packet.item2", "FLOAT", None)
        item10 = self.Cbor("item10", "$[1].packet.item3", "STRING", None)
        item11 = self.Cbor("item11", "$[1].packet.item4", "INT", 32)
        item12 = self.Cbor("item12", "$[1].packet.item5", "OBJECT", None)
        item13 = self.Cbor("item13", "$[1].packet.item5.happy", "STRING", None)
        item14 = self.Cbor("item14", "$[1].packet.item4[3]", "INT", None)

        items = [
            item1,
            item2,
            item3,
            item4,
            item5,
            item6,
            item7,
            item8,
            item9,
            item10,
            item11,
            item12,
            item13,
            item14,
        ]
        values = [
            5,
            5.05,
            "something",
            [1, 2, 3, 4],
            {"bill": "ted"},
            "money",
            25,
            7,
            3.13,
            "small",
            [101, 102, 103, 104],
            {"happy": "sad"},
            "art",
            14,
        ]
        CborAccessor.class_write_items(items, values, self.data2)
        self.assertEqual(CborAccessor.class_read_item(item1, self.data2), 5)
        self.assertEqual(CborAccessor.class_read_item(item2, self.data2), 5.05)
        self.assertEqual(CborAccessor.class_read_item(item3, self.data2), "something")
        # Item7 writes 25 over the 4 in the array
        self.assertEqual(CborAccessor.class_read_item(item4, self.data2), [1, 2, 3, 25])
        self.assertEqual(
            CborAccessor.class_read_item(item5, self.data2),
            # Item6 writes 'money' over 'ted'
            ({"bill": "money"}),
        )
        self.assertEqual(CborAccessor.class_read_item(item6, self.data2), "money")
        self.assertEqual(CborAccessor.class_read_item(item7, self.data2), 25)
        self.assertEqual(CborAccessor.class_read_item(item8, self.data2), 7)
        self.assertEqual(CborAccessor.class_read_item(item9, self.data2), 3.13)
        self.assertEqual(CborAccessor.class_read_item(item10, self.data2), "small")
        # Item14 writes 14 over the 104 in the array
        self.assertEqual(CborAccessor.class_read_item(item11, self.data2), [101, 102, 103, 14])
        self.assertEqual(
            CborAccessor.class_read_item(item12, self.data2),
            # Item13 writes 'art' over 'sad'
            ({"happy": "art"}),
        )
        self.assertEqual(CborAccessor.class_read_item(item13, self.data2), "art")
        self.assertEqual(CborAccessor.class_read_item(item14, self.data2), 14)
