# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'argon2'
require 'securerandom'
require 'openc3/utilities/store'

module OpenC3
  class AuthModel
    ARGON2_PROFILE = :rfc_9106_high_memory # More secure than default (:rfc_9106_low_memory)

    # Redis keys
    PRIMARY_KEY = 'OPENC3__TOKEN' # for argon2 password hash
    SESSIONS_KEY = 'OPENC3__SESSIONS' # for hash containing session tokens

    # The length of time in minutes to keep redis values in memory
    PW_HASH_CACHE_TIMEOUT = 5
    SESSION_CACHE_TIMEOUT = 5

    # Cached argon2 password hash
    @@pw_hash_cache = nil
    @@pw_hash_cache_time = nil

    # Cached session tokens
    @@session_cache = nil
    @@session_cache_time = nil

    MIN_PASSWORD_LENGTH = 8

    def self.set?(key = PRIMARY_KEY)
      Store.exists(key) == 1
    end

    # Checks whether the provided token is a valid user password, service password, or session token.
    # @param token [String] the plaintext password or session token to check (required)
    # @param no_password [Boolean] enforces use of a session token or service password (default: true)
    # @param service_only [Boolean] enforces use of a service password (default: false)
    # @return [Boolean] whether the provided password/token is valid
    def self.verify(token, no_password: true, service_only: false)
      # Handle a service password - Generally only used by ScriptRunner
      # TODO: Replace this with temporary service tokens
      service_password = ENV['OPENC3_SERVICE_PASSWORD']
      return true if service_password and service_password == token

      return false if service_only

      return verify_no_service(token, no_password: no_password)
    end

    # Checks whether the provided token is a valid user password or session token.
    # @param token [String] the plaintext password or session token to check (required)
    # @param no_password [Boolean] enforces use of a session token (default: true)
    # @return [Boolean] whether the provided password/token is valid
    def self.verify_no_service(token, no_password: true)
      return false if token.nil? or token.empty?

      # Check cached session tokens and password hash
      time = Time.now
      return true if @@session_cache and (time - @@session_cache_time) < SESSION_CACHE_TIMEOUT and @@session_cache[token]
      unless no_password
        return true if @@pw_hash_cache and (time - @@pw_hash_cache_time) < PW_HASH_CACHE_TIMEOUT and Argon2::Password.verify_password(token, @@pw_hash_cache)
      end

      # Check stored session tokens
      @@session_cache = Store.hgetall(SESSIONS_KEY)
      @@session_cache_time = time
      return true if @@session_cache[token]

      return false if no_password

      # Check stored password hash
      pw_hash = Store.get(PRIMARY_KEY)
      raise "invalid password hash" unless pw_hash.start_with?("$argon2") # Catch users who didn't run the migration utility when upgrading to COSMOS 7
      @@pw_hash_cache = pw_hash
      @@pw_hash_cache_time = time
      return Argon2::Password.verify_password(token, @@pw_hash_cache)
    end

    def self.set(password, old_password, key = PRIMARY_KEY)
      raise "password must not be nil or empty" if password.nil? or password.empty?
      raise "password must be at least 8 characters" if password.length < MIN_PASSWORD_LENGTH

      if set?(key)
        raise "old_password must not be nil or empty" if old_password.nil? or old_password.empty?
        raise "old_password incorrect" unless verify_no_service(old_password, no_password: false)
      end
      pw_hash = Argon2::Password.create(password, profile: ARGON2_PROFILE)
      Store.set(key, pw_hash)
      @@pw_hash_cache = nil
      @@pw_hash_cache_time = nil
    end

    # Creates a new session token. DO NOT CALL BEFORE VERIFYING.
    def self.generate_session
      token = SecureRandom.urlsafe_base64(nil, false)
      Store.hset(SESSIONS_KEY, token, Time.now.iso8601)
      return token
    end

    # Terminates every session.
    def self.logout
      Store.del(SESSIONS_KEY)
      @@session_cache = nil
      @@session_cache_time = nil
    end
  end
end
