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
import time

from openc3.models.model import Model
from openc3.utilities.store import Store
from openc3.utilities.store_queued import StoreQueued


# Stores the status about an interface. This class also implements logic
# to handle status for a router since the functionality is identical
# (only difference is the Redis key used).
class InterfaceStatusModel(Model):
    INTERFACES_PRIMARY_KEY = "openc3_interface_status"
    ROUTERS_PRIMARY_KEY = "openc3_router_status"

    @classmethod
    def _shard_for_name(cls, name, scope):
        """Look up the target_shard from the corresponding base model (InterfaceModel or RouterModel).
        Base models are always stored on shard 0."""
        type_ = cls._get_type()
        if type_ == "INTERFACESTATUS":
            json_data = Store.hget(f"{scope}__openc3_interfaces", name)
        else:
            json_data = Store.hget(f"{scope}__openc3_routers", name)
        if not json_data:
            return 0
        parsed = json.loads(json_data)
        return int(parsed.get("target_shard", 0) or 0)

    @classmethod
    def _active_shards(cls, scope):
        """Collect all unique target_shard values from the corresponding base models."""
        shards = {0}
        type_ = cls._get_type()
        if type_ == "INTERFACESTATUS":
            base = Store.hgetall(f"{scope}__openc3_interfaces")
        else:
            base = Store.hgetall(f"{scope}__openc3_routers")
        for _name, json_data in base.items():
            parsed = json.loads(json_data)
            shards.add(int(parsed.get("target_shard", 0) or 0))
        return shards

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name: str, scope: str):
        shard = cls._shard_for_name(name, scope)
        json_data = Store.instance(shard=shard).hget(f"{scope}__{cls._get_key()}", name)
        return json.loads(json_data) if json_data else None

    @classmethod
    def names(cls, scope: str):
        result = []
        for shard in cls._active_shards(scope):
            keys = Store.instance(shard=shard).hkeys(f"{scope}__{cls._get_key()}")
            result.extend(key.decode() for key in keys)
        # Deduplicate (in case mock redis returns same data for all shards) and sort
        return sorted(set(result))

    @classmethod
    def all(cls, scope: str):
        result = {}
        for shard in cls._active_shards(scope):
            base = Store.instance(shard=shard).hgetall(f"{scope}__{cls._get_key()}")
            decoded = {k.decode(): v for (k, v) in base.items()}
            for key, value in decoded.items():
                result[key] = json.loads(value)
        return result

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
