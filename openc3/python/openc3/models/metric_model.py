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
        return cls._db_sharded_get(f"{scope}{MetricModel.PRIMARY_KEY}", name, scope)

    @classmethod
    def names(cls, scope: str):
        return cls._db_sharded_names(f"{scope}{MetricModel.PRIMARY_KEY}", scope)

    @classmethod
    def all(cls, scope: str):
        return cls._db_sharded_all(f"{scope}{MetricModel.PRIMARY_KEY}", scope)

    # Sets (updates) the redis hash of this model
    @classmethod
    def set(cls, json_data: dict, scope: str = OPENC3_SCOPE, queued: bool = True):
        json_data["scope"] = scope
        cls(**json_data).create(force=True, queued=queued, expire_seconds=cls.METRIC_EXPIRE_SECONDS)

    @classmethod
    def destroy(cls, scope: str, name: str):
        db_shard = cls._db_shard_for_name(name, scope)
        cls.store().instance(db_shard=db_shard).hdel(f"{scope}{MetricModel.PRIMARY_KEY}", name)

    def __init__(self, name: str, values: dict = None, db_shard: int = 0, scope: str = OPENC3_SCOPE):
        values = {} if values is None else values
        super().__init__(f"{scope}{MetricModel.PRIMARY_KEY}", name=name, scope=scope)
        self.values = values
        self.db_shard = db_shard if db_shard is not None else 0

    def create(self, update=False, force=False, queued=False, isoformat=False, expire_seconds=None):
        self._db_sharded_create(self.db_shard, update=update, force=force, queued=queued, expire_seconds=expire_seconds)

    def as_json(self):
        return {"name": self.name, "updated_at": self.updated_at, "values": self.values, "db_shard": self.db_shard}
