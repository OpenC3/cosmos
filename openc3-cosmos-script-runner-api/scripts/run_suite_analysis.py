# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import glob
import json
import os
import sys


# Read the one-line auth JSON the parent wrote to stdin right after spawn.
# Applied at runtime so the secret is never in the process environment.
try:
    auth = json.loads(sys.stdin.readline())["auth"]
    if not isinstance(auth, dict):
        raise ValueError("no auth")
except Exception:
    raise RuntimeError("run_suite_analysis: missing or malformed stdin credentials") from None
if str(auth.get("token") or "").strip():
    os.environ["OPENC3_API_TOKEN"] = auth["token"]
else:
    # Leave OPENC3_API_USER unset for a null username: an empty string is not None,
    # so ApiServerProxy.generate_auth would pick Keycloak over Core auth.
    if auth.get("user"):
        os.environ["OPENC3_API_USER"] = auth["user"]
    if auth.get("password"):
        os.environ["OPENC3_API_PASSWORD"] = auth["password"]
        # Core authenticates as the service; OpenC3Authentication sets its service
        # flag by comparing OPENC3_API_PASSWORD to OPENC3_SERVICE_PASSWORD.
        os.environ["OPENC3_SERVICE_PASSWORD"] = auth["password"]

import openc3.utilities.target_file_importer
from openc3.script import *  # noqa: F403
from openc3.script.suite_runner import SuiteRunner
from openc3.top_level import add_to_search_path
from openc3.utilities.script_env import clear_credentials
from openc3.utilities.target_file import TargetFile


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
        raise RuntimeError(f"Unable to retrieve: {procedure_name} in scope {openc3_scope}")
    else:
        text = text.decode()

    exec(text, globals())
    return False


openc3.script.load_utility = load_utility
openc3.script.require_utility = load_utility

data = None
with open(path) as file:
    data = file.read()

for path in glob.glob("/gems/gems/**/lib"):
    add_to_search_path(path, True)

clear_credentials()

exec(data, globals())

print(json.dumps(SuiteRunner.build_suites(from_globals=globals())))
