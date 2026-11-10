# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
import re
import threading
import time
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone

from openc3.utilities.logger import Logger
from openc3.utilities.store import Store


class SharedResourceModel:
    """A resource (typically expensive hardware) defined in multiple scopes but
    only active in one scope at a time. See shared_resource_model.rb for the
    full description of the record format and the switching handoff."""

    PRIMARY_KEY = "openc3_shared_resources"
    LOCK_KEY = "openc3_shared_resources__lock"
    LOCK_TIMEOUT_MS = 10_000
    LOCK_WAIT_SECONDS = 15.0
    CACHE_TIMEOUT = 1.0
    ACTIVE = "ACTIVE"
    RELEASING = "RELEASING"
    # Member types backed by a microservice process
    PROCESS_TYPES = ["INTERFACE", "ROUTER", "MICROSERVICE"]
    MEMBER_TYPES = PROCESS_TYPES + ["TARGET"]

    _cache = None
    _cache_time = None
    _cache_lock = threading.Lock()

    @classmethod
    def store(cls):
        """Shared resources span scopes so they are always stored on db_shard 0"""
        return Store.instance(db_shard=0)

    @classmethod
    def validate_name(cls, name) -> str:
        name = str(name).upper()
        if not re.fullmatch(r"[A-Z0-9_]+", name) or "__" in name:
            raise RuntimeError(
                f"Invalid shared resource name '{name}'. Must only contain letters, numbers, and single underscores."
            )
        return name

    @classmethod
    def get(cls, name) -> dict | None:
        data = cls.store().hget(cls.PRIMARY_KEY, str(name).upper())
        return json.loads(data) if data else None

    @classmethod
    def names(cls) -> list[str]:
        keys = [key.decode() if isinstance(key, bytes) else key for key in cls.store().hkeys(cls.PRIMARY_KEY)]
        keys.sort()
        return keys

    @classmethod
    def all(cls) -> dict:
        result = {}
        for name, data in cls.store().hgetall(cls.PRIMARY_KEY).items():
            if isinstance(name, bytes):
                name = name.decode()
            result[name] = json.loads(data)
        return result

    @classmethod
    def all_cached(cls) -> dict:
        """Like all but cached for CACHE_TIMEOUT seconds. Used on hot paths like cmd."""
        with cls._cache_lock:
            if cls._cache is None or cls._cache_time is None or (time.time() - cls._cache_time) > cls.CACHE_TIMEOUT:
                cls._cache = cls.all()
                cls._cache_time = time.time()
            return cls._cache

    @classmethod
    def clear_cache(cls):
        with cls._cache_lock:
            cls._cache = None
            cls._cache_time = None

    @classmethod
    def add_member(cls, name, scope: str, type: str, member_name: str, shard: int = 0) -> dict:
        """Add a member to a shared resource. The first member to create the
        resource claims ownership for its scope."""
        name = cls.validate_name(name)
        type = str(type).upper()
        if type not in cls.MEMBER_TYPES:
            raise RuntimeError(f"Invalid shared resource member type '{type}'")
        with cls._lock():
            record = cls.get(name)
            if not record:
                record = cls._new_record(name, owner=scope)
                Logger.info(f"Shared resource {name} created and is active in scope {scope}", scope=scope)
            members = record["members"].setdefault(scope, [])
            members[:] = [m for m in members if not (m["type"] == type and m["name"] == member_name)]
            member = {"type": type, "name": member_name}
            if type in cls.PROCESS_TYPES:
                member["shard"] = int(shard or 0)
            members.append(member)
            cls._save(record)
            return record

    @classmethod
    def remove_member(cls, name, scope: str, type: str, member_name: str) -> dict | None:
        """Remove a member. Ownership is kept even if the owning scope has no
        members left. The record is deleted once no scope has any members."""
        name = str(name).upper()
        type = str(type).upper()
        with cls._lock():
            record = cls.get(name)
            if not record:
                return None
            members = record["members"].get(scope)
            if members is not None:
                members[:] = [m for m in members if not (m["type"] == type and m["name"] == member_name)]
                if not members:
                    del record["members"][scope]
            if not record["members"] and not record.get("waiting"):
                cls.store().hdel(cls.PRIMARY_KEY, name)
                Logger.info(f"Shared resource {name} deleted because it has no members", scope=scope)
                return None
            # Can't switch to a scope that no longer has members
            if record.get("to") and record["to"] not in record["members"]:
                record["to"] = None
            cls._save(record)
            return record

    @classmethod
    def switch(cls, name, to_scope: str, force: bool = False) -> dict:
        """Switch the shared resource to be active in to_scope"""
        name = str(name).upper()
        with cls._lock():
            record = cls.get(name)
            if not record:
                raise RuntimeError(f"Shared resource '{name}' does not exist")
            if to_scope not in record["members"]:
                raise RuntimeError(f"Shared resource '{name}' has no members in scope '{to_scope}'")
            if record["state"] == cls.ACTIVE and record["owner"] == to_scope:
                return record
            cls._start_release(record, to_scope, force)
            cls._save(record)
            return record

    @classmethod
    def release(cls, name, force: bool = False) -> dict:
        """Release the shared resource so it is not active in any scope"""
        name = str(name).upper()
        with cls._lock():
            record = cls.get(name)
            if not record:
                raise RuntimeError(f"Shared resource '{name}' does not exist")
            if record["state"] == cls.ACTIVE and record["owner"] is None:
                return record
            cls._start_release(record, None, force)
            cls._save(record)
            return record

    @classmethod
    def acknowledge(cls, name, member_names: list[str]) -> dict | None:
        """Confirm waiting process members have stopped. Completes the handoff once none are waiting."""
        with cls._lock():
            record = cls.get(name)
            if not record or record["state"] != cls.RELEASING:
                return None
            record["waiting"] = [m for m in record.get("waiting") or [] if m["name"] not in member_names]
            if not record["waiting"]:
                if not record["members"]:
                    # Every member was uninstalled during the handoff
                    cls.store().hdel(cls.PRIMARY_KEY, record["name"])
                    return None
                to_scope = record.get("to")
                if to_scope and to_scope not in record["members"]:
                    to_scope = None
                cls._finish_release(record, to_scope)
            cls._save(record)
            return record

    @classmethod
    def active(cls, record: dict | None, scope: str) -> bool:
        """Whether members of the resource in scope may be active"""
        if not record:
            return False
        return record["state"] == cls.ACTIVE and record["owner"] == scope

    @classmethod
    def process_members(cls, record: dict, scope: str | None) -> list[dict]:
        if not scope:
            return []
        return [m for m in record["members"].get(scope, []) if m["type"] in cls.PROCESS_TYPES]

    @classmethod
    def find_by_member(cls, scope: str, type: str, member_name: str, cached: bool = True) -> dict | None:
        records = cls.all_cached() if cached else cls.all()
        for record in records.values():
            members = record["members"].get(scope)
            if not members:
                continue
            if any(m["type"] == type and m["name"] == member_name for m in members):
                return record
        return None

    @classmethod
    def check_active(cls, scope: str, type: str, member_name: str, description: str):
        """Raise if the member is part of a shared resource that isn't active in scope"""
        record = cls.find_by_member(scope=scope, type=type, member_name=member_name)
        if record is None or cls.active(record, scope):
            return
        raise RuntimeError(cls.inactive_message(record, description))

    @classmethod
    def check_target_active(cls, target_name: str, scope: str):
        """Raise if commands to the target can't be sent in scope"""
        target_name = str(target_name).upper()
        cls.check_active(scope=scope, type="TARGET", member_name=target_name, description=f"Target {target_name}")

    @classmethod
    def check_interface_active(cls, type: str, name: str, scope: str):
        """Raise if the interface or router isn't running in scope because of its shared resource"""
        name = str(name).upper()
        cls.check_active(
            scope=scope,
            type=type,
            member_name=f"{scope}__{type}__{name}",
            description=f"{type.capitalize()} {name}",
        )

    @classmethod
    def inactive_message(cls, record: dict, description: str) -> str:
        if record["state"] == cls.RELEASING:
            if record.get("to"):
                return (
                    f"{description} is part of shared resource {record['name']} which is switching "
                    f"from scope {record['owner']} to scope {record['to']}"
                )
            return f"{description} is part of shared resource {record['name']} which is being released from scope {record['owner']}"
        if record["owner"]:
            return (
                f"{description} is part of shared resource {record['name']} which is active in scope {record['owner']}"
            )
        return f"{description} is part of shared resource {record['name']} which is not active in any scope"

    # Private helpers

    @classmethod
    def _new_record(cls, name: str, owner: str | None) -> dict:
        return {
            "name": name,
            "owner": owner,
            "state": cls.ACTIVE,
            "to": None,
            "waiting": [],
            "members": {},
            "requested_at": None,
            "updated_at": None,
        }

    @classmethod
    def _now(cls) -> str:
        return datetime.now(timezone.utc).isoformat()

    @classmethod
    def _save(cls, record: dict):
        record["updated_at"] = cls._now()
        cls.store().hset(cls.PRIMARY_KEY, record["name"], json.dumps(record))

    @classmethod
    def _start_release(cls, record: dict, to_scope: str | None, force: bool):
        if record["state"] == cls.RELEASING:
            waiting = record.get("waiting") or []
            if not force:
                # Already handing off. Nothing new can start so just change the destination.
                record["to"] = to_scope
                Logger.info(
                    f"Shared resource {record['name']} releasing from scope {record['owner']} now to {to_scope or 'none'}"
                )
                return
        else:
            waiting = [
                {"name": m["name"], "shard": int(m.get("shard") or 0)}
                for m in cls.process_members(record, record["owner"])
            ]
        # Nothing to wait for if the owner has no process members
        if force or not waiting:
            if force and waiting:
                Logger.warn(
                    f"Shared resource {record['name']} forced from scope {record['owner']} to {to_scope or 'none'} "
                    "without waiting for its microservices to stop"
                )
            cls._finish_release(record, to_scope)
        else:
            record["state"] = cls.RELEASING
            record["to"] = to_scope
            record["waiting"] = waiting
            record["requested_at"] = cls._now()
            Logger.info(
                f"Shared resource {record['name']} releasing from scope {record['owner']} to {to_scope or 'none'}"
            )

    @classmethod
    def _finish_release(cls, record: dict, to_scope: str | None):
        previous = record["owner"]
        record["owner"] = to_scope
        record["state"] = cls.ACTIVE
        record["to"] = None
        record["waiting"] = []
        record["requested_at"] = None
        Logger.info(
            f"Shared resource {record['name']} switched from scope {previous or 'none'} to {to_scope or 'none'}"
        )

    @classmethod
    @contextmanager
    def _lock(cls):
        """Serialize read-modify-write of the records across processes"""
        token = str(uuid.uuid4())
        start = time.time()
        while not cls.store().set(cls.LOCK_KEY, token, nx=True, px=cls.LOCK_TIMEOUT_MS):
            if (time.time() - start) > cls.LOCK_WAIT_SECONDS:
                raise RuntimeError("Timeout waiting for shared resource lock")
            time.sleep(0.05)
        try:
            yield
        finally:
            current = cls.store().get(cls.LOCK_KEY)
            if isinstance(current, bytes):
                current = current.decode()
            if current == token:
                cls.store().delete(cls.LOCK_KEY)
            cls.clear_cache()
