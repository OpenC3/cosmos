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
import time

from openc3.environment import OPENC3_SCOPE
from openc3.models.model import Model
from openc3.utilities.store import Store
from openc3.utilities.store_queued import StoreQueued


class MicroserviceStatusModel(Model):
    PRIMARY_KEY = "openc3_microservice_status"

    @classmethod
    def _shard_for_name(cls, name, scope):
        """Look up the target_shard from the corresponding MicroserviceModel.
        MicroserviceModel data is always stored on shard 0 under a global primary key."""
        json_data = Store.hget("openc3_microservices", name)
        if not json_data:
            return 0
        parsed = json.loads(json_data)
        return int(parsed.get("target_shard", 0) or 0)

    @classmethod
    def _active_shards(cls, scope):
        """Collect all unique target_shard values from MicroserviceModels for the given scope."""
        shards = {0}
        base = Store.hgetall("openc3_microservices")
        for name, json_data in base.items():
            decoded_name = name.decode() if isinstance(name, bytes) else name
            if scope and decoded_name.split("__")[0] != scope:
                continue
            parsed = json.loads(json_data)
            shards.add(int(parsed.get("target_shard", 0) or 0))
        return shards

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name: str, scope: str = OPENC3_SCOPE):
        shard = cls._shard_for_name(name, scope)
        json_data = Store.instance(shard=shard).hget(f"{scope}__{MicroserviceStatusModel.PRIMARY_KEY}", name)
        return json.loads(json_data) if json_data else None

    @classmethod
    def names(cls, scope: str = OPENC3_SCOPE):
        result = []
        for shard in cls._active_shards(scope):
            keys = Store.instance(shard=shard).hkeys(f"{scope}__{MicroserviceStatusModel.PRIMARY_KEY}")
            result.extend(key.decode() for key in keys)
        # Deduplicate and sort
        return sorted(set(result))

    @classmethod
    def all(cls, scope: str = OPENC3_SCOPE):
        result = {}
        for shard in cls._active_shards(scope):
            base = Store.instance(shard=shard).hgetall(f"{scope}__{MicroserviceStatusModel.PRIMARY_KEY}")
            decoded = {k.decode(): v for (k, v) in base.items()}
            for key, value in decoded.items():
                result[key] = json.loads(value)
        return result

    def __init__(
        self,
        name,
        state=None,
        count=0,
        error=None,
        custom=None,
        updated_at=None,
        plugin=None,
        scope=None,
    ):
        super().__init__(
            f"{scope}__{MicroserviceStatusModel.PRIMARY_KEY}",
            name=name,
            updated_at=updated_at,
            plugin=plugin,
            scope=scope,
        )
        self.state = state
        self.count = count
        self.error = error
        self.custom = custom

    def create(self, update=False, force=False, queued=False, isoformat=False):
        """Override create to write to the correct shard"""
        shard = self.__class__._shard_for_name(self.name, self.scope)
        shard_store = Store.instance(shard=shard)
        if not force:
            existing = shard_store.hget(self.primary_key, self.name)
            if existing and not update:
                raise RuntimeError(f"{self.primary_key}:{self.name} already exists at create")
            if not existing and update:
                raise RuntimeError(f"{self.primary_key}:{self.name} doesn't exist at update")
        self.updated_at = time.time() * 1_000_000_000

        if queued:
            StoreQueued.instance(shard=shard).hset(self.primary_key, self.name, json.dumps(self.as_json()))
        else:
            shard_store.hset(self.primary_key, self.name, json.dumps(self.as_json()))

    def destroy(self):
        """Override destroy to delete from the correct shard"""
        self.destroyed = True
        shard = self.__class__._shard_for_name(self.name, self.scope)
        Store.instance(shard=shard).hdel(self.primary_key, self.name)

    def as_json(self):
        json_data = {
            "name": self.name,
            "state": self.state,
            "count": self.count,
            "plugin": self.plugin,
            "updated_at": self.updated_at,
        }
        if self.error is not None:
            json_data["error"] = repr(self.error)
        if self.custom is not None:
            json_data["custom"] = self.custom.as_json()
        return json_data
