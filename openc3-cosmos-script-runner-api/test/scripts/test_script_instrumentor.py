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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import ast
import pytest
from scripts.script_instrumentor import ScriptInstrumentor


class MockRunningScript:
    instance = None

    def __init__(self):
        MockRunningScript.instance = self
        self.pre_lines = []
        self.post_lines = []
        self.exceptions = []

    def pre_line_instrumentation(self, filename, lineno, globals, locals):
        self.pre_lines.append((filename, lineno))

    def post_line_instrumentation(self, filename, lineno):
        self.post_lines.append((filename, lineno))

    def exception_instrumentation(self, filename, lineno):
        self.exceptions.append((filename, lineno))
        return False


@pytest.fixture
def mock_running_script():
    return MockRunningScript()


def test_simple_script(mock_running_script):
    script = """
x = 1
y = 2
z = x + y
"""
    parsed = ast.parse(script)
    tree = ScriptInstrumentor("testfile.py").visit(parsed)
    compiled = compile(tree, filename="testfile.py", mode="exec")
    exec(compiled, {"RunningScript": mock_running_script})

    assert mock_running_script.pre_lines == [
        ("testfile.py", 2),
        ("testfile.py", 3),
        ("testfile.py", 4),
    ]
    assert mock_running_script.post_lines == [
        ("testfile.py", 2),
        ("testfile.py", 3),
        ("testfile.py", 4),
    ]
    assert mock_running_script.exceptions == []


def test_try_except_script(mock_running_script):
    script = """
try:
  print('start')
  x = 1 / 0
except ZeroDivisionError:
  x = 0
print('done')
"""
    parsed = ast.parse(script)
    tree = ScriptInstrumentor("testfile.py").visit(parsed)
    compiled = compile(tree, filename="testfile.py", mode="exec")
    exec(compiled, {"RunningScript": mock_running_script})

    assert mock_running_script.pre_lines == [
        ("testfile.py", 2),
        ("testfile.py", 3),
        ("testfile.py", 4),
        ("testfile.py", 6),
        ("testfile.py", 7),
    ]
    assert mock_running_script.post_lines == [
        # Line 2 doesn't exit because it is a try
        ("testfile.py", 3),
        ("testfile.py", 4),
        ("testfile.py", 6),
        ("testfile.py", 7),
    ]
    assert mock_running_script.exceptions == []


def test_if_else_script(mock_running_script):
    script = """
x = 1
if x == 1:
  y = 2
else:
  y = 3
z = x + y
"""
    parsed = ast.parse(script)
    tree = ScriptInstrumentor("testfile.py").visit(parsed)
    compiled = compile(tree, filename="testfile.py", mode="exec")
    exec(compiled, {"RunningScript": mock_running_script})

    assert mock_running_script.pre_lines == [
        ("testfile.py", 2),
        ("testfile.py", 3),
        ("testfile.py", 4),
        ("testfile.py", 7),
    ]
    assert mock_running_script.post_lines == [
        ("testfile.py", 2),
        ("testfile.py", 4),
        ("testfile.py", 7),
    ]
    assert mock_running_script.exceptions == []


def test_for_loop_script(mock_running_script):
    script = """
for i in range(3):
  print(i)
print('done')
"""
    parsed = ast.parse(script)
    tree = ScriptInstrumentor("testfile.py").visit(parsed)
    compiled = compile(tree, filename="testfile.py", mode="exec")
    exec(compiled, {"RunningScript": mock_running_script})

    assert mock_running_script.pre_lines == [
        ("testfile.py", 2),
        ("testfile.py", 3),
        ("testfile.py", 3),
        ("testfile.py", 3),
        ("testfile.py", 4),
    ]
    assert mock_running_script.post_lines == [
        ("testfile.py", 3),
        ("testfile.py", 3),
        ("testfile.py", 3),
        ("testfile.py", 4),
    ]
    assert mock_running_script.exceptions == []


def test_match_script(mock_running_script):
    script = """
x = "HI"
match x:
  case "HI":
    print(x)
  case "NO":
    print(x)
print('done')
"""
    parsed = ast.parse(script)
    tree = ScriptInstrumentor("testfile.py").visit(parsed)
    compiled = compile(tree, filename="testfile.py", mode="exec")
    exec(compiled, {"RunningScript": mock_running_script})

    assert mock_running_script.pre_lines == [
        ("testfile.py", 2),  # x = "HI"
        ("testfile.py", 3),  # match x:
        # We can't match the case statement because it must come after the match statement
        ("testfile.py", 5),  # print(x)
        ("testfile.py", 8),
    ]
    assert mock_running_script.post_lines == [
        ("testfile.py", 2),
        ("testfile.py", 5),
        ("testfile.py", 8),
    ]
    assert mock_running_script.exceptions == []


def test_exception_script(mock_running_script):
    script = """
x = "HI"
raise RuntimeError("Error")
print('done')
"""
    parsed = ast.parse(script)
    tree = ScriptInstrumentor("testfile.py").visit(parsed)
    compiled = compile(tree, filename="testfile.py", mode="exec")
    exec(compiled, {"RunningScript": mock_running_script})

    assert mock_running_script.pre_lines == [
        ("testfile.py", 2),
        ("testfile.py", 3),
        ("testfile.py", 4),
    ]
    assert mock_running_script.post_lines == [
        ("testfile.py", 2),
        ("testfile.py", 3),
        ("testfile.py", 4),
    ]
    assert mock_running_script.exceptions == [
        ("testfile.py", 3),
    ]


def test_raise_with_try(mock_running_script):
    script = """
i = 0
raise RuntimeError("Error1") # Handled by us
try: # Initial try
  i = 1
  try: # Nested try
    i = 2
  except RuntimeError:
    i = 3
  raise RuntimeError("BAD") # Handled by them
except RuntimeError:
  i = 5 # This handler should execute
raise RuntimeError("Error2") # Handled by us
"""
    parsed = ast.parse(script)
    tree = ScriptInstrumentor("testfile.py").visit(parsed)
    compiled = compile(tree, filename="testfile.py", mode="exec")
    vars = {'i': None}
    exec(compiled, {"RunningScript": mock_running_script}, vars)
    assert(vars["i"] == 5)

    assert mock_running_script.pre_lines == [
        ("testfile.py", 2),
        ("testfile.py", 3),
        ("testfile.py", 4),
        ("testfile.py", 5),
        ("testfile.py", 6),
        ("testfile.py", 7),
        ("testfile.py", 10),
        ("testfile.py", 12),
        ("testfile.py", 13),
    ]
    assert mock_running_script.post_lines == [
        ("testfile.py", 2),
        ("testfile.py", 3),
        ("testfile.py", 5),
        ("testfile.py", 7),
        ("testfile.py", 10),
        ("testfile.py", 12),
        ("testfile.py", 13),
    ]
    assert mock_running_script.exceptions == [
        ("testfile.py", 3),
        # Note the exception on line 10 is handled by them
        ("testfile.py", 13),
    ]


def test_import_future_script(mock_running_script):
    script = "from __future__ import annotations\nprint('hi')"
    parsed = ast.parse(script)
    tree = ScriptInstrumentor("testfile.py").visit(parsed)
    compiled = compile(tree, filename="testfile.py", mode="exec")
    exec(compiled, {"RunningScript": mock_running_script})

    assert mock_running_script.pre_lines == [
        ("testfile.py", 2),
    ]
    assert mock_running_script.post_lines == [
        ("testfile.py", 2),
    ]
    assert mock_running_script.exceptions == []
