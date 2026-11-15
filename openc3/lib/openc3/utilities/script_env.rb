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

    # Secrets the script process needs, delivered over stdin instead of its
    # environment. Removing a variable from ENV does not change
    # /proc/<pid>/environ, which keeps the environment the process started with,
    # so anything passed in the environment stays readable by user code.
    # Maps the variable name in the script process to the variable it is read from
    # in the spawning process.
    STDIN_SECRET_VARS = {
      'OPENC3_REDIS_USERNAME' => 'OPENC3_SR_REDIS_USERNAME',
      'OPENC3_REDIS_PASSWORD' => 'OPENC3_SR_REDIS_PASSWORD',
      'OPENC3_BUCKET_USERNAME' => 'OPENC3_SR_BUCKET_USERNAME',
      'OPENC3_BUCKET_PASSWORD' => 'OPENC3_SR_BUCKET_PASSWORD',
    }.freeze

    # Removed from the environment of every spawned script process. The API
    # credentials and STDIN_SECRET_VARS are delivered over stdin instead.
    SPAWN_SCRUBBED_VARS = (UNUSED_VARS + [
      'SECRET_KEY_BASE',
      'OPENC3_SERVICE_PASSWORD',
      'OPENC3_API_PASSWORD',
      'OPENC3_API_TOKEN',
      # Scripts authenticate as the user who ran them, never as an API client
      'OPENC3_API_CLIENT_SECRET',
    ] + STDIN_SECRET_VARS.keys + STDIN_SECRET_VARS.values).freeze

    # Unset SPAWN_SCRUBBED_VARS in a ChildProcess environment (nil unsets the
    # variable rather than inheriting it from this process)
    def self.scrub_spawn_environment(environment)
      SPAWN_SCRUBBED_VARS.each { |key| environment[key] = nil }
    end

    # The STDIN_SECRET_VARS values to send to the script process, omitting unset ones
    def self.stdin_secrets
      STDIN_SECRET_VARS.each_with_object({}) do |(child_key, parent_key), secrets|
        value = ENV.fetch(parent_key, nil)
        secrets[child_key] = value if value
      end
    end

    # Called in the script process before any user code runs. This only removes
    # the variables from ENV, so secrets must not be passed in the environment
    # at spawn (see STDIN_SECRET_VARS).
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
