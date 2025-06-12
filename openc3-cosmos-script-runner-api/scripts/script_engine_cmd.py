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

import sys
import os
import glob
from openc3.top_level import get_class_from_module, add_to_search_path
from openc3.utilities.string import (
    filename_to_module,
    filename_to_class_name,
)
from openc3.models.script_engine_model import ScriptEngineModel

for path in glob.glob("/gems/gems/**/lib"):
    add_to_search_path(path, True)

class RunningScriptProxy:
    def pre_line_instrumentation(self, filename, line_number, global_variables, local_variables):
        pass

    def post_line_instrumentation(self, filename, line_number):
        pass

    def exception_instrumentation(self, filename, line_number):
        pass

command = sys.argv[1]
filename = sys.argv[2]
extension = str(os.path.splitext(filename)[1]).lower()

script_engine_filename = None
script_engine_model = ScriptEngineModel.get_model(name = extension, scope = 'DEFAULT')
if script_engine_model is not None:
    script_engine_filename = script_engine_model.filename
else:
    print(f"Script Engine for {filename} not found")
    exit(1)

klass = get_class_from_module(
    filename_to_module(script_engine_filename),
    filename_to_class_name(script_engine_filename),
)
running_script_proxy = RunningScriptProxy()
script_engine = klass(running_script_proxy)

# Read File Text
text = ""
with open(filename, 'r') as file:
    text = file.read()

exit_code = 0
match command:
    case "syntax_check":
        exit_code = script_engine.syntax_check(text, filename)

    case "mnemonic_check":
        exit_code = script_engine.mnemonic_check(text, filename)

    case _:
        print(f"Unknown command: {command}")
        exit_code = 1

exit(exit_code)