import re
import os
import sys

base = os.path.basename(sys.argv[1])
spec = False
if "spec" in base:
    spec = True
    file_class = "Test" + "".join([x.capitalize() for x in base.split("_")[0:-1]])
    py_file_name = f"test_{'_'.join(base.split('_')[0:-1])}.py"
else:
    py_file_name = f"{os.path.splitext(base)[0]}.py"

print(f"processing:{sys.argv[1]} into {py_file_name}")
out = open(py_file_name, "w+")
with open(sys.argv[1]) as file:
    for line in file:
        if line.strip() == "end":
            continue
        if spec and "module" in line:
            out.write(f"class {file_class}(unittest.TestCase):\n")
            continue
        m = re.compile(r".*describe \"(.*)\" do.*").match(line)
        if m:
            class_name = "".join([x.capitalize() for x in m.group(1).split("_")])
            line = f"class {class_name}(unittest.TestCase):\n"
        m = re.compile(r".*it \"(.*)\" do.*").match(line)
        if m:
            test_name = m.group(1).replace(" ", "_").replace("'", "").lower()
            # No trailing : because that's added later
            line = f"    def test_{test_name}(self)\n"

        line = (
            line.replace(", :allow_nan => true", "")
            .replace(":allow_nan => true", "")
            .replace(", :create_additions => true", "")
            .replace(", token: $openc3_token", "")
            .replace(", token: token", "")
            .replace("scope: $openc3_scope", "scope=OPENC3_SCOPE")
        )

        # Convert symbols to strings
        line = re.sub(r":([A-Z_]+)", r"'\1'", line)
        line = re.sub(r"([a-z._]+)\.length", r"len(\1)", line)
        line = re.sub(r"([a-z._]+)\.abs", r"abs(\1)", line)

        line = re.sub(r"([a-z_]):", r"\1=", line)
        line = re.sub(r"(\s*if .*)", r"\1:", line)
        m = re.compile(r"(\s*)def self\.(.*)\((.*)\)").match(line)
        if m:
            name = m.group(2).replace("self.", "")
            out.write(f"{m.group(1)}@classmethod\n")
            line = f"{m.group(1)}def {name}(cls, {m.group(3)}):\n"
        else:
            line = re.sub(r"(\s*def .*)", r"\1:", line)

        line = line.replace("initialize", "__init__")

        # Convert spec methods into unittest
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
        if "expect" in line and ".to be_falsey" in line:
            line = line.replace("expect(", "self.assertFalse(")
            line = line.replace(").to be_falsey", ")")
        if "expect" in line and ".to be true" in line:
            line = line.replace("expect(", "self.assertTrue(")
            line = line.replace(").to be true", ")")
        if "expect" in line and ".to be_truthy" in line:
            line = line.replace("expect(", "self.assertTrue(")
            line = line.replace(").to be_truthy", ")")
        if "expect {" in line:
            line = line.replace("expect ", "")
            m = re.compile(r"(\s*)\{(.*)\}\.to raise_error\(.* \"(.*)\"\)").match(line)
            if m:
                name = m.group(2).replace("self.", "")
                string = m.group(3).replace("#{", "{").replace("@", "self.")
                out.write(
                    f'{m.group(1)}with self.assertRaisesRegex(AttributeError, f"{string}"):\n'
                )
                line = f"{m.group(1)}    {m.group(2)}\n"
        if "expect(" in line and ".to match(" in line:
            m = re.compile(r"(\s*)expect\((.*)\)\.to match\(/(.*)/\)").match(line)
            if m:
                line = f"{m.group(1)}self.assertIn('{m.group(3)}', {m.group(2)})\n"

        if line.strip() == "case":
            line.replace("case", "match")
            line += ":"

        line = (
            line.replace(".new(", "(")
            .replace(".new", "()")
            .replace("ArgumentError, (", "AttributeError(f")
            .replace(".class", ".__class__.__name__")
            .replace("JSON.parse", "json.loads")
            .replace("JSON.generate", "json.dumps")
            .replace("else", "else:")
            .replace("elsif", "elif:")
            .replace("true", "True")
            .replace("false", "False")
            .replace("nil", "None")
            .replace("@", "self.")
            .replace(".upcase", ".upper()")
            .replace(".downcase", ".lower()")
            .replace("#{", "{")
            .replace("=>", ":")
            .replace("begin", "try:")
            .replace("rescue", "except:")
            .replace("when", "case")
            .replace(" && ", " and ")
            .replace(" || ", " or ")
        )
        out.write(line)

out.close()
