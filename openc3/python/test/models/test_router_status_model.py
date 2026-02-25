# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
from unittest.mock import *

from openc3.interfaces.interface import Interface
from openc3.models.interface_status_model import InterfaceStatusModel
from openc3.models.router_status_model import RouterStatusModel
from test.test_helper import *


class MyRouter(Interface):
    pass


class OtherRouter(Interface):
    pass


class TestRouterStatusModel(unittest.TestCase):
    def setUp(self):
        self.redis = mock_redis(self)

    def test_set_and_get(self):
        my = MyRouter()
        RouterStatusModel.set(my.as_json(), "DEFAULT")
        status = RouterStatusModel.get("MyRouter", "DEFAULT")
        self.assertEqual(my.name, status["name"])

    def test_names_and_all(self):
        my = MyRouter()
        RouterStatusModel.set(my.as_json(), "DEFAULT")
        other = OtherRouter()
        RouterStatusModel.set(other.as_json(), "DEFAULT")

        names = RouterStatusModel.names("DEFAULT")
        self.assertEqual(names, ["MyRouter", "OtherRouter"])
        all = RouterStatusModel.all("DEFAULT")
        self.assertEqual(list(all.keys()), ["MyRouter", "OtherRouter"])
        self.assertEqual(all["OtherRouter"]["name"], "OtherRouter")

        all = RouterStatusModel.names("OTHER")
        self.assertEqual(all, [])  # Nothing in 'OTHER' scope
        all = RouterStatusModel.all("OTHER")
        self.assertEqual(all, {})  # Nothing in 'OTHER' scope

    def test_with_similar_interface(self):
        # Ensure we can create an interface and router with the same name
        # and they get stored separately
        my = MyRouter()
        my.state = "DISCONNECTED"
        RouterStatusModel.set(my.as_json(), "DEFAULT")
        my.state = "CONNECTED"
        InterfaceStatusModel.set(my.as_json(), "DEFAULT")

        all_routers = RouterStatusModel.all("DEFAULT")
        self.assertEqual(list(all_routers.keys()), ["MyRouter"])
        self.assertEqual(all_routers["MyRouter"]["state"], "DISCONNECTED")
        all_interfaces = InterfaceStatusModel.all("DEFAULT")
        self.assertEqual(list(all_interfaces.keys()), ["MyRouter"])
        self.assertEqual(all_interfaces["MyRouter"]["state"], "CONNECTED")
