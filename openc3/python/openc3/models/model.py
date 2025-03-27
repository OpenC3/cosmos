# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
import time
from typing import Optional

from openc3.utilities.store import Store, EphemeralStore
from openc3.utilities.store_queued import StoreQueued, EphemeralStoreQueued


class Model:
    @classmethod
    def store(cls):
        return Store

    @classmethod
    def store_queued(cls):
        return StoreQueued

    # NOTE: The following three methods must be reimplemented by Model subclasses
    # without primary_key to support other class methods.

    @classmethod
    def get(cls, primary_key: str, name: str):
        """
        Return:
            (Dict[] | None) Hash of this model or nil if name not found under primary_key
        """
        json_data = cls.store().hget(primary_key, name)
        return json.loads(json_data) if json_data else None

    @classmethod
    def names(cls, primary_key: str):
        """
        Return:
            (List[str]) All the names stored under the primary key
        """
        keys = cls.store().hkeys(primary_key)
        keys.sort()
        return [key.decode() for key in keys]

    @classmethod
    def all(cls, primary_key: str):
        """
        Return:
             (List[Dict]) All the models (as Hash objects) stored under the primary key
        """
        base = cls.store().hgetall(primary_key)
        # decode the binary string keys to strings
        decoded = {k.decode(): v for (k, v) in base.items()}
        for key, value in decoded.items():
            decoded[key] = json.loads(value)
        return decoded

    # END NOTE

    @classmethod
    def set(cls, json_data: dict, scope: str, queued: bool = False):
        """Sets (updates) the redis hash of this model"""
        json_data["scope"] = scope
        cls(**json_data).create(force=True, queued=queued)

    @classmethod
    def from_json(cls, json_data: str | dict, scope: str):
        """
        Return:
            [Model] Model generated from the passed JSON
        """
        if isinstance(json_data, str):
            json_data = json.loads(json_data)
        if json_data is None:
            raise RuntimeError("json data is nil")
        json_data["scope"] = scope
        return cls(**json_data)

    @classmethod
    def get_model(cls, name: str, scope: str):
        """Calls self.get_model and then from_json to turn the Hash configuration into a Ruby Model object.
        Return:
            [Object|nil] Model object or nil if name not found under primary_key
        """
        json_data = cls.get(name, scope)
        return cls.from_json(json_data, scope) if json_data else None

    # NOTE: get_all_models not implemented as it is currently
    # unused by any python models

    # NOTE: find_all_by_plugin, handle_config not implemented as it is
    # only needed by plugin_model which is Ruby only

    def __init__(self, primary_key: str, **kw_args):
        """Store the primary key and keyword arguments"""
        self.primary_key: str = primary_key
        self.name: Optional[str] = kw_args.get("name")
        self.updated_at: Optional[float] = kw_args.get("updated_at")
        self.plugin: Optional[str] = kw_args.get("plugin")
        self.scope: Optional[str] = kw_args.get("scope")
        self.destroyed: bool = False

    def create(self, update=False, force=False, queued=False):
        """Update the Redis hash at primary_key and set the field "name"
        to the JSON generated via calling as_json
        """
        if not force:
            existing = self.store().hget(self.primary_key, self.name)
            if existing and not update:
                raise RuntimeError(f"{self.primary_key}:{self.name} already exists at create")
            if not existing and update:
                raise RuntimeError(f"{self.primary_key}:{self.name} doesn't exist at update")
        self.updated_at = time.time() * 1_000_000_000

        write_store = self.store_queued() if queued else self.store()
        write_store.hset(self.primary_key, self.name, json.dumps(self.as_json()))

    def update(self, force=False, queued=True):
        """Alias for create(update: true)"""
        self.create(update=True, force=force, queued=queued)

    def deploy(self, gem_path: str, variables: str):
        """Deploy the model into the OpenC3 system. Subclasses must implement this
        and typically create MicroserviceModels to implement.
        """
        raise NotImplementedError("must be implemented by subclass")

    def undeploy(self):
        """Undo the actions of deploy and remove the model from OpenC3.
        Subclasses must implement this as by default it is a noop.
        """
        pass

    def destroy(self):
        """Delete the model from the Store"""
        self.destroyed = True
        self.undeploy()
        self.store().hdel(self.primary_key, self.name)

    def as_json(self):
        """
        Return:
            (dict) JSON encoding of this model
        """
        return {
            "name": self.name,
            "updated_at": self.updated_at,
            "plugin": self.plugin,
            "scope": self.scope,
        }


class EphemeralModel(Model):
    @classmethod
    def store(cls):
        return EphemeralStore

    @classmethod
    def store_queued(cls):
        return EphemeralStoreQueued
