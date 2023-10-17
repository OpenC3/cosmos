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
from openc3.accessors.cbor_accessor import CborAccessor
from collections import namedtuple
from cbor2 import dumps


class TestCborAccessor(unittest.TestCase):
    def setUp(self):
        self.data1 = bytearray(
            dumps(
                {
                    "packet": {
                        "item1": 1,
                        "item2": 1.234,
                        "item3": "a string",
                        "item4": [1, 2, 3, 4],
                        "item5": {"another": "object"},
                    }
                }
            )
        )
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
        self.Cbor = namedtuple("Cbor", ("name", "key", "data_type"))

    def test_should_read_a_top_level_hash(self):
        item = self.Cbor("item", "$", "STRING")
        self.assertEqual(
            CborAccessor.class_read_item(item, self.hash_data), ({"test": "one"})
        )

    def test_should_read_a_top_level_array(self):
        item = self.Cbor("item", "$", "STRING")
        self.assertEqual(
            CborAccessor.class_read_item(item, self.array_data), ([4, 3, 2, 1])
        )

    def test_should_handle_various_keys(self):
        item = self.Cbor("item", "$.packet.item1", "STRING")
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), 1)

        item = self.Cbor("item", "$.packet.item2", "STRING")
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), 1.234)

        item = self.Cbor("item", "$.packet.item3", "STRING")
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), "a string")

        item = self.Cbor("item", "$.packet.item4", "STRING")
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), [1, 2, 3, 4])

        item = self.Cbor("item", "$.packet.item5", "STRING")
        self.assertEqual(
            CborAccessor.class_read_item(item, self.data1), ({"another": "object"})
        )

        item = self.Cbor("item", "$.packet.item5.another", "STRING")
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), "object")

        item = self.Cbor("item", "$.packet.item4[3]", "STRING")
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), 4)

        item = self.Cbor("item", "$[0].packet.item1", "STRING")
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 1)

        item = self.Cbor("item", "$[0].packet.item2", "STRING")
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 1.234)

        item = self.Cbor("item", "$[0].packet.item3", "STRING")
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), "a string")

        item = self.Cbor("item", "$[0].packet.item4", "STRING")
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), [1, 2, 3, 4])

        item = self.Cbor("item", "$[0].packet.item5", "STRING")
        self.assertEqual(
            CborAccessor.class_read_item(item, self.data2), ({"another": "object"})
        )

        item = self.Cbor("item", "$[0].packet.item5.another", "STRING")
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), "object")

        item = self.Cbor("item", "$[0].packet.item4[3]", "STRING")
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 4)

        item = self.Cbor("item", "$[1].packet.item1", "STRING")
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 2)

        item = self.Cbor("item", "$[1].packet.item2", "STRING")
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 2.234)

        item = self.Cbor("item", "$[1].packet.item3", "STRING")
        self.assertEqual(
            CborAccessor.class_read_item(item, self.data2), "another string"
        )

        item = self.Cbor("item", "$[1].packet.item4", "STRING")
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), [5, 6, 7, 8])

        item = self.Cbor("item", "$[1].packet.item5", "STRING")
        self.assertEqual(
            CborAccessor.class_read_item(item, self.data2), ({"another": "packet"})
        )

        item = self.Cbor("item", "$[1].packet.item5.another", "STRING")
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), "packet")

        item = self.Cbor("item", "$[1].packet.item4[3]", "STRING")
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 8)

    def test_should_read_a_collection_of_items(self):
        item1 = self.Cbor("ITEM1", "$.packet.item1", "STRING")
        item2 = self.Cbor("ITEM2", "$.packet.item2", "STRING")
        item3 = self.Cbor("ITEM3", "$.packet.item3", "STRING")
        item4 = self.Cbor("ITEM4", "$.packet.item4", "STRING")
        item5 = self.Cbor("ITEM5", "$.packet.item5", "STRING")
        item6 = self.Cbor("ITEM6", "$.packet.item5.another", "STRING")
        item7 = self.Cbor("ITEM7", "$.packet.item4[3]", "STRING")

        result = CborAccessor.class_read_items(
            [item1, item2, item3, item4, item5, item6, item7], self.data1
        )
        self.assertEqual(len(result), 7)
        self.assertEqual(result["ITEM1"], 1)
        self.assertEqual(result["ITEM2"], 1.234)
        self.assertEqual(result["ITEM3"], "a string")
        self.assertEqual(result["ITEM4"], [1, 2, 3, 4])
        self.assertEqual(result["ITEM5"], ({"another": "object"}))
        self.assertEqual(result["ITEM6"], "object")
        self.assertEqual(result["ITEM7"], 4)

        item1 = self.Cbor("ITEM1", "$[0].packet.item1", "STRING")
        item2 = self.Cbor("ITEM2", "$[0].packet.item2", "STRING")
        item3 = self.Cbor("ITEM3", "$[0].packet.item3", "STRING")
        item4 = self.Cbor("ITEM4", "$[0].packet.item4", "STRING")
        item5 = self.Cbor("ITEM5", "$[0].packet.item5", "STRING")
        item6 = self.Cbor("ITEM6", "$[0].packet.item5.another", "STRING")
        item7 = self.Cbor("ITEM7", "$[0].packet.item4[3]", "STRING")
        item8 = self.Cbor("ITEM8", "$[1].packet.item1", "STRING")
        item9 = self.Cbor("ITEM9", "$[1].packet.item2", "STRING")
        item10 = self.Cbor("ITEM10", "$[1].packet.item3", "STRING")
        item11 = self.Cbor("ITEM11", "$[1].packet.item4", "STRING")
        item12 = self.Cbor("ITEM12", "$[1].packet.item5", "STRING")
        item13 = self.Cbor("ITEM13", "$[1].packet.item5.another", "STRING")
        item14 = self.Cbor("ITEM14", "$[1].packet.item4[3]", "STRING")

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
        item = self.Cbor("item", "$.packet.item1", "STRING")
        CborAccessor.class_write_item(item, 3, self.data1)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), 3)

        item = self.Cbor("item", "$.packet.item2", "STRING")
        CborAccessor.class_write_item(item, 3.14, self.data1)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), 3.14)

        item = self.Cbor("item", "$.packet.item3", "STRING")
        CborAccessor.class_write_item(item, "something different", self.data1)
        self.assertEqual(
            CborAccessor.class_read_item(item, self.data1), "something different"
        )

        item = self.Cbor("item", "$.packet.item4", "STRING")
        CborAccessor.class_write_item(item, [7, 8, 9, 10], self.data1)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), [7, 8, 9, 10])

        item = self.Cbor("item", "$.packet.item5", "STRING")
        CborAccessor.class_write_item(item, {"good": "times"}, self.data1)
        self.assertEqual(
            CborAccessor.class_read_item(item, self.data1), ({"good": "times"})
        )

        item = self.Cbor("item", "$.packet.item5.good", "STRING")
        CborAccessor.class_write_item(item, "friends", self.data1)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), "friends")

        item = self.Cbor("item", "$.packet.item4[3]", "STRING")
        CborAccessor.class_write_item(item, 15, self.data1)
        self.assertEqual(CborAccessor.class_read_item(item, self.data1), 15)

        item = self.Cbor("item", "$[0].packet.item1", "STRING")
        CborAccessor.class_write_item(item, 5, self.data2)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 5)

        item = self.Cbor("item", "$[0].packet.item2", "STRING")
        CborAccessor.class_write_item(item, 5.05, self.data2)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 5.05)

        item = self.Cbor("item", "$[0].packet.item3", "STRING")
        CborAccessor.class_write_item(item, "something", self.data2)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), "something")

        item = self.Cbor("item", "$[0].packet.item4", "STRING")
        CborAccessor.class_write_item(item, "string", self.data2)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), "string")

        item = self.Cbor("item", "$[0].packet.item5", "STRING")
        CborAccessor.class_write_item(item, {"bill": "ted"}, self.data2)
        self.assertEqual(
            CborAccessor.class_read_item(item, self.data2), ({"bill": "ted"})
        )

        # TODO: This doesn't work because the above overwrites the item5
        # Ruby seems to add but Python replaces ...
        # item = self.Cbor("item", "$[0].packet.item5.another", "STRING")
        # CborAccessor.class_write_item(item, "money", self.data2)
        # self.assertEqual(CborAccessor.class_read_item(item, self.data2), "money")

        # TODO: This doesn't work because the above overwrites the item5
        # item = self.Cbor("item", "$[0].packet.item4[3]", "STRING")
        # CborAccessor.class_write_item(item, 25, self.data2)
        # self.assertEqual(CborAccessor.class_read_item(item, self.data2), 25)

        item = self.Cbor("item", "$[1].packet.item1", "STRING")
        CborAccessor.class_write_item(item, 7, self.data2)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 7)

        item = self.Cbor("item", "$[1].packet.item2", "STRING")
        CborAccessor.class_write_item(item, 3.13, self.data2)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), 3.13)

        item = self.Cbor("item", "$[1].packet.item3", "STRING")
        CborAccessor.class_write_item(item, "small", self.data2)
        self.assertEqual(CborAccessor.class_read_item(item, self.data2), "small")

        item = self.Cbor("item", "$[1].packet.item4", "STRING")
        CborAccessor.class_write_item(item, [101, 102, 103, 104], self.data2)
        self.assertEqual(
            CborAccessor.class_read_item(item, self.data2), [101, 102, 103, 104]
        )

        item = self.Cbor("item", "$[1].packet.item5", "STRING")
        CborAccessor.class_write_item(item, {"happy": "sad"}, self.data2)
        self.assertEqual(
            CborAccessor.class_read_item(item, self.data2), ({"happy": "sad"})
        )

        # item = self.Cbor("item", "$[1].packet.item5.another", "STRING")
        # CborAccessor.class_write_item(item, "art", self.data2)
        # self.assertEqual(CborAccessor.class_read_item(item, self.data2), "art")

        # item = self.Cbor("item", "$[1].packet.item4[3]", "STRING")
        # CborAccessor.class_write_item(item, 14, self.data2)
        # self.assertEqual(CborAccessor.class_read_item(item, self.data2), 14)

    def test_should_write_multiple_items(self):
        item1 = self.Cbor("item1", "$.packet.item1", "STRING")
        item2 = self.Cbor("item2", "$.packet.item2", "STRING")
        item3 = self.Cbor("item3", "$.packet.item3", "STRING")
        item4 = self.Cbor("item4", "$.packet.item4", "STRING")
        item5 = self.Cbor("item5", "$.packet.item5", "STRING")
        # item6 = self.Cbor("item6", "$.packet.item5.good", "STRING")
        # item7 = self.Cbor("item7", "$.packet.item4[3]", "STRING")

        items = [item1, item2, item3, item4, item5]  # , item6, item7]
        values = [
            3,
            3.14,
            "something different",
            [7, 8, 9, 10],
            {"good": "friends"},
            # "friends",
            # 15,
        ]
        CborAccessor.class_write_items(items, values, self.data1)
        self.assertEqual(CborAccessor.class_read_item(item1, self.data1), 3)
        self.assertEqual(CborAccessor.class_read_item(item2, self.data1), 3.14)
        self.assertEqual(
            CborAccessor.class_read_item(item3, self.data1), "something different"
        )
        self.assertEqual(CborAccessor.class_read_item(item4, self.data1), [7, 8, 9, 10])
        self.assertEqual(
            CborAccessor.class_read_item(item5, self.data1), ({"good": "friends"})
        )
        # self.assertEqual(CborAccessor.class_read_item(item6, self.data1), "friends")
        # self.assertEqual(CborAccessor.class_read_item(item7, self.data1), 15)

        item1 = self.Cbor("item1", "$[0].packet.item1", "STRING")
        item2 = self.Cbor("item2", "$[0].packet.item2", "STRING")
        item3 = self.Cbor("item3", "$[0].packet.item3", "STRING")
        item4 = self.Cbor("item4", "$[0].packet.item4", "STRING")
        item5 = self.Cbor("item5", "$[0].packet.item5", "STRING")
        # item6 = self.Cbor("item6", "$[0].packet.item5.good", "STRING")
        # item7 = self.Cbor("item7", "$[0].packet.item4[3]", "STRING")
        item8 = self.Cbor("item8", "$[1].packet.item1", "STRING")
        item9 = self.Cbor("item9", "$[1].packet.item2", "STRING")
        item10 = self.Cbor("item10", "$[1].packet.item3", "STRING")
        item11 = self.Cbor("item11", "$[1].packet.item4", "STRING")
        item12 = self.Cbor("item12", "$[1].packet.item5", "STRING")
        # item13 = self.Cbor("item13", "$[1].packet.item5.another", "STRING")
        # item14 = self.Cbor("item14", "$[1].packet.item4[3]", "STRING")

        items = [
            item1,
            item2,
            item3,
            item4,
            item5,
            item8,
            item9,
            item10,
            item11,
            item12,
        ]
        values = [
            5,
            5.05,
            "something",
            "string",
            {"bill": "ted"},
            # "money",
            # 25,
            7,
            3.13,
            "small",
            [101, 102, 103, 104],
            {"happy": "sad"},
            # "art",
            # 14,
        ]
        CborAccessor.class_write_items(items, values, self.data2)
        self.assertEqual(CborAccessor.class_read_item(item1, self.data2), 5)
        self.assertEqual(CborAccessor.class_read_item(item2, self.data2), 5.05)
        self.assertEqual(CborAccessor.class_read_item(item3, self.data2), "something")
        self.assertEqual(CborAccessor.class_read_item(item4, self.data2), "string")
        self.assertEqual(
            CborAccessor.class_read_item(item5, self.data2),
            ({"bill": "ted"}),
        )
        # self.assertEqual(CborAccessor.class_read_item(item6, self.data2), "money")
        # self.assertEqual(CborAccessor.class_read_item(item7, self.data2), 25)
        self.assertEqual(CborAccessor.class_read_item(item8, self.data2), 7)
        self.assertEqual(CborAccessor.class_read_item(item9, self.data2), 3.13)
        self.assertEqual(CborAccessor.class_read_item(item10, self.data2), "small")
        self.assertEqual(
            CborAccessor.class_read_item(item11, self.data2), [101, 102, 103, 104]
        )
        self.assertEqual(
            CborAccessor.class_read_item(item12, self.data2),
            ({"happy": "sad"}),
        )
        # self.assertEqual(CborAccessor.class_read_item(item13, self.data2), "art")
        # self.assertEqual(CborAccessor.class_read_item(item14, self.data2), 14)
