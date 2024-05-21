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
from openc3.script.suite_runner import SuiteRunner
from openc3.utilities.target_file import TargetFile
from openc3.script import *

openc3_scope = sys.argv[1]  # argv[0] is the script name
path = sys.argv[2]


# Load an additional python file
def load_utility(procedure_name):
    global openc3_scope
    extension = os.path.splitext(procedure_name)[1]
    if extension != ".py":
        procedure_name += ".py"

    # Retrieve file
    text = TargetFile.body(openc3_scope, procedure_name)
    if not text:
        raise RuntimeError(
            f"Unable to retrieve: {procedure_name} in scope {openc3_scope}"
        )
    else:
        text = text.decode()

    exec(text, globals())
    return False


data = None
with open(path) as file:
    data = file.read()

exec(data, globals())

print(json.dumps(SuiteRunner.build_suites(from_globals=globals())))
