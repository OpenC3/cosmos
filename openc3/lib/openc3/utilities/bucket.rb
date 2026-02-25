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

ENV['OPENC3_CLOUD'] ||= 'local'

# Interface class implemented by each cloud provider: AWS, GCS, Azure
module OpenC3
  class Bucket
    # Raised when the underlying bucket does not exist
    class NotFound < RuntimeError
    end

    def self.getClient
      raise 'OPENC3_CLOUD environment variable is required' unless ENV['OPENC3_CLOUD']
      # Base is AwsBucket which works with S3-compatible storage (versitygw), Enterprise implements additional
      bucket_class = ENV['OPENC3_CLOUD'].capitalize + 'Bucket'
      klass = OpenC3.require_class('openc3/utilities/'+bucket_class.class_name_to_filename)
      klass.new
    end

    def initialize
      # Setup the client instance
    end

    def create(bucket)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def ensure_public(bucket)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    # Apply bucket policies for ScriptRunner user (only applicable for local mode)
    def ensure_scriptrunner_policy(config_bucket, logs_bucket)
      # No-op by default, implemented by AwsBucket for local mode
    end

    def exist?(bucket)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def delete(bucket)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def get_object(bucket:, key:, path: nil, range: nil)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def list_objects(bucket:, prefix: nil, max_request: nil, max_total: nil)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def list_files(bucket:, path:, only_directories: false, metadata: false)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def put_object(bucket:, key:, body:, content_type: nil, cache_control: nil, metadata: nil)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def check_object(bucket:, key:, retries: true)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def delete_object(bucket:, key:)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def delete_objects(bucket:, keys:)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def presigned_request(bucket:, key:, method:, internal: true)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end
  end
end
