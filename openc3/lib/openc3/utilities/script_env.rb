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

require 'openc3/utilities/bucket'
OpenC3.require_file 'openc3/utilities/store'

module OpenC3
  # Environment handling for the child processes that execute user scripts
  # (script runs and suite analysis)
  module ScriptEnv
    # Not used by script processes so never passed to them
    UNUSED_VARS = [
      # This actually contains the password via redis://openc3:XXXXXXXX@openc3-redis:6379
      'ANYCABLE_REDIS_URL',
      'OPENC3_TSDB_USERNAME',
      'OPENC3_TSDB_PASSWORD',
      'KC_DB_USERNAME',
      'KC_DB_PASSWORD',
      'KEYCLOAK_ADMIN',
      'KEYCLOAK_ADMIN_PASSWORD',
    ]
    # Cleared by script processes once they have connected
    CLEARED_VARS = [
      'OPENC3_BUCKET_USERNAME',
      'OPENC3_BUCKET_PASSWORD',
      'OPENC3_REDIS_USERNAME',
      'OPENC3_REDIS_PASSWORD',
      'OPENC3_API_PASSWORD',
      'OPENC3_SERVICE_PASSWORD',
    ] + UNUSED_VARS

    # Remove UNUSED_VARS from a ChildProcess environment (nil unsets the variable)
    def self.remove_unused(environment)
      UNUSED_VARS.each { |key| environment[key] = nil }
    end

    # Called in the script process before any user code runs
    def self.clear_credentials
      # Load the bucket client code to ensure we authenticate outside ENV vars
      Bucket.getClient()
      # Preload Store and remove Redis secrets from ENV
      Store.instance
      EphemeralStore.instance
      CLEARED_VARS.each { |key| ENV.delete(key) }
    end
  end
end
