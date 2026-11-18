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
from importlib.resources import files
from typing import get_args

from openc3.api.api_types import OverrideValueType, ValueType
from openc3.models.cvt_model import CvtModel


class TestApiTypes(unittest.TestCase):
    def test_value_type_matches_cvt_value_types(self):
        # WITH_UNITS is deprecated but still accepted as an alias for FORMATTED
        self.assertEqual(set(get_args(ValueType)), CvtModel.VALUE_TYPES | {"WITH_UNITS"})

    def test_override_value_type_adds_all(self):
        self.assertEqual(set(get_args(OverrideValueType)), set(get_args(ValueType)) | {"ALL"})

    def test_package_is_marked_typed(self):
        # PEP 561: type checkers only read inline hints from packages with py.typed
        self.assertTrue(files("openc3").joinpath("py.typed").is_file())
