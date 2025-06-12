# Copyright 2025 OpenC3, Inc.
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
from openc3.script_engines.script_engine import ScriptEngine

class TestScriptEngine(unittest.TestCase):
    def setUp(self):
        self.mock_running_script = MagicMock()
        self.engine = ScriptEngine(self.mock_running_script)

    def test_tokenizer_basic(self):
        result = self.engine.tokenizer("WRITE 'Hello World'")
        assert result == ['WRITE', "'Hello World'"]

    def test_tokenizer_special_chars(self):
        result = self.engine.tokenizer("LET $VAR = 42")
        assert result == ["LET", "$VAR", "=", "42"]

    def test_tokenizer_preserves_quotes(self):
        result = self.engine.tokenizer('WRITE "Hello World"')
        assert result == ['WRITE', '"Hello World"']

    def test_tokenizer_preserves_single_quotes(self):
        result = self.engine.tokenizer("WRITE 'Single quotes'")
        assert result == ['WRITE', "'Single quotes'"]

    def test_tokenizer_multiple_quoted_strings(self):
        result = self.engine.tokenizer('WRITE "Hello" , "World"')
        assert result == ['WRITE', '"Hello"', ',', '"World"']

    def test_tokenizer_timestamps(self):
        result = self.engine.tokenizer('WRITE 11:30:00')
        assert result == ['WRITE', '11:30:00']
        result = self.engine.tokenizer('WRITE 2025/123-11:30:00.57')
        assert result == ['WRITE', '2025', '/', '123', '-', '11:30:00.57']
        result = self.engine.tokenizer('WRITE /123-11:30:00.57')
        assert result == ['WRITE', '/', '123', '-', '11:30:00.57']
        result = self.engine.tokenizer('WRITE 2025/-11:30:00.57')
        assert result == ['WRITE', '2025', '/', '-', '11:30:00.57']
        result = self.engine.tokenizer('WRITE /-11:30:00.57')
        assert result == ['WRITE', '/', '-', '11:30:00.57']