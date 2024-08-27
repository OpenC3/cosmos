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
from unittest.mock import patch, MagicMock
from openc3.models.target_model import TargetModel
from openc3.conversions.generic_conversion import GenericConversion

class TestTargetModel(unittest.TestCase):
    def setUp(self):
      mock_redis(self)
      #model = ScopeModel.new(name: "DEFAULT")
      #model.create

    @patch('openc3.models.model.Model.names')
    def test_names_with_default_scope(self, mock_super_names):
        # Arrange
        expected_names = ['TARGET1', 'TARGET2', 'TARGET3']
        mock_super_names.return_value = expected_names
        default_scope = 'DEFAULT'
        # Act
        result = TargetModel.names(default_scope)
        # Assert
        self.assertEqual(result, expected_names)
        mock_super_names.assert_called_once_with(f'{default_scope}__openc3_targets')

    @patch('openc3.models.model.Model.names')
    def test_names_with_custom_scope(self, mock_super_names):
        # Arrange
        expected_names = ['CUSTOM_TARGET1', 'CUSTOM_TARGET2']
        mock_super_names.return_value = expected_names
        custom_scope = 'CUSTOM_SCOPE'
        # Act
        result = TargetModel.names(custom_scope)
        # Assert
        self.assertEqual(result, expected_names)
        mock_super_names.assert_called_once_with(f'{custom_scope}__openc3_targets')

    @patch('openc3.models.model.Model.names')
    def test_names_with_empty_result(self, mock_super_names):
        # Arrange
        mock_super_names.return_value = []
        scope = 'EMPTY_SCOPE'
        # Act
        result = TargetModel.names(scope)
        # Assert
        self.assertEqual(result, [])
        mock_super_names.assert_called_once_with(f'{scope}__openc3_targets')

    @patch('openc3.models.model.Model.names')
    def test_names_with_none_scope(self, mock_super_names):
        # Arrange
        expected_names = ['TARGET_X', 'TARGET_Y']
        mock_super_names.return_value = expected_names
        # Act & Assert
        with self.assertRaises(TypeError):
            TargetModel.names(None)
        mock_super_names.assert_not_called()
