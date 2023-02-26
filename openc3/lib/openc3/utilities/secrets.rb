# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

ENV['OPENC3_SECRET_BACKEND'] ||= 'redis'

module OpenC3
  class Secrets
    def initialize
      @local_secrets = {}
    end

    def self.getClient
      raise 'OPENC3_SECRET_BACKEND environment variable is required' unless ENV['OPENC3_SECRET_BACKEND']
      secrets_class = ENV['OPENC3_SECRET_BACKEND'].capitalize + 'Secrets'
      klass = OpenC3.require_class('openc3/utilities/' + secrets_class.class_name_to_filename)
      klass.new
    end

    def keys(secret_store: nil, scope:)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def get(key, secret_store: nil, scope:)
      return @local_secrets[key]
    end

    def set(key, value, secret_store: nil, scope:)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def delete(key, secret_store: nil, scope:)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def setup(secrets)
      secrets.each do |type, key, data, secret_store|
        case type
        when 'ENV'
          @local_secrets[key] = ENV[data]
        when 'FILE'
          @local_secrets[key] = File.read(data)
        else
          raise "Unknown secret type: #{type}"
        end
      end
    end
  end
end
