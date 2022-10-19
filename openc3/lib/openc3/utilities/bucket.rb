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

    %w(create exist? get_object put_object list_objects check_object delete_object presigned_request).each do |method_name|
      define_method(method_name) do |params|
        raise NotImplementedError, "#{self.class} has not implemented method '#{method_name}'"
      end
    end
  end
end
