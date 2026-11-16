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

import re
from datetime import date, datetime, timedelta, timezone
from typing import Any

from openc3.environment import OPENC3_SCOPE
from openc3.models.activity_model import ActivityModel
from openc3.models.timeline_model import TimelineModel


__all__ = [
    "list_timelines",
    "create_timeline",
    "get_timeline",
    "set_timeline_color",
    "set_timeline_execute",
    "delete_timeline",
    "create_timeline_activity",
    "update_timeline_activity",
    "get_timeline_activity",
    "get_timeline_activities",
    "delete_timeline_activity",
    "count_timeline_activities",
    "commit_timeline_activity",
]


# NOTE: These methods are intentionally NOT added to WHITELIST. Their signatures
# match openc3/lib/openc3/script/calendar.rb (no manual/token kwargs), so they
# cannot be dispatched via JSON-RPC (which auto-injects manual/token from
# headers). The script-side calendar methods reach the server through the
# timeline/activity HTTP controllers, which call these helpers after performing
# their own authorization.


def list_timelines(scope: str = OPENC3_SCOPE) -> list[dict[str, Any]]:
    """Return all timelines in a scope.

    Args:
        scope: COSMOS scope.

    Returns:
        One dict per timeline.
    """
    ret = []
    for timeline, value in TimelineModel.all().items():
        if scope == timeline.split("__")[0]:
            ret.append(value)
    return ret


def create_timeline(name: str, color: str | None = None, scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Create a new timeline and deploy its microservice.

    Args:
        name: Timeline name.
        color: Display color, e.g. "#FF0000". Defaults to a random color.
        scope: COSMOS scope.

    Returns:
        The created timeline.
    """
    model = TimelineModel(name=name, color=color, scope=scope)
    model.create()
    model.deploy()
    return model.as_json()


def get_timeline(name: str, scope: str = OPENC3_SCOPE) -> dict[str, Any] | None:
    """Return a timeline.

    Args:
        name: Timeline name.
        scope: COSMOS scope.

    Returns:
        The timeline, or None if not found.
    """
    model = TimelineModel.get(name=name, scope=scope)
    if model is None:
        return None
    return model.as_json()


def set_timeline_color(name: str, color: str, scope: str = OPENC3_SCOPE) -> dict[str, Any] | None:
    """Set the color of an existing timeline.

    Args:
        name: Timeline name.
        color: Display color, e.g. "#FF0000".
        scope: COSMOS scope.

    Returns:
        The updated timeline, or None if not found.
    """
    model = TimelineModel.get(name=name, scope=scope)
    if model is None:
        return None
    model.color = color
    model.update()
    model.notify(kind="updated")
    return model.as_json()


def set_timeline_execute(name: str, enable: bool, scope: str = OPENC3_SCOPE) -> dict[str, Any] | None:
    """Set whether an existing timeline executes its activities.

    Args:
        name: Timeline name.
        enable: Whether the timeline executes its activities.
        scope: COSMOS scope.

    Returns:
        The updated timeline, or None if not found.
    """
    model = TimelineModel.get(name=name, scope=scope)
    if model is None:
        return None
    model.execute = enable
    model.update()
    model.notify(kind="updated")
    return model.as_json()


def delete_timeline(name: str, force: bool = False, scope: str = OPENC3_SCOPE) -> dict[str, str] | None:
    """Delete a timeline and undeploy its microservice.

    Args:
        name: Timeline name.
        force: Also delete the timeline's activities. Deleting a timeline
            which has activities fails without this.
        scope: COSMOS scope.

    Returns:
        {"name": name}, or None if not found.
    """
    model = TimelineModel.get(name=name, scope=scope)
    if model is None:
        return None
    TimelineModel.delete(name=name, scope=scope, force=force)
    model.undeploy()
    model.notify(kind="deleted")
    return {"name": name}


def create_timeline_activity(
    name: str,
    kind: str,
    start: int | float | str | date,
    stop: int | float | str | date,
    data: dict[str, Any] | None = None,
    recurring: dict[str, Any] | None = None,
    scope: str = OPENC3_SCOPE,
) -> dict[str, Any]:
    """Create a new activity on a timeline.

    Times may be epoch seconds, numeric strings, ISO 8601 strings, or
    datetime/date objects. Naive times are treated as UTC.

    Args:
        name: Timeline name.
        kind: Activity kind: command, script or reserve.
        start: Activity start time.
        stop: Activity stop time.
        data: Activity data. A "username" key, if present, is used for the
            audit event.
        recurring: Recurrence settings. An "end" key is converted to epoch
            seconds like start and stop.
        scope: COSMOS scope.

    Returns:
        The created activity.
    """
    if data is None:
        data = {}
    hash_ = {
        "kind": kind,
        "start": _cal_to_epoch(start),
        "stop": _cal_to_epoch(stop),
        "data": data,
    }
    if recurring:
        recurring = dict(recurring)
        if recurring.get("end"):
            recurring["end"] = _cal_to_epoch(recurring["end"])
        hash_["recurring"] = recurring
    model = ActivityModel.from_json(hash_, name=name, scope=scope)
    model.create(username=data.get("username"))
    return model.as_json()


def update_timeline_activity(
    name: str,
    id: int | str,
    kind: str,
    start: int | float | str | date,
    stop: int | float | str | date,
    uuid: str,
    data: dict[str, Any] | None = None,
    scope: str = OPENC3_SCOPE,
) -> dict[str, Any] | None:
    """Update an existing activity on a timeline.

    Args:
        name: Timeline name.
        id: Current start time of the activity in epoch seconds.
        kind: Activity kind: command, script or reserve.
        start: New start time. See `create_timeline_activity` for the formats.
        stop: New stop time. See `create_timeline_activity` for the formats.
        uuid: Activity UUID.
        data: Activity data. A "username" key, if present, is used for the
            audit event.
        scope: COSMOS scope.

    Returns:
        The updated activity, or None if not found.
    """
    if data is None:
        data = {}
    model = ActivityModel.score(name=name, score=int(id), uuid=uuid, scope=scope)
    if model is None:
        return None
    model.update(
        start=_cal_to_epoch(start),
        stop=_cal_to_epoch(stop),
        kind=kind,
        data=data,
        username=data.get("username"),
    )
    return model.as_json()


def get_timeline_activity(name: str, start: int | str, uuid: str, scope: str = OPENC3_SCOPE) -> dict[str, Any] | None:
    """Return an activity on a timeline.

    Args:
        name: Timeline name.
        start: Start time of the activity in epoch seconds.
        uuid: Activity UUID.
        scope: COSMOS scope.

    Returns:
        The activity, or None if not found.
    """
    model = ActivityModel.score(name=name, score=int(start), uuid=uuid, scope=scope)
    if model is None:
        return None
    return model.as_json()


def get_timeline_activities(
    name: str,
    start: int | float | str | date | None = None,
    stop: int | float | str | date | None = None,
    limit: int | None = None,
    scope: str = OPENC3_SCOPE,
) -> list[dict[str, Any]]:
    """Return the activities on a timeline within a time window.

    Args:
        name: Timeline name.
        start: Window start. Defaults to 7 days ago. See
            `create_timeline_activity` for the formats.
        stop: Window stop. Defaults to 7 days from now. See
            `create_timeline_activity` for the formats.
        limit: Maximum number of activities to return. Defaults to one per
            minute over the window.
        scope: COSMOS scope.

    Returns:
        The matching activities.
    """
    now = datetime.now(timezone.utc)
    start_score = int((now - timedelta(days=7)).timestamp()) if start is None else _cal_to_epoch(start)
    stop_score = int((now + timedelta(days=7)).timestamp()) if stop is None else _cal_to_epoch(stop)
    if limit is None:
        limit = (stop_score - start_score) // 60
    return ActivityModel.get(name=name, scope=scope, start=start_score, stop=stop_score, limit=limit)


def delete_timeline_activity(
    name: str, start: int | str, uuid: str, recurring: Any = None, scope: str = OPENC3_SCOPE
) -> int:
    """Delete an activity from a timeline.

    Args:
        name: Timeline name.
        start: Start time of the activity in epoch seconds.
        uuid: Activity UUID.
        recurring: When truthy, also delete every activity in the same
            recurring group.
        scope: COSMOS scope.

    Returns:
        The number of activities removed (0 indicates not found).
    """
    return ActivityModel.destroy(name=name, scope=scope, score=int(start), uuid=uuid, recurring=recurring)


def count_timeline_activities(name: str, scope: str = OPENC3_SCOPE) -> int:
    """Return the number of activities on a timeline.

    Args:
        name: Timeline name.
        scope: COSMOS scope.

    Returns:
        The activity count.
    """
    return ActivityModel.count(name=name, scope=scope)


def commit_timeline_activity(
    name: str, start: int | str, uuid: str, status: str, message: str | None = None, scope: str = OPENC3_SCOPE
) -> dict[str, Any] | None:
    """Record an event on an existing activity.

    Args:
        name: Timeline name.
        start: Start time of the activity in epoch seconds.
        uuid: Activity UUID.
        status: Event status.
        message: Optional event message.
        scope: COSMOS scope.

    Returns:
        The activity, or None if not found.
    """
    model = ActivityModel.score(name=name, score=int(start), uuid=uuid, scope=scope)
    if model is None:
        return None
    model.commit(status=status, message=message)
    return model.as_json()


_EPOCH_INT_RE = re.compile(r"\A-?\d+\Z")


def _cal_to_epoch(value: Any):
    """Convert a value to an epoch integer.

    Accepts int/float (treated as already-epoch), numeric strings, and
    ISO-style date/time strings or datetime/date objects.
    """
    # bool is a subclass of int in Python; treat it as int
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return int(value.timestamp())
    # datetime is a subclass of date, so check date last
    if isinstance(value, date):
        return int(datetime(value.year, value.month, value.day, tzinfo=timezone.utc).timestamp())
    s = str(value)
    if _EPOCH_INT_RE.match(s):
        return int(s)
    parsed = datetime.fromisoformat(s.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return int(parsed.timestamp())
