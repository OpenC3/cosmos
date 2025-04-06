# Copyright 2025 OpenC3, Inc
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os
from openc3.api import WHITELIST
from openc3.environment import OPENC3_SCOPE
from openc3.utilities.authorization import authorize
from openc3.models.offline_access_model import OfflineAccessModel
from openc3.utilities.authentication import (
    OpenC3KeycloakAuthentication,
)

try:
    from openc3enterprise.utilities.authorization import user_info
except ImportError:
    from openc3.utilities.authorization import user_info

WHITELIST.extend(["offline_access_needed", "set_offline_access"])


def offline_access_needed(manual=False, scope=OPENC3_SCOPE, token=None):
    authorize(permission="system", manual=manual, scope=scope)
    try:
        authorize(permission="script_view", manual=manual, scope=scope)
    except Exception:
        # Not needed if can't run scripts
        return False
    info = user_info(token)
    if "offline_access" in info["roles"]:
        username = info["username"]
        if username and username != "":
            model = OfflineAccessModel.get_model(name=username, scope=scope)
            if model and model.offline_access_token:
                auth = OpenC3KeycloakAuthentication(os.environ.get("OPENC3_KEYCLOAK_URL"))
                valid_token = auth.get_token_from_refresh_token(model.offline_access_token)
                if valid_token:
                    return False
                else:
                    model.offline_access_token = None
                    model.update()
                    return True
            return True
        else:
            return False
    else:
        return False


def set_offline_access(offline_access_token, manual=False, scope=OPENC3_SCOPE, token=None):
    authorize(permission="script_view", manual=manual, scope=scope)
    info = user_info(token)
    username = info["username"]
    if not username or username == "":
        raise ValueError("Invalid username")
    model = OfflineAccessModel.get_model(name=username, scope=scope)
    if model:
        model.offline_access_token = offline_access_token
        model.update()
    else:
        model = OfflineAccessModel(name=username, offline_access_token=offline_access_token, scope=scope)
        model.create()
