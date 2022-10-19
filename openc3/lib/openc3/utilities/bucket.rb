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

# Interface class implemented by each cloud provider: AWS, GCS, Azure
module OpenC3
  class Bucket
    def self.getClient
      raise 'OPENC3_CLOUD environment variable is required' unless ENV['OPENC3_CLOUD']
      # Base is AwsBucket which works with MINIO, Enterprise implements additional
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

    def exist?(bucket)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def delete(bucket)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def get_object(bucket:, key:, path: nil)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    # NOTE: We will need to explicitly define the params after we implement all the clouds
    def list_objects(params)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def list_directories(bucket:, path:)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    # NOTE: We will need to explicitly define the kwargs after we implement all the clouds
    def put_object(bucket:, key:, body:, **kwargs)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def check_object(bucket:, key:)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def delete_object(bucket:, key:)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    # NOTE: We will need to explicitly define the params after we implement all the clouds
    def delete_objects(params)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def presigned_request(bucket:, key:, method:, internal: true)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end
  end
end
