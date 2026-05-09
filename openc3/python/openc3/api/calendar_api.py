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


def list_timelines(scope=OPENC3_SCOPE):
    """Returns a list of all timelines for the given scope."""
    ret = []
    for timeline, value in TimelineModel.all().items():
        if scope == timeline.split("__")[0]:
            ret.append(value)
    return ret


def create_timeline(name, color=None, scope=OPENC3_SCOPE):
    """Creates a new timeline and deploys its microservice.

    Returns the created timeline as a dict.
    """
    model = TimelineModel(name=name, color=color, scope=scope)
    model.create()
    model.deploy()
    return model.as_json()


def get_timeline(name, scope=OPENC3_SCOPE):
    """Returns the timeline as a dict, or None if not found."""
    model = TimelineModel.get(name=name, scope=scope)
    if model is None:
        return None
    return model.as_json()


def set_timeline_color(name, color, scope=OPENC3_SCOPE):
    """Updates the color of an existing timeline.

    Returns the updated timeline as a dict, or None if not found.
    """
    model = TimelineModel.get(name=name, scope=scope)
    if model is None:
        return None
    model.color = color
    model.update()
    model.notify(kind="updated")
    return model.as_json()


def set_timeline_execute(name, enable, scope=OPENC3_SCOPE):
    """Updates the execute flag of an existing timeline.

    Returns the updated timeline as a dict, or None if not found.
    """
    model = TimelineModel.get(name=name, scope=scope)
    if model is None:
        return None
    model.execute = enable
    model.update()
    model.notify(kind="updated")
    return model.as_json()


def delete_timeline(name, force=False, scope=OPENC3_SCOPE):
    """Deletes a timeline (and optionally all of its activities when force is True).

    Returns {"name": name}, or None if not found.
    """
    model = TimelineModel.get(name=name, scope=scope)
    if model is None:
        return None
    TimelineModel.delete(name=name, scope=scope, force=force)
    model.undeploy()
    model.notify(kind="deleted")
    return {"name": name}


def create_timeline_activity(name, kind, start, stop, data=None, recurring=None, scope=OPENC3_SCOPE):
    """Creates a new activity on the specified timeline.

    username is read from data['username'] if present and is used for the audit event.
    Returns the created activity as a dict.
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


def update_timeline_activity(name, id, kind, start, stop, uuid, data=None, scope=OPENC3_SCOPE):
    """Updates an existing activity on the specified timeline.

    Returns the updated activity as a dict, or None if not found.
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


def get_timeline_activity(name, start, uuid, scope=OPENC3_SCOPE):
    """Returns the activity as a dict, or None if not found."""
    model = ActivityModel.score(name=name, score=int(start), uuid=uuid, scope=scope)
    if model is None:
        return None
    return model.as_json()


def get_timeline_activities(name, start=None, stop=None, limit=None, scope=OPENC3_SCOPE):
    """Returns activities on the timeline in the given window.

    When start/stop are None, defaults to a window of [now - 7 days, now + 7 days].
    When limit is None, defaults to one event per minute over the window.
    Returns a list of matching activities.
    """
    now = datetime.now(timezone.utc)
    start_score = int((now - timedelta(days=7)).timestamp()) if start is None else _cal_to_epoch(start)
    stop_score = int((now + timedelta(days=7)).timestamp()) if stop is None else _cal_to_epoch(stop)
    if limit is None:
        limit = (stop_score - start_score) // 60
    return ActivityModel.get(name=name, scope=scope, start=start_score, stop=stop_score, limit=limit)


def delete_timeline_activity(name, start, uuid, recurring=None, scope=OPENC3_SCOPE):
    """Removes an activity (or all members of its recurring group when recurring is truthy).

    Returns the number of activities removed (0 indicates not found).
    """
    return ActivityModel.destroy(name=name, scope=scope, score=int(start), uuid=uuid, recurring=recurring)


def count_timeline_activities(name, scope=OPENC3_SCOPE):
    """Returns the count of activities on the timeline."""
    return ActivityModel.count(name=name, scope=scope)


def commit_timeline_activity(name, start, uuid, status, message=None, scope=OPENC3_SCOPE):
    """Commits an event to an existing activity.

    Returns the activity as a dict, or None if not found.
    """
    model = ActivityModel.score(name=name, score=int(start), uuid=uuid, scope=scope)
    if model is None:
        return None
    model.commit(status=status, message=message)
    return model.as_json()


_EPOCH_INT_RE = re.compile(r"\A-?\d+\Z")


def _cal_to_epoch(value):
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
