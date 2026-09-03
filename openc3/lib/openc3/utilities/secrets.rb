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

ENV['OPENC3_SECRET_BACKEND'] ||= 'redis'

module OpenC3
  class Secrets
    # Default base directory that FILE type secret paths must reside under.
    # FILE type secrets are written by the operator (or mounted by Kubernetes)
    # and then read back by the microservice, so the path is a destination we
    # control, not an arbitrary file on the host.
    DEFAULT_SECRET_FILE_DIR = '/tmp'

    def initialize
      @local_secrets = {}
    end

    # Base directory that FILE type secret paths must reside under
    def self.secret_file_dir
      dir = ENV['OPENC3_SECRET_FILE_DIR']
      dir = DEFAULT_SECRET_FILE_DIR if dir.nil? or dir.empty?
      dir
    end

    # Validates a FILE type secret path. The path must expand to a location
    # strictly inside Secrets.secret_file_dir. This prevents a plugin
    # configuration such as 'SECRET FILE KEY /root/.ssh/id_rsa' or
    # 'SECRET FILE KEY /tmp/../etc/shadow' from reading or overwriting arbitrary
    # files as the OpenC3 process user.
    #
    # @param path [String] Path from a SECRET FILE definition
    # @return [String] The validated absolute path
    def self.validate_file_path(path)
      raise ArgumentError, "Secret file path must be a String but is a #{path.class}" unless path.is_a?(String)
      raise ArgumentError, "Secret file path must not be blank" if path.strip.empty?
      raise ArgumentError, "Secret file path must not contain a null byte" if path.include?("\x00")

      # expand_path collapses '..' and '.', expands '~', and makes a relative path
      # absolute, so the comparison below can't be walked out of. This is
      # deliberately a purely lexical check: it does not touch the filesystem, so
      # a path validates identically at plugin install time (cmd-tlm-api) and at
      # write time (openc3-operator), which are separate containers. Symlinks are
      # rejected by the operator when it writes the secret.
      base = File.expand_path(secret_file_dir)
      absolute = File.expand_path(path)
      unless absolute.start_with?(base + File::SEPARATOR)
        raise ArgumentError, "Secret file path '#{path}' must be under '#{base}'"
      end
      absolute
    end

    # @return true if path is inside base, or is base itself
    def self.path_contained?(base, path)
      path == base or path.start_with?(base.end_with?(File::SEPARATOR) ? base : base + File::SEPARATOR)
    end

    def self.getClient
      raise 'OPENC3_SECRET_BACKEND environment variable is required' unless ENV['OPENC3_SECRET_BACKEND']
      secrets_class = ENV.fetch('OPENC3_SECRET_BACKEND').capitalize + 'Secrets'
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
      secrets.each do |secret|
        if secret.length < 3
          raise ArgumentError, "Secret must have at least 3 items (type, key, data), got #{secret.length}"
        end
        type, key, data, _secret_store = secret
        case type
        when 'ENV'
          @local_secrets[key] = ENV.fetch(data, nil)
        when 'FILE'
          @local_secrets[key] = File.read(Secrets.validate_file_path(data))
        else
          raise "Unknown secret type: #{type}"
        end
      end
    end
  end
end
