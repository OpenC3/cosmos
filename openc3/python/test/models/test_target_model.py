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


import time
from typing import Optional
import unittest

from test.test_helper import *

from openc3.models.model import Model

from unittest.mock import *
from openc3.models.target_model import TargetModel
from openc3.conversions.generic_conversion import GenericConversion

from pprint import pprint

class TestTargetModel(unittest.TestCase):
    def setUp(self):
      mock_redis(self)
      #model = ScopeModel.new(name: "DEFAULT")
      #model.create

    def test_returns_all_model_names(self):
        model = TargetModel(folder_name= "TEST", name= "TEST", scope= "DEFAULT")
        pprint(dir(model))
        model.create
        model = TargetModel(folder_name= "SPEC", name= "SPEC", scope= "DEFAULT")
        model.create
        model = TargetModel(folder_name= "OTHER", name= "OTHER", scope= "OTHER")
        model.create
        names = TargetModel.names(scope= "DEFAULT")
        pprint(names)
        # contain_exactly doesn't care about ordering and neither do we
        #expect(names).to contain_exactly("TEST", "SPEC")
        #names = TargetModel.names(scope= "OTHER")
        #expect(names).to contain_exactly("OTHER")

