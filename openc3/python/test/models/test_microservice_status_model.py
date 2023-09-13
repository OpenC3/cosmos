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
from openc3.models.microservice_status_model import MicroserviceStatusModel
from openc3.microservices.microservice import Microservice


class TestMicroserviceStatusModel(unittest.TestCase):
    def setUp(self):
        self.redis = mock_redis(self)

    def test_stores_microservice_status(self):
        microservice = Microservice("DEFAULT__TYPE__TEST")
        MicroserviceStatusModel.set(microservice.as_json(), scope="DEFAULT")
        microservice = Microservice("DEFAULT__TYPE__TEST2")
        MicroserviceStatusModel.set(microservice.as_json(), scope="DEFAULT")
        self.assertListEqual(
            ["DEFAULT__TYPE__TEST", "DEFAULT__TYPE__TEST2"],
            MicroserviceStatusModel.names(scope="DEFAULT"),
        )
        micro = MicroserviceStatusModel.get("DEFAULT__TYPE__TEST", scope="DEFAULT")
        print(f"mciro:{micro} type:{type(micro)}")
        self.assertEqual(micro["name"], "DEFAULT__TYPE__TEST")
        self.assertEqual(micro["state"], "INITIALIZED")
        self.assertEqual(micro["count"], 0)
        self.assertEqual(micro["plugin"], None)
