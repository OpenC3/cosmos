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
require 'openc3/utilities/logger'
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

    # Variables users may not set through the global Environment or the
    # per-script environment. Global entries apply to every user's scripts, so
    # these are the names that would let one user run code in, or redirect the
    # credentials of, another user's script process. Keep this list to names
    # that matter: script code can already read its own credentials, and an
    # overly broad list (e.g. a RUBY or PYTHON prefix) breaks ordinary user
    # variables. Matched case-insensitively.
    RESERVED_PREFIXES = %w[
      OPENC3_
      LD_
      BUNDLE
      AWS_
    ].freeze
    RESERVED_NAMES = %w[
      PATH HOME
      RUBYOPT RUBYLIB RUBYGEMS_GEMDEPS GEM_HOME GEM_PATH
      PYTHONPATH PYTHONHOME PYTHONUSERBASE PYTHONSTARTUP PYTHONWARNINGS
      PYTHONBREAKPOINT PYTHONINSPECT PYTHONPYCACHEPREFIX VIRTUAL_ENV
      GCONV_PATH OPENSSL_CONF OPENSSL_MODULES OPENSSL_ENGINES
      BASH_ENV ENV IFS
      HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY
      HOSTALIASES LOCALDOMAIN RES_OPTIONS
      SSL_CERT_FILE SSL_CERT_DIR REQUESTS_CA_BUNDLE CURL_CA_BUNDLE
    ].freeze
    # Reserved-prefix names that only change script output, not how the
    # script connects or loads code. Script Runner sends OPENC3_FULL_BACKTRACE
    # when "Enable Stack Traces" is checked.
    ALLOWED_NAMES = %w[OPENC3_FULL_BACKTRACE].freeze
    VALID_NAME = /\A[A-Za-z_][A-Za-z0-9_]*\z/

    # Returns an error message if key can't be set by users, nil if it can
    def self.key_error(key)
      return "Environment variable name must be a String" unless key.is_a?(String)
      unless VALID_NAME.match?(key)
        return "Environment variable name '#{key}' must contain only letters, digits and underscores and not start with a digit"
      end

      upcased = key.upcase
      return nil if ALLOWED_NAMES.include?(upcased)
      if RESERVED_NAMES.include?(upcased) or RESERVED_PREFIXES.any? { |prefix| upcased.start_with?(prefix) }
        return "Environment variable '#{key}' is reserved by COSMOS and can not be set for scripts"
      end

      return nil
    end

    def self.allowed_key?(key)
      return key_error(key).nil?
    end

    # Copy user environment entries ([{ 'key' => , 'value' => }, ...]) into a
    # ChildProcess environment, skipping reserved names. Returns the hash of
    # entries applied.
    def self.apply_user_entries(environment, entries, source:, scope: nil)
      applied = {}
      (entries || []).each do |entry|
        key = entry.respond_to?(:key?) ? entry['key'] : nil
        error = key_error(key)
        if error
          Logger.warn("Ignoring #{source} environment variable: #{error}", scope: scope)
          next
        end
        # nil unsets the variable in the ChildProcess environment
        value = entry['value']
        value = value.to_s unless value.nil?
        environment[key] = value
        applied[key] = value
      end
      return applied
    end

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
