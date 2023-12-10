# Copyright 2023 OpenC3, Inc.
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

import sys
import json
import os
import importlib
from openc3.script.suite_runner import SuiteRunner

openc3_scope = sys.argv[1]  # argv[0] is the script name
path = sys.argv[2]
module_path = os.path.dirname(path)

python_path = os.environ.get("PYTHONPATH") or ""
if len(python_path) > 0:
    sys.path.append(python_path + ":" + module_path)
else:
    sys.path.append(module_path)

filename = os.path.basename(path)
file_no_ext, extension = os.path.splitext(filename)
my_module = importlib.import_module(file_no_ext)

print(json.dumps(SuiteRunner.build_suites(from_module=my_module)))
