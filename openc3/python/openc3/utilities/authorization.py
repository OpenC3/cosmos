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

# require 'openc3/models/auth_model'
from openc3.api.authorized_api import OPENC3_AUTHORIZE


# begin
#   require 'openc3-enterprise/utilities/authorization'
# rescue LoadError
# If we're not in openc3-enterprise we define our own
class AuthError(RuntimeError):
    pass


class ForbiddenError(RuntimeError):
    pass


# Raises an exception if unauthorized, otherwise does nothing
def authorize(
    permission=None,
    target_name=None,
    packet_name=None,
    interface_name=None,
    router_name=None,
    scope=None,
):
    if not scope:
        raise AuthError("Scope is required")

    if OPENC3_AUTHORIZE:
        pass
        # if not AuthModel.verify(token, permission: permission):
        #     raise AuthError(f"Password is invalid for '{permission}' permission")


def user_info(_token):
    return {}  # EE does stuff here
