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
from openc3.models.model import EphemeralModel
from openc3.models.sharded_model import ShardedModel
from openc3.utilities.store import Store

class MetricModel(ShardedModel, EphemeralModel):
    PRIMARY_KEY = "__openc3__metric"

    _shard_cache = {}

    @classmethod
    def _lookup_target_shard(cls, name, scope):
        """Look up target_shard from the corresponding MicroserviceModel."""
        json_data = Store.hget("openc3_microservices", name)
        return int(json.loads(json_data).get("target_shard", 0) or 0) if json_data else 0

    @classmethod
    def _collect_target_shards(cls, scope):
        """Collect all unique target_shard values from MicroserviceModels."""
        shards = {0}
        for name, json_data in Store.hgetall("openc3_microservices").items():
            decoded_name = name.decode() if isinstance(name, bytes) else name
            if scope and decoded_name.split("__")[0] != scope:
                continue
            shards.add(int(json.loads(json_data).get("target_shard", 0) or 0))
        return shards

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name: str, scope: str):
        return cls._sharded_get(f"{scope}{MetricModel.PRIMARY_KEY}", name, scope)

    @classmethod
    def names(cls, scope: str):
        return cls._sharded_names(f"{scope}{MetricModel.PRIMARY_KEY}", scope)

    @classmethod
    def all(cls, scope: str):
        return cls._sharded_all(f"{scope}{MetricModel.PRIMARY_KEY}", scope)

    # Sets (updates) the redis hash of this model
    @classmethod
    def set(cls, json_data: dict, scope: str = OPENC3_SCOPE, queued: bool = True):
        json_data["scope"] = scope
        cls(**json_data).create(force=True, queued=queued)

    @classmethod
    def destroy(cls, scope: str, name: str):
        shard = cls._shard_for_name(name, scope)
        cls.store().instance(shard=shard).hdel(f"{scope}{MetricModel.PRIMARY_KEY}", name)

    def __init__(self, name: str, values: dict = None, target_shard: int = 0, scope: str = OPENC3_SCOPE):
        values = {} if values is None else values
        super().__init__(f"{scope}{MetricModel.PRIMARY_KEY}", name=name, scope=scope)
        self.values = values
        self.target_shard = target_shard if target_shard is not None else 0

    def create(self, update=False, force=False, queued=False, isoformat=False):
        self._sharded_create(self.target_shard, update=update, force=force, queued=queued)

    def as_json(self):
        return {"name": self.name, "updated_at": self.updated_at, "values": self.values}
