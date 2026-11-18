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

import json
import traceback
from typing import Any

import openc3.script
from openc3.environment import OPENC3_SCOPE


def package_list(scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Return the installed Ruby gems and Python packages.

    Args:
        scope: COSMOS scope.

    Returns:
        {"ruby": gem file names, "python": Python packages}. The Python
        packages are grouped by where they are installed.

    Raises:
        RuntimeError: If the request fails.
    """
    try:
        endpoint = f"/openc3-api/packages?scope={scope}"
        response = openc3.script.API_SERVER.request("get", endpoint, scope=scope)
        if not response or response.status_code != 200:
            raise RuntimeError(f"Unexpected response to package_list: {response}")
        return json.loads(response.text)
    except Exception as error:
        raise RuntimeError(f"package_list failed due to {traceback.format_exc()}") from error
