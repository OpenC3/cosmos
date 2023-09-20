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
from openc3.utilities.store import Store


class Model:
    # NOTE: The following three methods must be reimplemented by Model subclasses
    # without primary_key to support other class methods.

    @classmethod
    def get(cls, primary_key, name):
        """@return [Hash|nil] Hash of this model or nil if name not found under primary_key"""
        json_data = Store.hget(primary_key, name)
        if json_data:
            return json.loads(json_data)
        else:
            return None

    @classmethod
    def names(cls, primary_key):
        """@return [Array<String>] All the names stored under the primary key"""
        keys = Store.hkeys(primary_key)
        keys.sort()
        return keys

    @classmethod
    def all(cls, primary_key):
        """@return [Array<Hash>] All the models (as Hash objects) stored under the primary key"""
        hash = Store.hgetall(primary_key)
        for key, value in hash.items():
            hash[key] = json.loads(value)
        return hash

    # END NOTE

    # Sets (updates) the redis hash of this model
    @classmethod
    def set(cls, json, scope):
        json["scope"] = scope
        cls(**json).create(force=True)

    # @return [Model] Model generated from the passed JSON
    @classmethod
    def from_json(cls, json_data, scope):
        if type(json_data) == str:
            json_data = json.loads(json_data)
        if json_data is None:
            raise RuntimeError("json data is nil")
        json_data["scope"] = scope
        return cls(**json_data)

    # Calls self.get and then from_json to turn the Hash configuration into a Ruby Model object.
    # @return [Object|nil] Model object or nil if name not found under primary_key
    @classmethod
    def get_model(cls, name, scope):
        json = cls.get(name, scope)
        if json:
            return cls.from_json(json, scope)
        else:
            return None

    # NOTE: get_all_models not implemented as it is currently
    # unused by any python models

    # NOTE: find_all_by_plugin not implemented as it is
    # only needed by plugin_model which is Ruby only

    # @classmethod
    # def handle_config(cls, parser, keyword, parameters):
    #     raise RuntimeError("must be implemented by subclass")

    # Store the primary key and keyword arguments
    def __init__(self, primary_key, **kw_args):
        self.primary_key = primary_key
        self.name = kw_args.get("name")
        self.updated_at = kw_args.get("updated_at")
        self.plugin = kw_args.get("plugin")
        self.scope = kw_args.get("scope")
        self.destroyed = False

    # Update the Redis hash at primary_key and set the field "name"
    # to the JSON generated via calling as_json
    def create(self, update=False, force=False):
        if not force:
            existing = Store.hget(self.primary_key, self.name)
            if existing and not update:
                raise RuntimeError(
                    f"{self.primary_key}:{self.name} already exists at create"
                )
            if not existing and update:
                raise RuntimeError(
                    f"{self.primary_key}:{self.name} doesn't exist at update"
                )
        self.updated_at = time.time() * 1_000_000_000
        Store.hset(self.primary_key, self.name, json.dumps(self.as_json()))

    # Alias for create(update: true)
    def update(self):
        self.create(update=True)

    # Deploy the model into the OpenC3 system. Subclasses must implement this
    # and typically create MicroserviceModels to implement.
    def deploy(self, gem_path, variables):
        raise RuntimeError("must be implemented by subclass")

    # Undo the actions of deploy and remove the model from OpenC3.
    # Subclasses must implement this as by default it is a noop.
    def undeploy(self):
        pass

    # Delete the model from the Store
    def destroy(self):
        self.destroyed = True
        self.undeploy()
        Store.hdel(self.primary_key, self.name)

    # @return [Hash] JSON encoding of this model
    def as_json(self):
        return {
            "name": self.name,
            "updated_at": self.updated_at,
            "plugin": self.plugin,
            "scope": self.scope,
        }
