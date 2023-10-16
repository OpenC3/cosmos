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
from openc3.api.target_api import *
from openc3.models.target_model import TargetModel
from openc3.models.interface_model import InterfaceModel


class TestTargetApi(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()

        model = InterfaceModel(
            name="INST_INT",
            scope="DEFAULT",
            target_names=["INST"],
            config_params=["openc3/interfaces/interface.py"],
        )
        model.create()
        model = TargetModel(folder_name="INST", name="INST", scope="DEFAULT")
        model.create()
        model = TargetModel(folder_name="EMPTY", name="EMPTY", scope="DEFAULT")
        model.create()
        model = TargetModel(folder_name="SYSTEM", name="SYSTEM", scope="DEFAULT")
        model.create()

    def test_gets_an_empty_array_for_an_unknown_scope(self):
        self.assertEqual(len(get_target_names(scope="UNKNOWN")), 0)

    def test_gets_the_list_of_targets(self):
        self.assertEqual(get_target_names(scope="DEFAULT"), ["EMPTY", "INST", "SYSTEM"])

    def test_returns_none_if_the_target_doesnt_exist(self):
        self.assertIsNone(get_target("BLAH", scope="DEFAULT"))

    def test_gets_a_target_hash(self):
        tgt = get_target("INST", scope="DEFAULT")
        self.assertEqual(type(tgt), dict)
        self.assertEqual(tgt["name"], "INST")

    def test_gets_target_name_interface_names(self):
        info = get_target_interfaces(scope="DEFAULT")
        self.assertEqual(info[0][0], "EMPTY")
        self.assertEqual(info[0][1], "")
        self.assertEqual(info[1][0], "INST")
        self.assertEqual(info[1][1], "INST_INT")
        self.assertEqual(info[2][0], "SYSTEM")
        self.assertEqual(info[2][1], "")
