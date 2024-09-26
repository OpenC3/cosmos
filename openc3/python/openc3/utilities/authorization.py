# Copyright 2024 OpenC3, Inc.
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


class AuthError(RuntimeError):
    pass


class ForbiddenError(RuntimeError):
    pass


# All the authorization is done by Ruby code in the Ruby API backend.
# This code is basically a NOOP for now. If we ever want to build a whole
# new API endpoint in Python we'll have to implement an Enterprise
# authorize() like in Ruby.
def authorize(
    permission=None,
    target_name=None,
    packet_name=None,
    interface_name=None,
    router_name=None,
    manual=False,
    scope=None,
):
    if not scope:
        raise AuthError("Scope is required")


def user_info(_token):
    return {}  # EE does stuff here
