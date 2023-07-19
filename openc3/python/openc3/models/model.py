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

# require 'openc3/config/config_parser'

# attr_accessor :name
# attr_accessor :updated_at
# attr_accessor :plugin
# attr_accessor :scope


class Model:
    # NOTE: The following three methods must be reimplemented by Model subclasses
    # without primary_key to support other class methods.

    @classmethod
    def get(primary_key, name):
        """@return [Hash|nil] Hash of this model or nil if name not found under primary_key"""
        json_data = Store.hget(primary_key, name)
        if json_data:
            return json.loads(json)
        else:
            return None

    @classmethod
    def names(primary_key):
        """@return [Array<String>] All the names stored under the primary key"""
        Store.hkeys(primary_key).sort()

    @classmethod
    def all(primary_key):
        """@return [Array<Hash>] All the models (as Hash objects) stored under the primary key"""
        hash = Store.hgetall(primary_key)
        for key, value in hash.items():
            hash[key] = json.loads(value)
        return hash

    # END NOTE

    #     # Loops over all items and returns objects that match a key value pair
    #     def self.filter(key, value, scope:, substr: false)
    #       filtered = {}
    #       results = all(scope: scope)
    #       results.each do |name, result|
    #         if result[key] == value || (substr && result[key].include?(value))
    #           filtered[name] = result
    #         end
    #       end
    #       return filtered
    #     end

    #     # Sets (updates) the redis hash of this model
    #     def self.set(json, scope:)
    #       json[:scope] = scope
    #       json.transform_keys!(&:to_sym)
    #       self.new(**json).create(force: true)
    #     end

    #     # @return [Model] Model generated from the passed JSON
    #     def self.from_json(json, scope:)
    #       json = JSON.parse(json, :allow_nan => true, :create_additions => true) if String === json
    #       raise "json data is nil" if json.nil?
    #       json[:scope] = scope
    #       self.new(**json.transform_keys(&:to_sym), scope: scope)
    #     end

    #     # Calls self.get and then from_json to turn the Hash configuration into a Ruby Model object.
    #     # @return [Object|nil] Model object or nil if name not found under primary_key
    #     def self.get_model(name:, scope:)
    #       json = get(name: name, scope: scope)
    #       if json
    #         return from_json(json, scope: scope)
    #       else
    #         return nil
    #       end
    #     end

    #     # @return [Array<Object>] All the models (as Model objects) stored under the primary key
    #     def self.get_all_models(scope:)
    #       models = {}
    #       all(scope: scope).each { |name, json| models[name] = from_json(json, scope: scope) }
    #       models
    #     end

    #     # @return [Array<Object>] All the models (as Model objects) stored under the primary key
    #     #   which have the plugin attribute
    #     def self.find_all_by_plugin(plugin:, scope:)
    #       result = {}
    #       models = get_all_models(scope: scope)
    #       models.each do |name, model|
    #         result[name] = model if model.plugin == plugin
    #       end
    #       result
    #     end

    #     def self.handle_config(parser, keyword, parameters)
    #       raise "must be implemented by subclass"
    #     end

    # Store the primary key and keyword arguments
    def __init__(self, primary_key, **kw_args):
        self.primary_key = primary_key
        self.name = kw_args["name"]
        self.updated_at = kw_args["updated_at"]
        self.plugin = kw_args["plugin"]
        self.scope = kw_args["scope"]
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

    #     # Alias for create(update: true)
    #     def update
    #       create(update: true)
    #     end

    #     # Deploy the model into the OpenC3 system. Subclasses must implement this
    #     # and typically create MicroserviceModels to implement.
    #     def deploy(gem_path, variables)
    #       raise "must be implemented by subclass"
    #     end

    #     # Undo the actions of deploy and remove the model from OpenC3.
    #     # Subclasses must implement this as by default it is a noop.
    #     def undeploy
    #     end

    #     # Delete the model from the Store
    #     def destroy
    #       self.destroyed = true
    #       undeploy()
    #       self.class.store.hdel(self.primary_key, self.name)
    #     end

    #     # Indicate if destroy has been called
    #     def destroyed?
    #       self.destroyed
    #     end

    # @return [Hash] JSON encoding of this model
    def as_json(self):
        return {
            "name": self.name,
            "updated_at": self.updated_at,
            "plugin": self.plugin,
            "scope": self.scope,
        }
