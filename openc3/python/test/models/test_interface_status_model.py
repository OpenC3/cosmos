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
from openc3.interfaces.interface import Interface
from openc3.models.interface_status_model import InterfaceStatusModel


class MyInterface(Interface):
    pass


class OtherInterface(Interface):
    pass


class TestInterfaceStatusModel(unittest.TestCase):
    def setUp(self):
        self.redis = mock_redis(self)

    def test_set_and_get(self):
        my = MyInterface()
        InterfaceStatusModel.set(my.as_json(), "DEFAULT")
        status = InterfaceStatusModel.get("MyInterface", "DEFAULT")
        self.assertEqual(my.name, status["name"])

    def test_names_and_all(self):
        my = MyInterface()
        InterfaceStatusModel.set(my.as_json(), "DEFAULT")
        other = OtherInterface()
        InterfaceStatusModel.set(other.as_json(), "DEFAULT")

        names = InterfaceStatusModel.names("DEFAULT")
        self.assertEqual(names, ["MyInterface", "OtherInterface"])
        all = InterfaceStatusModel.all("DEFAULT")
        self.assertEqual(list(all.keys()), ["MyInterface", "OtherInterface"])
        self.assertEqual(all["OtherInterface"]["name"], "OtherInterface")

        all = InterfaceStatusModel.names("OTHER")
        self.assertEqual(all, [])  # Nothing in 'OTHER' scope
        all = InterfaceStatusModel.all("OTHER")
        self.assertEqual(all, {})  # Nothing in 'OTHER' scope
