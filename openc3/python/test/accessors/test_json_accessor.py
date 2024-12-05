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
from openc3.accessors.json_accessor import JsonAccessor
from collections import namedtuple
from openc3.packets.packet import Packet
from openc3.packets.packet_item import PacketItem

class TestJsonAccessor(unittest.TestCase):
    def setUp(self):
        self.data1 = bytearray(
            '{ "packet": {"item1": 1, "item2": 1.234, "item3": "a string", "item4": [1, 2, 3, 4], "item5": {"another": "object"}} }',
            encoding="utf-8",
        )
        self.data2 = bytearray(
            '[ { "packet": {"item1": 1, "item2": 1.234, "item3": "a string", "item4": [1, 2, 3, 4], "item5": {"another": "object"}} }, { "packet": {"item1": 2, "item2": 2.234, "item3": "another string", "item4": [5, 6, 7, 8], "item5": {"another": "packet"}} }]',
            encoding="utf-8",
        )
        self.hash_data = bytearray('{"test":"one"}', encoding="utf-8")
        self.array_data = bytearray("[4, 3, 2, 1]", encoding="utf-8")
        self.Json = namedtuple("Json", ("name", "key", "data_type", "array_size"))

    def test_should_return_None_for_an_item_that_does_not_exist(self):
        item = self.Json("item", "$.packet.nope", "INT", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.hash_data), None)

    def test_should_write_into_a_packet(self):
        p = Packet("tgt", "pkt")
        pi = PacketItem("item1", 0, 16, "UINT", "BIG_ENDIAN")
        pi.key = "$.item1"
        p.define(pi)
        pi = PacketItem("item2", 16, 16, "UINT", "BIG_ENDIAN")
        pi.key = "$.more.item2"
        p.define(pi)
        pi = PacketItem("item3", 32, 64, "FLOAT", "BIG_ENDIAN")
        pi.key = "$.more.item3"
        p.define(pi)
        pi = PacketItem("item4", 96, 128, "STRING", "BIG_ENDIAN")
        pi.key = "$.more.item4"
        p.define(pi)
        pi = PacketItem("item5", 224, 8, "UINT", "BIG_ENDIAN", 0)
        pi.key = "$.more.item5"
        p.define(pi)
        p.accessor = JsonAccessor()
        p.template = b'{"id_item":1, "item1":101, "more": { "item2":12, "item3":3.14, "item4":"Example", "item5":[4, 3, 2, 1] } }'
        p.restore_defaults()
        self.assertEqual(
            p.buffer,
            # The formatting of this string has to be precise
            bytearray(
                b'{"id_item":1, "item1":101, "more": { "item2":12, "item3":3.14, "item4":"Example", "item5":[4, 3, 2, 1] } }'
            ),
        )
        p.write("item1", 5)
        p.write("item2", 888)
        p.write("item3", 1.23)
        p.write("item4", "JSON")
        p.write("item5", [1, 2, 3, 4])
        self.assertEqual(
            p.buffer,
            # The formatting of this string has to be precise
            bytearray(
                b'{"id_item": 1, "item1": 5, "more": {"item2": 888, "item3": 1.23, "item4": "JSON", "item5": [1, 2, 3, 4]}}'
            ),
        )

    def test_should_read_a_top_level_hash(self):
        item = self.Json("item", "$", "OBJECT", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.hash_data), {"test": "one"})

    def test_should_read_a_top_level_array(self):
        item = self.Json("item", "$", "INT", 32)
        self.assertEqual(JsonAccessor.class_read_item(item, self.array_data), [4, 3, 2, 1])

    def test_should_write_json(self):
        data = b'{"id_item":1, "item1":101, "more": { "item2":12, "item3":3.14, "item4":"Example", "item5":[4, 3, 2, 1] } }'
        item = self.Json("item", "$.packet.item1", "DERIVED", None)
        self.assertEqual(JsonAccessor.class_write_item(item, 3, data), None)

    def test_should_write_into_empty_array(self):
        data = bytearray(b'{"params": []}')
        item = self.Json("item", "$.params[0]", "STRING", None)
        JsonAccessor.class_write_item(item, "TARGET", data)
        self.assertEqual(JsonAccessor.class_read_item(item, data), "TARGET")
        self.assertEqual(data, bytearray(b'{"params": ["TARGET"]}'))

    def test_should_handle_various_keys(self):
        item = self.Json("item", "$.packet.item1", "INT", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data1), 1)

        item = self.Json("item", "$.packet.item2", "FLOAT", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data1), 1.234)

        item = self.Json("item", "$.packet.item3", "STRING", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data1), "a string")

        item = self.Json("item", "$.packet.item4", "INT", 32)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data1), [1, 2, 3, 4])

        item = self.Json("item", "$.packet.item5", "OBJECT", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data1), ({"another": "object"}))

        item = self.Json("item", "$.packet.item5.another", "STRING", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data1), "object")

        item = self.Json("item", "$.packet.item4[3]", "INT", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data1), 4)

        item = self.Json("item", "$[0].packet.item1", "UINT", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), 1)

        item = self.Json("item", "$[0].packet.item2", "FLOAT", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), 1.234)

        item = self.Json("item", "$[0].packet.item3", "STRING", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), "a string")

        item = self.Json("item", "$[0].packet.item4", "INT", 32)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), [1, 2, 3, 4])

        item = self.Json("item", "$[0].packet.item5", "OBJECT", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), ({"another": "object"}))

        item = self.Json("item", "$[0].packet.item5.another", "STRING", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), "object")

        item = self.Json("item", "$[0].packet.item4[3]", "INT", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), 4)

        item = self.Json("item", "$[1].packet.item1", "UINT", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), 2)

        item = self.Json("item", "$[1].packet.item2", "FLOAT", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), 2.234)

        item = self.Json("item", "$[1].packet.item3", "STRING", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), "another string")

        item = self.Json("item", "$[1].packet.item4", "INT", 32)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), [5, 6, 7, 8])

        item = self.Json("item", "$[1].packet.item5", "OBJECT", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), ({"another": "packet"}))

        item = self.Json("item", "$[1].packet.item5.another", "STRING", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), "packet")

        item = self.Json("item", "$[1].packet.item4[3]", "INT", None)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), 8)

    def test_should_read_a_collection_of_items(self):
        item1 = self.Json("ITEM1", "$.packet.item1", "INT", None)
        item2 = self.Json("ITEM2", "$.packet.item2", "FLOAT", None)
        item3 = self.Json("ITEM3", "$.packet.item3", "STRING", None)
        item4 = self.Json("ITEM4", "$.packet.item4", "INT", 32)
        item5 = self.Json("ITEM5", "$.packet.item5", "OBJECT", None)
        item6 = self.Json("ITEM6", "$.packet.item5.another", "STRING", None)
        item7 = self.Json("ITEM7", "$.packet.item4[3]", "UINT", None)

        result = JsonAccessor.class_read_items([item1, item2, item3, item4, item5, item6, item7], self.data1)
        self.assertEqual(len(result), 7)
        self.assertEqual(result["ITEM1"], 1)
        self.assertEqual(result["ITEM2"], 1.234)
        self.assertEqual(result["ITEM3"], "a string")
        self.assertEqual(result["ITEM4"], [1, 2, 3, 4])
        self.assertEqual(result["ITEM5"], ({"another": "object"}))
        self.assertEqual(result["ITEM6"], "object")
        self.assertEqual(result["ITEM7"], 4)

        item1 = self.Json("ITEM1", "$[0].packet.item1", "INT", None)
        item2 = self.Json("ITEM2", "$[0].packet.item2", "FLOAT", None)
        item3 = self.Json("ITEM3", "$[0].packet.item3", "STRING", None)
        item4 = self.Json("ITEM4", "$[0].packet.item4", "INT", 32)
        item5 = self.Json("ITEM5", "$[0].packet.item5", "OBJECT", None)
        item6 = self.Json("ITEM6", "$[0].packet.item5.another", "STRING", None)
        item7 = self.Json("ITEM7", "$[0].packet.item4[3]", "INT", None)
        item8 = self.Json("ITEM8", "$[1].packet.item1", "UINT", None)
        item9 = self.Json("ITEM9", "$[1].packet.item2", "FLOAT", None)
        item10 = self.Json("ITEM10", "$[1].packet.item3", "STRING", None)
        item11 = self.Json("ITEM11", "$[1].packet.item4", "INT", 32)
        item12 = self.Json("ITEM12", "$[1].packet.item5", "OBJECT", None)
        item13 = self.Json("ITEM13", "$[1].packet.item5.another", "STRING", None)
        item14 = self.Json("ITEM14", "$[1].packet.item4[3]", "INT", None)

        result = JsonAccessor.class_read_items(
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
        # DERIVED items aren't actually written
        item = self.Json("item", "$.packet.item1", "DERIVED", None)
        self.assertEqual(JsonAccessor.class_write_item(item, 3, self.data1), None)
        # Reading DERIVED items always returns None
        self.assertEqual(JsonAccessor.class_read_item(item, self.data1), None)
        json_data = json.loads(self.data1)
        self.assertEqual(json_data["packet"]["item1"], 1)

        item = self.Json("item", "$.packet.item1", "UINT", None)
        JsonAccessor.class_write_item(item, 3, self.data1)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data1), 3)
        json_data = json.loads(self.data1)
        self.assertEqual(json_data["packet"]["item1"], 3)

        item = self.Json("item", "$.packet.item1", "FLOAT", None)
        JsonAccessor.class_write_item(item, 3, self.data1)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data1), 3.0)
        json_data = json.loads(self.data1)
        self.assertEqual(json_data["packet"]["item1"], 3.0)

        item = self.Json("item", "$.packet.item1", "STRING", None)
        JsonAccessor.class_write_item(item, 3, self.data1)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data1), "3")
        json_data = json.loads(self.data1)
        self.assertEqual(json_data["packet"]["item1"], "3")

        item = self.Json("item", "$.packet.item2", "FLOAT", None)
        JsonAccessor.class_write_item(item, 3.14, self.data1)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data1), 3.14)

        item = self.Json("item", "$.packet.item3", "STRING", None)
        JsonAccessor.class_write_item(item, "something different", self.data1)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data1), "something different")

        item = self.Json("item", "$.packet.item4", "UINT", 32)
        JsonAccessor.class_write_item(item, [7, 8, 9, 10], self.data1)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data1), [7, 8, 9, 10])

        item = self.Json("item", "$.packet.item5", "STRING", None)
        JsonAccessor.class_write_item(item, {"good": "times"}, self.data1)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data1), ("{'good': 'times'}"))

        # item = self.Json("item", "$.packet.item5.good", "STRING")
        # JsonAccessor.class_write_item(item, "friends", self.data1)
        # self.assertEqual(JsonAccessor.class_read_item(item, self.data1), "friends")

        item = self.Json("item", "$.packet.item4[3]", "INT", None)
        JsonAccessor.class_write_item(item, 15, self.data1)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data1), 15)

        item = self.Json("item", "$[0].packet.item1", "INT", None)
        JsonAccessor.class_write_item(item, 5, self.data2)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), 5)

        item = self.Json("item", "$[0].packet.item2", "FLOAT", None)
        JsonAccessor.class_write_item(item, 5.05, self.data2)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), 5.05)

        item = self.Json("item", "$[0].packet.item3", "STRING", None)
        JsonAccessor.class_write_item(item, "something", self.data2)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), "something")

        item = self.Json("item", "$[0].packet.item4", "STRING", None)
        JsonAccessor.class_write_item(item, "string", self.data2)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), "string")

        item = self.Json("item", "$[0].packet.item5", "OBJECT", None)
        JsonAccessor.class_write_item(item, {"bill": "ted"}, self.data2)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), ({"bill": "ted"}))

        # TODO: This doesn't work because the above overwrites the item5
        # Ruby seems to add but Python replaces ...
        # item = self.Json("item", "$[0].packet.item5.another", "STRING")
        # JsonAccessor.class_write_item(item, "money", self.data2)
        # self.assertEqual(JsonAccessor.class_read_item(item, self.data2), "money")

        # TODO: This doesn't work because the above overwrites the item5
        # item = self.Json("item", "$[0].packet.item4[3]", "STRING")
        # JsonAccessor.class_write_item(item, 25, self.data2)
        # self.assertEqual(JsonAccessor.class_read_item(item, self.data2), 25)

        item = self.Json("item", "$[1].packet.item1", "UINT", None)
        JsonAccessor.class_write_item(item, 7, self.data2)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), 7)

        item = self.Json("item", "$[1].packet.item2", "FLOAT", None)
        JsonAccessor.class_write_item(item, 3.13, self.data2)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), 3.13)

        item = self.Json("item", "$[1].packet.item3", "STRING", None)
        JsonAccessor.class_write_item(item, "small", self.data2)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), "small")

        item = self.Json("item", "$[1].packet.item4", "INT", 32)
        JsonAccessor.class_write_item(item, [101, 102, 103, 104], self.data2)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), [101, 102, 103, 104])

        item = self.Json("item", "$[1].packet.item5", "OBJECT", None)
        JsonAccessor.class_write_item(item, {"happy": "sad"}, self.data2)
        self.assertEqual(JsonAccessor.class_read_item(item, self.data2), ({"happy": "sad"}))

        # item = self.Json("item", "$[1].packet.item5.another", "STRING")
        # JsonAccessor.class_write_item(item, "art", self.data2)
        # self.assertEqual(JsonAccessor.class_read_item(item, self.data2), "art")

        # item = self.Json("item", "$[1].packet.item4[3]", "STRING")
        # JsonAccessor.class_write_item(item, 14, self.data2)
        # self.assertEqual(JsonAccessor.class_read_item(item, self.data2), 14)

    def test_should_write_multiple_items(self):
        item1 = self.Json("item1", "$.packet.item1", "INT", None)
        item2 = self.Json("item2", "$.packet.item2", "FLOAT", None)
        item3 = self.Json("item3", "$.packet.item3", "STRING", None)
        item4 = self.Json("item4", "$.packet.item4", "INT", 32)
        item5 = self.Json("item5", "$.packet.item5", "OBJECT", None)
        item6 = self.Json("item6", "$.packet.item5.good", "STRING", None)
        item7 = self.Json("item7", "$.packet.item4[3]", "UINT", None)

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
        JsonAccessor.class_write_items(items, values, self.data1)
        self.assertEqual(JsonAccessor.class_read_item(item1, self.data1), 3)
        self.assertEqual(JsonAccessor.class_read_item(item2, self.data1), 3.14)
        self.assertEqual(JsonAccessor.class_read_item(item3, self.data1), "something different")
        # item7 writes 15 over the 10 in the array
        self.assertEqual(JsonAccessor.class_read_item(item4, self.data1), [7, 8, 9, 15])
        self.assertEqual(JsonAccessor.class_read_item(item5, self.data1), ({"good": "friends"}))
        self.assertEqual(JsonAccessor.class_read_item(item6, self.data1), "friends")
        self.assertEqual(JsonAccessor.class_read_item(item7, self.data1), 15)

        item1 = self.Json("item1", "$[0].packet.item1", "INT", None)
        item2 = self.Json("item2", "$[0].packet.item2", "FLOAT", None)
        item3 = self.Json("item3", "$[0].packet.item3", "STRING", None)
        item4 = self.Json("item4", "$[0].packet.item4", "INT", 32)
        item5 = self.Json("item5", "$[0].packet.item5", "OBJECT", None)
        # Select item5.bill because we write {"bill": "ted"}
        item6 = self.Json("item6", "$[0].packet.item5.bill", "STRING", None)
        item7 = self.Json("item7", "$[0].packet.item4[3]", "INT", None)
        item8 = self.Json("item8", "$[1].packet.item1", "UINT", None)
        item9 = self.Json("item9", "$[1].packet.item2", "FLOAT", None)
        item10 = self.Json("item10", "$[1].packet.item3", "STRING", None)
        item11 = self.Json("item11", "$[1].packet.item4", "INT", 32)
        item12 = self.Json("item12", "$[1].packet.item5", "OBJECT", None)
        # Select item5.happy because we write {"happy": "sad"}
        item13 = self.Json("item13", "$[1].packet.item5.happy", "STRING", None)
        item14 = self.Json("item14", "$[1].packet.item4[3]", "INT", None)

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
        JsonAccessor.class_write_items(items, values, self.data2)
        self.assertEqual(JsonAccessor.class_read_item(item1, self.data2), 5)
        self.assertEqual(JsonAccessor.class_read_item(item2, self.data2), 5.05)
        self.assertEqual(JsonAccessor.class_read_item(item3, self.data2), "something")
        # Item7 writes 25 over the 4 in the array
        self.assertEqual(JsonAccessor.class_read_item(item4, self.data2), [1, 2, 3, 25])
        self.assertEqual(
            JsonAccessor.class_read_item(item5, self.data2),
            # Item6 writes 'money' over 'ted'
            ({"bill": "money"}),
        )
        self.assertEqual(JsonAccessor.class_read_item(item6, self.data2), "money")
        self.assertEqual(JsonAccessor.class_read_item(item7, self.data2), 25)
        self.assertEqual(JsonAccessor.class_read_item(item8, self.data2), 7)
        self.assertEqual(JsonAccessor.class_read_item(item9, self.data2), 3.13)
        self.assertEqual(JsonAccessor.class_read_item(item10, self.data2), "small")
        # Item14 writes 14 over the 104 in the array
        self.assertEqual(JsonAccessor.class_read_item(item11, self.data2), [101, 102, 103, 14])
        self.assertEqual(
            JsonAccessor.class_read_item(item12, self.data2),
            # Item13 writes 'art' over 'sad'
            ({"happy": "art"}),
        )
        self.assertEqual(JsonAccessor.class_read_item(item13, self.data2), "art")
        self.assertEqual(JsonAccessor.class_read_item(item14, self.data2), 14)
