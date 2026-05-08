# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# https://www.rubydoc.info/gems/redis/Redis/Commands/SortedSets

import json
import time
import uuid as uuid_module
from datetime import datetime, timezone

from openc3.models.model import Model
from openc3.topics.timeline_topic import TimelineTopic
from openc3.utilities.store import Store
from openc3.utilities.time import to_nsec_from_epoch


class ActivityError(RuntimeError):
    pass


class ActivityInputError(ActivityError):
    pass


class ActivityOverlapError(ActivityError):
    pass


def _decode(value):
    return value.decode() if isinstance(value, (bytes, bytearray)) else value


class ActivityModel(Model):
    SEC_PER_DAY = 86400
    MAX_DURATION = SEC_PER_DAY
    # Grace window (in seconds) to allow creating activities slightly in the past.
    # This handles race conditions where real-time activity notifications arrive
    # after the start time has already passed (e.g. from external systems).
    # This is consistent with the -15 second window in the timeline microservice.
    START_GRACE_SECONDS = 15
    # MUST be equal to TimelineModel.PRIMARY_KEY minus the leading __
    PRIMARY_KEY = "__openc3_timelines"
    # See run_activity(activity) in openc3/lib/openc3/microservices/timeline_microservice.rb
    VALID_KINDS = ["command", "script", "reserve", "expire"]

    # Called via the microservice; gets the previous 00:00:15 to 01:01:00. This allows
    # for a small buffer around the timeline so the schedule doesn't get stale.
    # 00:00:15 was selected because the schedule queue used in the microservice has a
    # round-robin array with 15 slots to make sure we don't miss a planned task.
    @classmethod
    def activities(cls, name, scope):
        now = time.time()
        start_score = now - 15
        stop_score = now + 3660
        array = Store.zrangebyscore(f"{scope}{cls.PRIMARY_KEY}__{name}", start_score, stop_score)
        return [cls.from_json(value, name=name, scope=scope) for value in array]

    # Up to ``limit`` (default 100) activities scored between ``start`` and ``stop``,
    # returned as dicts.
    @classmethod
    def get(cls, name, start, stop, scope, limit=100):
        if start > stop:
            raise ActivityInputError(f"start: {start} must be <= stop: {stop}")
        array = Store.zrangebyscore(f"{scope}{cls.PRIMARY_KEY}__{name}", start, stop, start=0, num=limit)
        return [json.loads(_decode(value)) for value in array]

    # Up to ``limit`` activities (as dicts) stored under the primary key.
    @classmethod
    def all(cls, name, scope, limit=100):
        # zrange does not support limit when called by index; cap the index range instead.
        array = Store.zrange(f"{scope}{cls.PRIMARY_KEY}__{name}", 0, limit - 1)
        return [json.loads(_decode(value)) for value in array]

    # Returns the saved ActivityModel at ``score``, optionally filtered by ``uuid``,
    # or ``None`` if not found.
    @classmethod
    def score(cls, name, score, scope, uuid=None):
        values = Store.zrangebyscore(f"{scope}{cls.PRIMARY_KEY}__{name}", score, score)
        if values:
            if uuid:
                for value in values:
                    activity = cls.from_json(value, name=name, scope=scope)
                    if activity.uuid == uuid:
                        return activity
            else:
                return cls.from_json(values[0], name=name, scope=scope)
        return None

    @classmethod
    def count(cls, name, scope):
        return Store.zcard(f"{scope}{cls.PRIMARY_KEY}__{name}")

    # Remove one member (or all members of its recurring group) from a sorted set.
    # Returns the count of activities removed (0 indicates not found).
    @classmethod
    def destroy(cls, name, scope, score, uuid=None, recurring=None):
        result = 0
        primary = f"{scope}{cls.PRIMARY_KEY}__{name}"

        # Delete all recurring activities
        if recurring:
            activity = cls.score(name=name, score=score, scope=scope)
            if activity and activity.recurring.get("end") and activity.recurring.get("uuid"):
                json_values = Store.zrangebyscore(primary, activity.recurring["start"], activity.recurring["end"])
                parsed = [cls.from_json(value, name=name, scope=scope) for value in json_values]
                for index, value in enumerate(parsed):
                    if value.recurring.get("uuid") == uuid:
                        Store.zrem(primary, json_values[index])
                        result += 1

        # First find all the activities at the score
        json_values = Store.zrangebyscore(primary, score, score, start=0, num=100)
        parsed = [json.loads(_decode(value)) for value in json_values]
        for index, value in enumerate(parsed):
            if uuid:
                # If a uuid is given then only delete activities matching that uuid
                if value.get("uuid") == uuid:
                    Store.zrem(primary, json_values[index])
                    result += 1
                    break
            else:
                # If no uuid is given (backwards compatibility) delete all activities
                # at the score that do NOT have a uuid
                if value.get("uuid"):
                    continue
                Store.zrem(primary, json_values[index])
                result += 1

        notification = {
            # start / stop to match SortedModel
            "data": json.dumps({"start": score, "uuid": uuid}),
            "kind": "deleted",
            "type": "activity",
            "timeline": name,
        }
        TimelineTopic.write_activity(notification, scope=scope)
        return result

    # Remove members from min to max of the sorted set.
    @classmethod
    def range_destroy(cls, name, scope, min, max):
        result = Store.zremrangebyscore(f"{scope}{cls.PRIMARY_KEY}__{name}", min, max)
        notification = {
            # start / stop to match SortedModel
            "data": json.dumps({"start": min, "stop": max}),
            "kind": "deleted",
            "type": "activity",
            "timeline": name,
        }
        TimelineTopic.write_activity(notification, scope=scope)
        return result

    @classmethod
    def from_json(cls, json_data, name, scope):
        if isinstance(json_data, (str, bytes)):
            json_data = json.loads(_decode(json_data))
        if json_data is None:
            raise RuntimeError("json data is nil")
        json_data = dict(json_data)
        json_data.pop("name", None)
        json_data.pop("scope", None)
        return cls(name=name, scope=scope, **json_data)

    def __init__(
        self,
        name,
        start,
        stop,
        kind,
        data,
        scope,
        updated_at=0,
        fulfillment=None,
        uuid=None,
        events=None,
        recurring=None,
    ):
        super().__init__(f"{scope}{self.PRIMARY_KEY}__{name}", name=name, scope=scope)
        # Default mutable args
        if recurring is None:
            recurring = {}
        # Validate everything that isn't already in Model
        self.recurring = recurring
        self.set_input(
            start=start,
            stop=stop,
            kind=kind,
            data=data,
            fulfillment=fulfillment,
            uuid=uuid,
            events=events,
            recurring=recurring,
        )
        self.updated_at = updated_at

    # validate_time searches from the current activity ``stop`` (exclusive — we allow overlap of
    # stop with start) back through ``start - MAX_DURATION``. The method validates that this new
    # activity does not overlap anything else. We search back past ``start`` through MAX_DURATION
    # because we need to inspect activities that may start before us and verify we don't overlap
    # their stop times. Activities are inserted by ``start`` time so we have to walk backward to
    # check existing stops.
    #
    # Score is seconds since the Unix Epoch. ``zrevrangebyscore`` finds activities in reverse so
    # the first task is the closest to the current score. ``ignore_score`` lets the request skip
    # a known existing time when doing an update. Returns the start time of a colliding activity,
    # or None if none was found.
    def validate_time(self, start, stop, ignore_score=None):
        # Adding a '(' makes the max value exclusive
        array = Store.zrevrangebyscore(self.primary_key, f"({stop}", start - self.MAX_DURATION)
        for value in array:
            activity = json.loads(_decode(value))
            if ignore_score == activity["start"]:
                continue
            if activity["stop"] > start:
                return activity["start"]
            return None
        return None

    # Validate the input against the rules we have created for timelines.
    # - A task's start MUST NOT be more than START_GRACE_SECONDS in the past.
    # - A task's start MUST be before the stop.
    # - A task CAN NOT be longer than MAX_DURATION (86400) in seconds.
    # - A task MUST have a kind.
    # - A task MUST have a data object/dict.
    def validate_input(self, start, stop, kind, data):
        try:
            datetime.fromtimestamp(int(start), tz=timezone.utc)
            datetime.fromtimestamp(int(stop), tz=timezone.utc)
        except (TypeError, ValueError, OverflowError, OSError) as e:
            raise ActivityInputError(f"start and stop must be seconds: {start}, {stop}") from e
        now_f = time.time()
        try:
            duration = stop - start
        except TypeError as e:
            raise ActivityInputError(f"start and stop must be seconds: {start}, {stop}") from e
        if now_f >= start + self.START_GRACE_SECONDS and kind != "expire":
            raise ActivityInputError(
                f"activity must not be more than {self.START_GRACE_SECONDS} seconds in the past, "
                f"current_time: {now_f} vs {start}"
            )
        elif duration > self.MAX_DURATION and kind != "expire":
            raise ActivityInputError(f"activity can not be longer than {self.MAX_DURATION} seconds")
        elif duration <= 0:
            raise ActivityInputError(f"start: {start} must be before stop: {stop}")
        elif kind not in self.VALID_KINDS:
            raise ActivityInputError(f"unknown kind: {kind}, must be one of {', '.join(self.VALID_KINDS)}")
        elif data is None:
            raise ActivityInputError(f"data must not be nil: {data}")
        elif not isinstance(data, dict):
            raise ActivityInputError(f"data must be a json object/hash: {data}")

    # Set the values of the instance: start, kind, data, events, etc.
    def set_input(self, start, stop, kind=None, data=None, uuid=None, events=None, fulfillment=None, recurring=None):
        kind = str(kind).lower()
        self.validate_input(start=start, stop=stop, kind=kind, data=data)
        self.start = start
        self.stop = stop
        self.fulfillment = False if fulfillment is None else fulfillment
        self.kind = kind
        if data is not None:
            self.data = data
        self.uuid = uuid if uuid is not None else str(uuid_module.uuid4())
        self.events = [] if events is None else events
        if recurring is not None:
            self.recurring = recurring

    # Update the Redis hash at primary_key and set the score equal to the start Epoch time.
    # The member is set to the JSON generated via calling as_json.
    def create(self, overlap=True, username=None):
        # Avoid circular import: timeline_model imports activity-related modules indirectly
        from openc3.models.timeline_model import TimelineModel

        # Validate that the timeline exists in this scope before creating activities.
        # Activities must be attached to an existing timeline within the same scope.
        if not TimelineModel.get(name=self.name, scope=self.scope):
            raise ActivityError(f"timeline '{self.name}' does not exist in scope '{self.scope}'")

        if self.recurring.get("end") and self.recurring.get("frequency") and self.recurring.get("span"):
            # First validate the initial recurring activity ... all others are just offsets
            self.validate_input(start=self.start, stop=self.stop, kind=self.kind, data=self.data)

            # Create a uuid for deleting related recurring activities in the future
            self.recurring["uuid"] = str(uuid_module.uuid4())
            self.recurring["start"] = self.start
            duration = self.stop - self.start
            recurrence = 0
            span = self.recurring["span"]
            frequency = int(self.recurring["frequency"])
            if span == "minutes":
                recurrence = frequency * 60
            elif span == "hours":
                recurrence = frequency * 3600
            elif span == "days":
                recurrence = frequency * 86400

            existing = []
            if not overlap:
                # Get all the existing events in the recurring time range as well as those before
                # the start of the recurring time range to ensure we don't start inside an existing event
                raw = Store.zrevrangebyscore(
                    self.primary_key,
                    self.recurring["end"] - 1,
                    self.recurring["start"] - self.MAX_DURATION,
                )
                existing = [json.loads(_decode(value)) for value in raw]
            last_stop = None

            # Update updated_at and add an event assuming it all completes ok
            self.updated_at = to_nsec_from_epoch(datetime.now(timezone.utc))
            self.add_event(status="created", username=username)

            start_time = self.start
            while start_time <= self.recurring["end"]:
                self.start = start_time
                self.stop = start_time + duration
                self.uuid = str(uuid_module.uuid4())

                if last_stop is not None and self.start < last_stop:
                    self.events.pop()  # Remove previously created event
                    raise ActivityOverlapError(
                        "Recurring activity overlap. Increase recurrence delta or decrease activity duration."
                    )
                if not overlap:
                    for value in existing:
                        if (value["start"] <= self.start < value["stop"]) or (
                            value["start"] < self.stop <= value["stop"]
                        ):
                            self.events.pop()  # Remove previously created event
                            raise ActivityOverlapError(f"activity overlaps existing at {value['start']}")
                Store.zadd(self.primary_key, {json.dumps(self.as_json()): self.start})
                last_stop = self.stop
                start_time += recurrence
            self.notify(kind="created")
        else:
            self.validate_input(start=self.start, stop=self.stop, kind=self.kind, data=self.data)
            if not overlap:
                # If we don't allow overlap we need to validate the time
                collision = self.validate_time(self.start, self.stop)
                if collision is not None:
                    raise ActivityOverlapError(f"activity overlaps existing at {collision}")
            self.updated_at = to_nsec_from_epoch(datetime.now(timezone.utc))
            self.add_event(status="created", username=username)
            Store.zadd(self.primary_key, {json.dumps(self.as_json()): self.start})
            self.notify(kind="created")

    # Update the Redis hash at primary_key by removing the current activity at the current score
    # and re-inserting at the new score. The remove and create are issued sequentially.
    def update(self, start, stop, kind, data, overlap=True, username=None):
        array = Store.zrangebyscore(self.primary_key, self.start, self.start)
        if len(array) == 0:
            raise ActivityError(f"failed to find activity at: {self.start}")

        old_start = self.start
        old_uuid = self.uuid
        if not overlap:
            # If we don't allow overlap we need to validate the time
            collision = self.validate_time(start, stop, ignore_score=old_start)
            if collision is not None:
                raise ActivityOverlapError(
                    f"failed to update {old_start}, no activities can overlap, collision: {collision}"
                )

        # Compute changeset for audit trail before applying changes
        changes = {}
        self.diff_field(changes, "start", self.start, start)
        self.diff_field(changes, "stop", self.stop, stop)
        self.diff_field(changes, "kind", self.kind, kind)
        old_data = {k: v for k, v in self.data.items() if k != "username"}
        new_data = {k: v for k, v in data.items() if k != "username"}
        for key in set(old_data.keys()) | set(new_data.keys()):
            self.diff_field(changes, f"data.{key}", old_data.get(key), new_data.get(key))

        self.set_input(start=start, stop=stop, kind=kind, data=data, events=self.events)
        self.updated_at = to_nsec_from_epoch(datetime.now(timezone.utc))

        self.add_event(status="updated", username=username, changes=changes if changes else None)
        json_values = Store.zrangebyscore(self.primary_key, old_start, old_start)
        parsed = [json.loads(_decode(value)) for value in json_values]
        for index, value in enumerate(parsed):
            if value.get("uuid") == old_uuid:
                Store.zrem(self.primary_key, json_values[index])
                Store.zadd(self.primary_key, {json.dumps(self.as_json()): self.start})
        self.notify(kind="updated", extra={"old_start": old_start, "old_uuid": old_uuid})
        return self.start

    # commit will make an event and save the object to the redis database
    # status: the event status such as "complete" or "failed"
    # message: an optional message to include in the event
    # timestamp: optional datetime to use instead of current time
    def commit(self, status, message=None, fulfillment=None, timestamp=None):
        event = {
            "time": int(timestamp.timestamp()) if timestamp is not None else int(time.time()),
            "event": status,
            "commit": True,
        }
        if message is not None:
            event["message"] = message
        if fulfillment is not None:
            self.fulfillment = fulfillment
        self.events.append(event)

        json_values = Store.zrangebyscore(self.primary_key, self.start, self.start)
        parsed = [json.loads(_decode(value)) for value in json_values]
        for index, value in enumerate(parsed):
            if value.get("uuid") == self.uuid:
                Store.zrem(self.primary_key, json_values[index])
                Store.zadd(self.primary_key, {json.dumps(self.as_json()): self.start})
        self.notify(kind="event")

    # add_event will make an event. This will NOT save the object to the redis database.
    # status: the event status such as "queued" or "updated" or "created"
    # username: optional username of who performed the action
    # changes: optional dict describing what fields changed (for audit)
    def add_event(self, status, username=None, changes=None):
        event = {
            "time": int(time.time()),
            "event": status,
        }
        if username:
            event["username"] = username
        if changes:
            event["changes"] = changes
        self.events.append(event)

    def diff_field(self, changes, field, old_val, new_val):
        if old_val != new_val:
            changes[field] = {"old": old_val, "new": new_val}

    # Update the redis stream / timeline topic that something has changed.
    def notify(self, kind, extra=None):
        notification = {
            "data": json.dumps(self.as_json()),
            "kind": kind,
            "type": "activity",
            "timeline": self.name,
        }
        if extra:
            for key, value in extra.items():
                notification[str(key)] = value
        try:
            TimelineTopic.write_activity(notification, scope=self.scope)
        except Exception as e:
            raise ActivityError(f"Failed to write to stream: {notification}, {e}") from e

    def as_json(self):
        return {
            "name": self.name,
            "updated_at": self.updated_at,
            "start": self.start,
            "stop": self.stop,
            "kind": self.kind,
            "data": self.data,
            "scope": self.scope,
            "fulfillment": self.fulfillment,
            "uuid": self.uuid,
            "events": self.events,
            "recurring": self.recurring,
        }
