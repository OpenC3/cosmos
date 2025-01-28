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

import json
import openc3.script
from openc3.environment import OPENC3_SCOPE

def table_create_binary(definition: str, scope: str = OPENC3_SCOPE):
    data = {}
    data['definition'] = definition
    response = openc3.script.API_SERVER.request("post", "/openc3-api/tables/generate", data=data, json=True, scope=scope)
    return _handle_response(response, 'Failed to create binary')

def table_create_report(filename: str, definition: str, table_name: str = None, scope: str = OPENC3_SCOPE):
    data = {}
    data['binary'] = filename
    data['definition'] = definition
    if table_name:
        data['table_name'] = table_name
    response = openc3.script.API_SERVER.request("post", "/openc3-api/tables/report", data=data, json=True, scope=scope)
    return _handle_response(response, 'Failed to create binary')

# Helper method to handle the response
def _handle_response(response, error_message):
    if response is None:
        return None
    if response.status_code >= 400:
        result = json.loads(response.text)
        raise RuntimeError(f"{error_message} due to {result['message']}")
    # Not sure why the response body is empty (on delete) but check for that
    if response.text is None or len(response.text) == 0:
        return None
    else:
        return json.loads(response.text)
