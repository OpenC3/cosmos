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

import time
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.microservices.microservice import Microservice


class TestMicroservice(unittest.TestCase):
    def setUp(self):
        self.redis = mock_redis(self)

    def test_expects_scope__type__name_parameter_as_env(self):
        with self.assertRaisesRegex(RuntimeError, "Microservice must be named"):
            Microservice.run()
        os.environ["OPENC3_MICROSERVICE_NAME"] = "DEFAULT"
        with self.assertRaisesRegex(
            RuntimeError, "Name DEFAULT doesn't match convention"
        ):
            Microservice.run()
        os.environ["OPENC3_MICROSERVICE_NAME"] = "DEFAULT_TYPE_NAME"
        with self.assertRaisesRegex(
            RuntimeError, "Name DEFAULT_TYPE_NAME doesn't match convention"
        ):
            Microservice.run()
        os.environ["OPENC3_MICROSERVICE_NAME"] = "DEFAULT__TYPE__NAME"
        Microservice.run()
        time.sleep(0.1)
