# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.api import WHITELIST
from openc3.environment import OPENC3_SCOPE
from openc3.models.shared_resource_model import SharedResourceModel
from openc3.utilities.authorization import authorize, user_info
from openc3.utilities.logger import Logger


WHITELIST.extend(
    [
        "get_shared_resources",
        "get_shared_resource",
        "switch_shared_resource",
        "release_shared_resource",
    ]
)


def get_shared_resources(scope=OPENC3_SCOPE, manual=False):
    """Return the shared resources with members in the scope"""
    authorize(permission="system", scope=scope, manual=manual)
    records = [record for record in SharedResourceModel.all().values() if scope in record["members"]]
    return sorted(records, key=lambda record: record["name"])


def get_shared_resource(name, scope=OPENC3_SCOPE, manual=False):
    """Return the shared resource or None if it doesn't exist"""
    authorize(permission="system", scope=scope, manual=manual)
    return SharedResourceModel.get(name)


def switch_shared_resource(name, to_scope=None, force=False, scope=OPENC3_SCOPE, manual=False):
    """Make a shared resource active in to_scope (default is the current scope).
    Its microservices in the currently active scope are stopped before those in the new scope start."""
    if to_scope is None:
        to_scope = scope
    # Switching affects both scopes so require admin in each
    authorize(permission="admin", scope=to_scope, manual=manual)
    record = SharedResourceModel.get(name)
    if not record:
        raise RuntimeError(f"Shared resource '{str(name).upper()}' does not exist")
    if record["owner"] and record["owner"] != to_scope:
        authorize(permission="admin", scope=record["owner"], manual=manual)
    record = SharedResourceModel.switch(name, to_scope=to_scope, force=force)
    username = user_info(None).get("username") or "Anonymous"
    forced = " (forced)" if force else ""
    Logger.info(
        f"User {username} switched shared resource {record['name']} to scope {to_scope}{forced}",
        scope=to_scope,
        user=username,
    )
    return record


def release_shared_resource(name, force=False, scope=OPENC3_SCOPE, manual=False):
    """Release a shared resource so it is not active in any scope"""
    authorize(permission="admin", scope=scope, manual=manual)
    record = SharedResourceModel.get(name)
    if not record:
        raise RuntimeError(f"Shared resource '{str(name).upper()}' does not exist")
    if record["owner"] and record["owner"] != scope:
        authorize(permission="admin", scope=record["owner"], manual=manual)
    record = SharedResourceModel.release(name, force=force)
    username = user_info(None).get("username") or "Anonymous"
    forced = " (forced)" if force else ""
    Logger.info(f"User {username} released shared resource {record['name']}{forced}", scope=scope, user=username)
    return record
