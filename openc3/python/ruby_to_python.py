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
        # Ignore comments
        if len(line.strip()) > 0 and line.strip()[0] == "#":
            out.write(line)
            continue
        # Convert class name
        m = re.compile(r"\s*class (.*)").match(line)
        if m:
            classes = m.group(1).split(" < ")
            if len(classes) > 1:
                out.write(f"class {classes[0]}({classes[1]}):\n")
            else:
                out.write(f"class {classes[0]}:\n")
            continue

        m = re.compile(r".*describe \"(.*)\" do.*").match(line)
        if m:
            class_name = "".join([x.capitalize() for x in m.group(1).split("_")])
            line = f"class {class_name}(unittest.TestCase):\n"
        m = re.compile(r".*it \"(.*)\" do.*").match(line)
        if m:
            test_name = (
                m.group(1)
                .replace(" ", "_")
                .replace("'", "")
                .replace("-", "_")
                .replace(",", "")
                .lower()
            )
            # No trailing : because that's added later
            line = f"    def test_{test_name}(self)\n"

        # Remove allow_nan, create_additions, and token keyword args
        # Fix scope keyword arg
        line = (
            line.replace(", :allow_nan => true", "")
            .replace(":allow_nan => true", "")
            .replace(", :create_additions => true", "")
            .replace(", token: $openc3_token", "")
            .replace(", token: token", "")
            .replace("scope: $openc3_scope", "scope=OPENC3_SCOPE")
        )

        # Ruby:   :var
        # Python: 'var'
        line = re.sub(r":([A-Z_]+)", r"'\1'", line)
        # Ruby:   var.length
        # Python: len(var)
        line = re.sub(r"([@a-z._]+)\.length", r"len(\1)", line)
        # Ruby:   var.abs
        # Python: abs(var)
        line = re.sub(r"([@a-z._]+)\.abs", r"abs(\1)", line)
        # Ruby:   param: value
        # Python: param = value
        line = re.sub(r"([a-z_]):", r"\1=", line)
        # Add a ':' to the end of if lines
        line = re.sub(r"(\s*if .*)", r"\1:", line)
        m = re.compile(r"(\s*)def self\.(.*)\((.*)\)").match(line)
        if m:
            name = m.group(2).replace("self.", "")
            out.write(f"{m.group(1)}@classmethod\n")
            line = f"{m.group(1)}def {name}(cls, {m.group(3)}):\n"
        else:
            line = re.sub(r"(\s*def .*)", r"\1:", line)

        line = re.sub(r"\s*?(\w*?)\.to_s", r" str(\1)", line)
        line = re.sub(r"\s*?(\w*?)\.to_f", r" float(\1)", line)
        line = re.sub(r"\s*?(\w*?)\.to_i", r" int(\1)", line)

        line = line.replace("initialize(", "__init__(self, ")

        # Convert spec methods into unittest
        if "before(:each)" in line:
            line = "    def setUp(self):\n"
        if "expect" in line and ".to eql" in line:
            line = line.replace("expect(", "self.assertEqual(")
            line = re.sub(r"\)\.to eql(.*)", r", \1)", line)
        elif "expect" in line and ".to eq" in line:
            line = line.replace("expect(", "self.assertEqual(")
            line = re.sub(r"\)\.to eq(.*)", r", \1)", line)
        elif "expect" in line and ".to be_nil" in line:
            line = line.replace("expect(", "self.assertIsNone(")
            line = line.replace(").to be_nil", ")")
        elif "expect" in line and ".not_to be_nil" in line:
            line = line.replace("expect(", "self.assertIsNotNone(")
            line = line.replace(").not_to be_nil", ")")
        elif "expect" in line and ".to be false" in line:
            line = line.replace("expect(", "self.assertFalse(")
            line = line.replace(").to be false", ")")
        elif "expect" in line and ".to be_falsey" in line:
            line = line.replace("expect(", "self.assertFalse(")
            line = line.replace(").to be_falsey", ")")
        elif "expect" in line and ".to be true" in line:
            line = line.replace("expect(", "self.assertTrue(")
            line = line.replace(").to be true", ")")
        elif "expect" in line and ".to be_truthy" in line:
            line = line.replace("expect(", "self.assertTrue(")
            line = line.replace(").to be_truthy", ")")
        elif "expect" in line and ".to be" in line:
            line = line.replace("expect(", "self.assertEqual(")
            line = re.sub(r"\)\.to be (.*)", r", \1)", line)
        if "expect {" in line:
            line = line.replace("expect ", "")
            m = re.compile(
                r"(\s*)\{(.*)\}\.to raise_error\(.* [\"\/](.*)[\"\/]\)"
            ).match(line)
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
        if "expect(" in line and ".to include(" in line:
            m = re.compile(r"(\s*)expect\((.*)\)\.to include\((.*)\)").match(line)
            if m:
                line = f"{m.group(1)}self.assertIn([{m.group(3)}], {m.group(2)})\n"

        # Ruby:   target_names.each do |target_name|
        # Python: for target_name in target_names:
        m = re.compile(r"(\s*)(\S*)\.each do \|(.*)\|").match(line)
        if m:
            line = f"{m.group(1)} for {m.group(3)} in {m.group(2)}:\n"

        # Ruby:   x = y if y
        # Python: if y:
        #             x = y
        m = re.compile(r"(\s*)(\S.*) (if .*)").match(line)
        if m:
            line = f"{m.group(1)}{m.group(3)}\n{m.group(1)}    {m.group(2)}\n"

        # Convert Ruby Tempfile to python tempfile
        line = (
            line.replace(
                "tf = Tempfile.new('unittest')",
                'tf = tempfile.NamedTemporaryFile(mode="w")',
            )
            .replace("tf.path", "tf.name")
            .replace("tf.close", "tf.seek(0)")
            .replace("tf.unlink", "tf.close()")
        )
        line = re.sub(r"(\s*)tf.puts '(.*)'", r"\1tf.write('\2\\n')", line)
        # Usually << means append to a list
        line = re.sub(r"(.*) << (.*)", r"\1.append(\2)", line)
        line = re.sub(r"(\s*)case (.*)", r"\1match \2:", line)
        m = re.compile(r"(\s*)when (.*)").match(line)
        if m:
            line = re.sub(r"(\s*)when (.*)", r"\1case \2:", line)
            line.replace(",", "|")  # python separates values with | not ,
        line = (
            line.replace(".new(", "(")
            .replace(".new", "()")
            .replace(".freeze", "")
            .replace(".intern", "")
            .replace("Integer(", "int(")
            .replace("Float(", "float(")
            .replace("raise(ArgumentError, (", "raise AttributeError(f")
            .replace("raise(ArgumentError, ", "raise AttributeError(f")
            .replace(".class", ".__class__.__name__")
            .replace("JSON.parse", "json.loads")
            .replace("JSON.generate", "json.dumps")
            .replace("buffer(False)", "buffer_no_copy()")
            .replace("else", "else:")
            .replace("elsif", "elif:")
            .replace("true", "True")
            .replace("false", "False")
            .replace("nil", "None")
            .replace("unless", "if not")
            .replace("@", "self.")
            .replace(".upcase", ".upper()")
            .replace(".downcase", ".lower()")
            .replace(".unshift(", ".insert(0, ")
            .replace("#{", "{")
            .replace("=>", ":")
            .replace("begin", "try:")
            .replace("rescue", "except:")
            .replace(" && ", " and ")
            .replace(" || ", " or ")
            .replace("..-1]", ":]")
            .replace("...", ":")
        )
        out.write(line)

out.close()
