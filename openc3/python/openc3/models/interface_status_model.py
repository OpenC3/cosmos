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

from openc3.models.model import Model
from openc3.models.sharded_model import ShardedModel
from openc3.utilities.store import Store


# Stores the status about an interface. This class also implements logic
# to handle status for a router since the functionality is identical
# (only difference is the Redis key used).
class InterfaceStatusModel(ShardedModel, Model):
    INTERFACES_PRIMARY_KEY = "openc3_interface_status"
    ROUTERS_PRIMARY_KEY = "openc3_router_status"

    _shard_cache = {}

    @classmethod
    def _lookup_db_shard(cls, name, scope):
        """Look up db_shard from the corresponding InterfaceModel or RouterModel."""
        type_ = cls._get_type()
        key = f"{scope}__openc3_interfaces" if type_ == "INTERFACESTATUS" else f"{scope}__openc3_routers"
        json_data = Store.hget(key, name)
        return int(json.loads(json_data).get("db_shard", 0) or 0) if json_data else 0

    @classmethod
    def _collect_db_shards(cls, scope):
        """Collect all unique db_shard values from InterfaceModels or RouterModels."""
        shards = {0}
        type_ = cls._get_type()
        key = f"{scope}__openc3_interfaces" if type_ == "INTERFACESTATUS" else f"{scope}__openc3_routers"
        for _name, json_data in Store.hgetall(key).items():
            shards.add(int(json.loads(json_data).get("db_shard", 0) or 0))
        return shards

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name: str, scope: str):
        return cls._sharded_get(f"{scope}__{cls._get_key()}", name, scope)

    @classmethod
    def names(cls, scope: str):
        return cls._sharded_names(f"{scope}__{cls._get_key()}", scope)

    @classmethod
    def all(cls, scope: str):
        return cls._sharded_all(f"{scope}__{cls._get_key()}", scope)

    # END NOTE

    # Helper method to return the correct type based on class name
    @classmethod
    def _get_type(cls):
        return cls.__name__.split("Model")[0].upper()

    # Helper method to return the correct primary key based on class name
    @classmethod
    def _get_key(cls):
        type_ = cls._get_type()
        match type_:
            case "INTERFACESTATUS":
                return InterfaceStatusModel.INTERFACES_PRIMARY_KEY
            case "ROUTERSTATUS":
                return InterfaceStatusModel.ROUTERS_PRIMARY_KEY
            case _:
                raise RuntimeError(f"Unknown type {type_} from class {cls.__name__}")

    def __init__(
        self,
        name,
        state,
        clients=0,
        txsize=0,
        rxsize=0,
        txbytes=0,
        rxbytes=0,
        txcnt=0,
        rxcnt=0,
        updated_at=None,
        plugin=None,
        scope=None,
    ):
        if self.__class__._get_type() == "INTERFACESTATUS":
            super().__init__(
                f"{scope}__{InterfaceStatusModel.INTERFACES_PRIMARY_KEY}",
                name=name,
                updated_at=updated_at,
                plugin=plugin,
                scope=scope,
            )
        else:
            super().__init__(
                f"{scope}__{InterfaceStatusModel.ROUTERS_PRIMARY_KEY}",
                name=name,
                updated_at=updated_at,
                plugin=plugin,
                scope=scope,
            )
        self.state = state
        self.clients = clients
        self.txsize = txsize
        self.rxsize = rxsize
        self.txbytes = txbytes
        self.rxbytes = rxbytes
        self.txcnt = txcnt
        self.rxcnt = rxcnt

    def create(self, update=False, force=False, queued=False, isoformat=False):
        self._sharded_create(self.__class__._shard_for_name(self.name, self.scope, use_cache=True), update=update, force=force, queued=queued)

    def destroy(self):
        self._sharded_destroy(self.__class__._shard_for_name(self.name, self.scope))

    def as_json(self):
        return {
            "name": self.name,
            "state": self.state,
            "clients": self.clients,
            "txsize": self.txsize,
            "rxsize": self.rxsize,
            "txbytes": self.txbytes,
            "rxbytes": self.rxbytes,
            "txcnt": self.txcnt,
            "rxcnt": self.rxcnt,
            "plugin": self.plugin,
            "updated_at": self.updated_at,
        }
