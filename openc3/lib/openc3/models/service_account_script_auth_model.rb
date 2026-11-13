# encoding: ascii-8bit

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

require 'openc3/models/model'

module OpenC3
  # Stores the durable child-script authentication metadata for one
  # service-account principal within a scope.
  #
  # The record keeps only the machine-auth lookup details needed to mint a new
  # client_credentials token during child-script launch. The secret value stays
  # in the configured secret backend and is referenced here by name.
  class ServiceAccountScriptAuthModel < Model
    PRIMARY_KEY = 'openc3__service_account_script_auth'

    attr_accessor :auth_kind
    attr_accessor :client_id
    attr_accessor :client_secret_name
    attr_accessor :secret_store

    def self.get(name:, scope:)
      super("#{scope}__#{PRIMARY_KEY}", name: name)
    end

    def self.names(scope:)
      super("#{scope}__#{PRIMARY_KEY}")
    end

    def self.all(scope:)
      super("#{scope}__#{PRIMARY_KEY}")
    end

    def initialize(name:, auth_kind: nil, client_id: nil, client_secret_name: nil, secret_store: nil, updated_at: nil, scope: 'DEFAULT')
      super("#{scope}__#{PRIMARY_KEY}", name: name, updated_at: updated_at, scope: scope)
      @auth_kind = auth_kind
      @client_id = client_id
      @client_secret_name = client_secret_name
      @secret_store = secret_store
    end

    def as_json(*_args)
      {
        'name' => @name,
        'updated_at' => @updated_at,
        'auth_kind' => @auth_kind,
        'client_id' => @client_id,
        'client_secret_name' => @client_secret_name,
        'secret_store' => @secret_store,
        'scope' => @scope,
      }
    end
  end
end
