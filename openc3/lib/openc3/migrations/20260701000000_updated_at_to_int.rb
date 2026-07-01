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

require 'time'
require 'openc3/utilities/migration'
require 'openc3/core_ext/time'
require 'openc3/models/scope_model'
require 'openc3/models/script_status_model'

module OpenC3
  # Earlier versions of the Python script runner wrote the ScriptStatusModel
  # updated_at field as an ISO8601 string (e.g. "2026-06-30T12:34:56.789012Z")
  # instead of integer nanoseconds since the epoch. This migration rewrites any
  # such string values as integers so updated_at is consistently an int.
  #
  # NOTE: The stored JSON is edited in place rather than reloaded through the
  # model and re-created, because ScriptStatusModel#create always sets
  # updated_at to the current time, which would discard the original timestamp.
  class UpdatedAtToInt < Migration
    def self.run
      ScopeModel.names.each do |scope|
        [ScriptStatusModel::RUNNING_PRIMARY_KEY, ScriptStatusModel::COMPLETED_PRIMARY_KEY].each do |key|
          primary_key = "#{key}__#{scope}"
          Store.hgetall(primary_key).each do |name, json|
            data = JSON.parse(json, allow_nan: true)
            updated_at = data['updated_at']
            next unless updated_at.is_a?(String)

            begin
              data['updated_at'] = Time.parse(updated_at).to_nsec_from_epoch
            rescue ArgumentError
              # Leave unparseable values untouched
              next
            end
            Store.hset(primary_key, name, JSON.generate(data, allow_nan: true))
          end
        end
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::UpdatedAtToInt.run
end
