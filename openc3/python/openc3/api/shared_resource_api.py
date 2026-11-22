# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from typing import Any

from openc3.api import WHITELIST
from openc3.environment import OPENC3_SCOPE
from openc3.models.shared_resource_model import SharedResourceModel
from openc3.utilities.authorization import ForbiddenError, authorize, user_info
from openc3.utilities.logger import Logger


__all__ = [
    "get_shared_resources",
    "get_shared_resource",
    "switch_shared_resource",
    "release_shared_resource",
]


WHITELIST.extend(
    [
        "get_shared_resources",
        "get_shared_resource",
        "switch_shared_resource",
        "release_shared_resource",
    ]
)


def get_shared_resources(scope: str = OPENC3_SCOPE, manual: bool = False) -> list[dict[str, Any]]:
    """Return the shared resources with members in the scope.

    Members in scopes the user can't access are left out.

    Args:
        scope: COSMOS scope.
        manual: Whether the call was made manually by a user.

    Returns:
        The shared resources sorted by name. Each has name, owner, state, to,
        waiting, and members (scope to list of type, name, and shard).
    """
    authorize(permission="system", scope=scope, manual=manual)
    records = [record for record in SharedResourceModel.all().values() if scope in record["members"]]
    records = sorted(records, key=lambda record: record["name"])
    accessible = {scope: True}
    return [_shared_resource_for_user(record, accessible, manual) for record in records]


def get_shared_resource(name: str, scope: str = OPENC3_SCOPE, manual: bool = False) -> dict[str, Any] | None:
    """Return a shared resource.

    Members in scopes the user can't access are left out.

    Args:
        name: Shared resource name.
        scope: COSMOS scope.
        manual: Whether the call was made manually by a user.

    Returns:
        The shared resource, or None if it doesn't exist or has no members in the scope.
    """
    authorize(permission="system", scope=scope, manual=manual)
    record = SharedResourceModel.get(name)
    if not record or scope not in record["members"]:
        return None
    return _shared_resource_for_user(record, {scope: True}, manual)


def switch_shared_resource(
    name: str, to_scope: str | None = None, force: bool = False, scope: str = OPENC3_SCOPE, manual: bool = False
) -> dict[str, Any]:
    """Make a shared resource active in a scope.

    Its microservices in the currently active scope are stopped before those in
    the new scope start. Requires admin in both scopes.

    Args:
        name: Shared resource name.
        to_scope: Scope to make the resource active in. Defaults to the current scope.
        force: Don't wait for the active scope's microservices to stop.
        scope: COSMOS scope.
        manual: Whether the call was made manually by a user.

    Returns:
        The updated shared resource.

    Raises:
        RuntimeError: If the shared resource does not exist or has no members in to_scope.
    """
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


def release_shared_resource(
    name: str, force: bool = False, scope: str = OPENC3_SCOPE, manual: bool = False
) -> dict[str, Any]:
    """Release a shared resource so it is not active in any scope.

    Args:
        name: Shared resource name.
        force: Don't wait for the active scope's microservices to stop.
        scope: COSMOS scope.
        manual: Whether the call was made manually by a user.

    Returns:
        The updated shared resource.

    Raises:
        RuntimeError: If the shared resource does not exist.
    """
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


def _shared_resource_for_user(record: dict[str, Any], accessible: dict[str, bool], manual: bool) -> dict[str, Any]:
    """Remove the members of scopes the user doesn't have system permission in.

    The owner's waiting members are removed too if the user can't access the
    owner. The owner and state stay so the UI can say where the resource is
    active. accessible caches scope to whether the user can access it.
    """

    def can_access(other_scope: str) -> bool:
        if other_scope not in accessible:
            try:
                authorize(permission="system", scope=other_scope, manual=manual)
                accessible[other_scope] = True
            except ForbiddenError:
                accessible[other_scope] = False
        return accessible[other_scope]

    record = dict(record)
    record["members"] = {
        member_scope: members for member_scope, members in record["members"].items() if can_access(member_scope)
    }
    if record.get("owner") and record.get("waiting") and not can_access(record["owner"]):
        record["waiting"] = []
    return record
