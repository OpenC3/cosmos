# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os

from openc3.api import WHITELIST
from openc3.environment import OPENC3_SCOPE
from openc3.models.offline_access_model import OfflineAccessModel
from openc3.utilities.authentication import (
    OpenC3KeycloakAuthentication,
)
from openc3.utilities.authorization import authorize


try:
    from openc3enterprise.utilities.authorization import user_info
except ImportError:
    from openc3.utilities.authorization import user_info

WHITELIST.extend(["offline_access_needed", "set_offline_access"])


def offline_access_needed(manual: bool = False, scope: str = OPENC3_SCOPE, token: str | None = None) -> bool:
    """Return whether the current user needs to provide an offline access token.

    An offline access token is needed when the user has the offline_access
    role but no stored token, or the stored token can no longer be refreshed.
    An invalid stored token is cleared. Users who cannot run scripts never
    need one.

    Args:
        manual: Whether the request was made manually by a user.
        scope: COSMOS scope.
        token: Access token of the requesting user.

    Returns:
        True if an offline access token is needed, otherwise False.
    """
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


def set_offline_access(
    offline_access_token: str, manual: bool = False, scope: str = OPENC3_SCOPE, token: str | None = None
) -> None:
    """Store the offline access token for the current user.

    Args:
        offline_access_token: Keycloak offline access (refresh) token.
        manual: Whether the request was made manually by a user.
        scope: COSMOS scope.
        token: Access token of the requesting user.

    Raises:
        ValueError: If the requesting user has no username.
    """
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
