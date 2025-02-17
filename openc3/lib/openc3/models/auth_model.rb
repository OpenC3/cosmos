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

require 'digest'
require 'securerandom'
require 'openc3/utilities/store'

module OpenC3
  class AuthModel
    PRIMARY_KEY = 'OPENC3__TOKEN'
    SESSIONS_KEY = 'OPENC3__SESSIONS'

    TOKEN_CACHE_TIMEOUT = 5
    SESSION_CACHE_TIMEOUT = 5
    @@token_cache = nil
    @@token_cache_time = nil
    @@session_cache = nil
    @@session_cache_time = nil

    MIN_TOKEN_LENGTH = 8

    def self.set?(key = PRIMARY_KEY)
      Store.exists(key) == 1
    end

    def self.verify(token)
      # Handle a service password - Generally only used by ScriptRunner
      # TODO: Replace this with temporary service tokens
      service_password = ENV['OPENC3_SERVICE_PASSWORD']
      return true if service_password and service_password == token

      return verify_no_service(token)
    end

    def self.verify_no_service(token)
      return false if token.nil? or token.empty?

      time = Time.now
      return true if @@session_cache and (time - @@session_cache_time) < SESSION_CACHE_TIMEOUT and @@session_cache[token]
      token_hash = hash(token)
      return true if @@token_cache and (time - @@token_cache_time) < TOKEN_CACHE_TIMEOUT and @@token_cache == token_hash

      # Check sessions
      @@session_cache = Store.hgetall(SESSIONS_KEY)
      @@session_cache_time = time
      return true if @@session_cache[token]

      # Check Direct password
      @@token_cache = Store.get(PRIMARY_KEY)
      @@token_cache_time = time
      return true if @@token_cache == token_hash

      return false
    end

    def self.set(token, old_token, key = PRIMARY_KEY)
      raise "token must not be nil or empty" if token.nil? or token.empty?
      raise "token must be at least 8 characters" if token.length < MIN_TOKEN_LENGTH

      if set?(key)
        raise "old_token must not be nil or empty" if old_token.nil? or old_token.empty?
        raise "old_token incorrect" unless verify(old_token)
      end
      Store.set(key, hash(token))
    end

    def self.generate_session
      token = SecureRandom.urlsafe_base64(nil, false)
      Store.hset(SESSIONS_KEY, token, Time.now.iso8601)
      return token
    end

    def self.logout
      Store.del(SESSIONS_KEY)
      @@sessions_cache = nil
      @@sessions_cache_time = nil
    end

    def self.hash(token)
      Digest::SHA2.hexdigest token
    end
  end
end
