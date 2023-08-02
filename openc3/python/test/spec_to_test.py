import re
import os
import sys

print(sys.argv)
base = os.path.basename(sys.argv[1])
file_class = "Test" + "".join([x.capitalize() for x in base.split("_")[0:-1]])
py_file_name = f"test_{'_'.join(base.split('_')[0:-1])}.py"
print(f"processing:{sys.argv[1]} into {py_file_name}")
out = open(py_file_name, "w+")
with open(sys.argv[1]) as file:
    for line in file:
        if line.strip() == "end":
            continue
        if "module" in line:
            out.write(f"class {file_class}(unittest.TestCase):\n")
            continue
        m = re.compile(r".*describe \"(.*)\" do.*").match(line)
        if m:
            class_name = "".join([x.capitalize() for x in m.group(1).split("_")])
            line = f"class {class_name}(unittest.TestCase):\n"
        m = re.compile(r".*it \"(.*)\" do.*").match(line)
        if m:
            test_name = m.group(1).replace(" ", "_").replace("'", "").lower()
            line = f"    def test_{test_name}(self):\n"
        # Convert symbols to strings
        line = re.sub(r":([A-Z_]+)", r"'\1'", line)
        line = re.sub(r"([a-z._]+)\.length", r"len(\1)", line)
        line = re.sub(r"([a-z._]+)\.abs", r"abs(\1)", line)

        if "before(:each)" in line:
            line = "    def setUp(self):\n"
        if "expect" in line and ".to eql" in line:
            line = line.replace("expect(", "self.assertEqual(")
            line = re.sub(r"\)\.to eql (.*)", r", \1)", line)
        if "expect" in line and ".to be_nil" in line:
            line = line.replace("expect(", "self.assertIsNone(")
            line = line.replace(").to be_nil", ")")
        if "expect" in line and ".not_to be_nil" in line:
            line = line.replace("expect(", "self.assertIsNotNone(")
            line = line.replace(").not_to be_nil", ")")
        if "expect" in line and ".to be false" in line:
            line = line.replace("expect(", "self.assertFalse(")
            line = line.replace(").to be false", ")")
        if "expect" in line and ".to be true" in line:
            line = line.replace("expect(", "self.assertTrue(")
            line = line.replace(").to be true", ")")
        if "expect {" in line:
            line = line.replace("expect ", "")
            line = re.sub(
                r"\{(.*)\}\.to raise_error\(.* \"(.*)\"\)",
                r'self.assertRaisesRegex(AttributeError, f"\2", \1)',
                line,
            )

        line = (
            line.replace(".new", "()")
            .replace("true", "True")
            .replace("false", "False")
            .replace("nil", "None")
            .replace("@", "self.")
            .replace(".upcase", ".upper()")
            .replace(".downcase", ".lower()")
        )
        out.write(line)

out.close()
