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

from openc3.packets.command_validator import CommandValidator, CommandValidatorResult


class TestCommandValidator(unittest.TestCase):
    def test_pre_check_returns_success_result(self):
        result = CommandValidator().pre_check(None)
        self.assertIsInstance(result, CommandValidatorResult)
        self.assertIsInstance(result, tuple)
        self.assertEqual(result, (True, None))
        self.assertTrue(result.result)
        self.assertIsNone(result.message)

    def test_post_check_returns_success_result(self):
        result = CommandValidator().post_check(None)
        self.assertIsInstance(result, CommandValidatorResult)
        self.assertEqual(result, (True, None))
        self.assertTrue(result.result)
        self.assertIsNone(result.message)

    def test_result_unpacks_like_a_tuple(self):
        result, message = CommandValidatorResult(False, "not ready")
        self.assertFalse(result)
        self.assertEqual(message, "not ready")
