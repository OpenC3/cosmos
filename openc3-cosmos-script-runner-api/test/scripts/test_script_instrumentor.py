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
    ("testfile.py", 5),
    ("testfile.py", 6),
  ]
  assert mock_running_script.post_lines == [
    # Line 2 doesn't exit because it raises an exception
    ("testfile.py", 3),
    ("testfile.py", 5),
    ("testfile.py", 6),
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
  print(ast.dump(tree, indent=4))
  compiled = compile(tree, filename="testfile.py", mode="exec")
  exec(compiled, {"RunningScript": mock_running_script})

  assert mock_running_script.pre_lines == [
    ("testfile.py", 2), # x = "HI"
    ("testfile.py", 3), # match x:
    # We can't match the case statement because it must come after the match statement
    ("testfile.py", 5), # print(x)
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
  print(ast.dump(tree, indent=4))
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
