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

import json

from openc3.environment import OPENC3_SCOPE
from openc3.models.db_sharded_model import DbShardedModel
from openc3.models.model import EphemeralModel
from openc3.utilities.store import Store


class MetricModel(DbShardedModel, EphemeralModel):
    PRIMARY_KEY = "__openc3__metric"
    # Process level metrics (cpu, memory) reported by the operator on behalf of
    # the microservices it spawned. These live in their own hash so that the
    # operator and the microservice are never two writers of one field - each
    # write replaces the whole values hash, so sharing a field would have them
    # clobbering each other every cycle. The two are merged back together on
    # read by get/names/all, so callers see a single row per microservice.
    PROCESS_PRIMARY_KEY = "__openc3__process_metric"
    METRIC_EXPIRE_SECONDS = 3600  # # Expire metrics after 1 hour

    _db_shard_cache = {}

    @classmethod
    def _lookup_db_shard(cls, name, scope):
        """Look up db_shard from the corresponding MicroserviceModel."""
        json_data = Store.hget("openc3_microservices", name)
        return int(json.loads(json_data).get("db_shard", 0) or 0) if json_data else 0

    @classmethod
    def _collect_db_shards(cls, scope):
        """Collect all unique db_shard values from MicroserviceModels."""
        db_shards = {0}
        for name, json_data in Store.hgetall("openc3_microservices").items():
            decoded_name = name.decode() if isinstance(name, bytes) else name
            if scope and decoded_name.split("__")[0] != scope:
                continue
            db_shards.add(int(json.loads(json_data).get("db_shard", 0) or 0))
        return db_shards

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name: str, scope: str):
        return cls._merge_entries(
            cls._db_sharded_get(f"{scope}{MetricModel.PRIMARY_KEY}", name, scope),
            cls._db_sharded_get(f"{scope}{MetricModel.PROCESS_PRIMARY_KEY}", name, scope),
        )

    @classmethod
    def names(cls, scope: str):
        names = cls._db_sharded_names(f"{scope}{MetricModel.PRIMARY_KEY}", scope)
        names.extend(cls._db_sharded_names(f"{scope}{MetricModel.PROCESS_PRIMARY_KEY}", scope))
        return sorted(set(names))

    @classmethod
    def all(cls, scope: str):
        result = cls._db_sharded_all(f"{scope}{MetricModel.PRIMARY_KEY}", scope)
        process_entries = cls._db_sharded_all(f"{scope}{MetricModel.PROCESS_PRIMARY_KEY}", scope)
        for name, process_entry in process_entries.items():
            result[name] = cls._merge_entries(result.get(name), process_entry)
        return result

    # Combine a microservice's self reported metrics with the process metrics
    # the operator reported for it. The microservice's own values win on a key
    # collision - a process that can measure itself knows better than the
    # operator watching from outside.
    @classmethod
    def _merge_entries(cls, entry, process_entry):
        if not process_entry:
            return entry
        if not entry:
            return process_entry
        values = dict(process_entry.get("values") or {})
        values.update(entry.get("values") or {})
        entry["values"] = values
        updated_at = [u for u in (entry.get("updated_at"), process_entry.get("updated_at")) if u is not None]
        if updated_at:
            entry["updated_at"] = max(updated_at)
        return entry

    # Sets (updates) the redis hash of this model
    @classmethod
    def set(cls, json_data: dict, scope: str = OPENC3_SCOPE, queued: bool = True):
        json_data["scope"] = scope
        cls(**json_data).create(force=True, queued=queued, expire_seconds=cls.METRIC_EXPIRE_SECONDS)

    # Sets (updates) the process metrics reported by the operator for a
    # microservice it spawned. See PROCESS_PRIMARY_KEY.
    @classmethod
    def set_process(cls, json_data: dict, scope: str = OPENC3_SCOPE, queued: bool = True):
        json_data["scope"] = scope
        json_data["primary_key"] = cls.PROCESS_PRIMARY_KEY
        cls(**json_data).create(force=True, queued=queued, expire_seconds=cls.METRIC_EXPIRE_SECONDS)

    @classmethod
    def destroy(cls, scope: str, name: str):
        db_shard = cls._db_shard_for_name(name, scope)
        cls.store().instance(db_shard=db_shard).hdel(f"{scope}{MetricModel.PRIMARY_KEY}", name)
        cls.store().instance(db_shard=db_shard).hdel(f"{scope}{MetricModel.PROCESS_PRIMARY_KEY}", name)

    def __init__(
        self,
        name: str,
        values: dict | None = None,
        db_shard: int = 0,
        scope: str = OPENC3_SCOPE,
        primary_key: str = PRIMARY_KEY,
    ):
        values = {} if values is None else values
        super().__init__(f"{scope}{primary_key}", name=name, scope=scope)
        self.values = values
        self.db_shard = db_shard if db_shard is not None else 0

    def create(self, update=False, force=False, queued=False, expire_seconds=None):
        self._db_sharded_create(self.db_shard, update=update, force=force, queued=queued, expire_seconds=expire_seconds)

    def as_json(self):
        return {"name": self.name, "updated_at": self.updated_at, "values": self.values, "db_shard": self.db_shard}
