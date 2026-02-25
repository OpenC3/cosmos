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

from openc3.streams.stream import Stream
from test.test_helper import *


class TestStream(unittest.TestCase):
    def test_raises_an_error(self):
        with self.assertRaisesRegex(
            RuntimeError,
            "not defined by Stream",
        ):
            Stream().read()
        with self.assertRaisesRegex(
            RuntimeError,
            "not defined by Stream",
        ):
            Stream().write(None)
        with self.assertRaisesRegex(
            RuntimeError,
            "not defined by Stream",
        ):
            Stream().connect()
        with self.assertRaisesRegex(
            RuntimeError,
            "not defined by Stream",
        ):
            Stream().disconnect()
