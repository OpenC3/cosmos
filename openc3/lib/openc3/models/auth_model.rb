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
# All changes Copyright 2025, OpenC3, Inc.
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

    MIN_PASSWORD_LENGTH = 8

    def self.set?(key = PRIMARY_KEY)
      Store.exists(key) == 1
    end

    def self.verify(token)
      return true if verify_service_password(token)
      return verify_no_service(token)
    end

    def self.verify_service_password(password)
      # Handle a service password - Generally only used by ScriptRunner and CmdQueues
      # TODO: Replace this with temporary service tokens
      service_password = ENV['OPENC3_SERVICE_PASSWORD']
      return true if service_password and service_password == password

      return false
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

      return false
    end

    def self.verify_password(password)
      return false if password.nil? or password.empty?

      # Check Direct password
      @@token_cache = Store.get(PRIMARY_KEY)
      @@token_cache_time = Time.now
      return true if @@token_cache == hash(password)

      return false
    end

    def self.set(password, old_password, key = PRIMARY_KEY)
      raise "password must not be nil or empty" if password.nil? or password.empty?
      raise "password must be at least 8 characters" if password.length < MIN_PASSWORD_LENGTH

      if set?(key)
        raise "old_password must not be nil or empty" if old_password.nil? or old_password.empty?
        raise "old_password incorrect" unless verify_password(old_password)
      end
      Store.set(key, hash(password))
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

    def self.hash(plaintext)
      Digest::SHA2.hexdigest plaintext
    end
  end
end
