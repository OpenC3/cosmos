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

from openc3.environment import OPENC3_SCOPE
from openc3.models.model import Model
from openc3.models.db_sharded_model import DbShardedModel
from openc3.utilities.store import Store


class MicroserviceStatusModel(DbShardedModel, Model):
    PRIMARY_KEY = "openc3_microservice_status"

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
    def get(cls, name: str, scope: str = OPENC3_SCOPE):
        return cls._db_sharded_get(f"{scope}__{MicroserviceStatusModel.PRIMARY_KEY}", name, scope)

    @classmethod
    def names(cls, scope: str = OPENC3_SCOPE):
        return cls._db_sharded_names(f"{scope}__{MicroserviceStatusModel.PRIMARY_KEY}", scope)

    @classmethod
    def all(cls, scope: str = OPENC3_SCOPE):
        return cls._db_sharded_all(f"{scope}__{MicroserviceStatusModel.PRIMARY_KEY}", scope)

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
        self._db_sharded_create(self.__class__._db_shard_for_name(self.name, self.scope, use_cache=True), update=update, force=force, queued=queued)

    def destroy(self):
        self._db_sharded_destroy(self.__class__._db_shard_for_name(self.name, self.scope))

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
