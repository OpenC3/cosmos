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

require 'openc3/utilities/bucket'
module Aws
  autoload(:S3, 'openc3/utilities/s3_autoload.rb')
end

module OpenC3
  class AwsBucket < Bucket
    def initialize
      @client = Aws::S3::Client.new
    end

    def create(bucket)
      unless exist?(bucket)
        @client.create_bucket({ bucket: bucket })
        policy = <<~EOL
          {
            "Version": "2012-10-17",
            "Statement": [
              {
                "Action": [
                  "s3:GetBucketLocation",
                  "s3:ListBucket"
                ],
                "Effect": "Allow",
                "Principal": {
                  "AWS": [
                    "*"
                  ]
                },
                "Resource": [
                  "arn:aws:s3:::#{bucket}"
                ],
                "Sid": ""
              },
              {
                "Action": [
                  "s3:GetObject"
                ],
                "Effect": "Allow",
                "Principal": {
                  "AWS": [
                    "*"
                  ]
                },
                "Resource": [
                  "arn:aws:s3:::#{bucket}/*"
                ],
                "Sid": ""
              }
            ]
          }
        EOL
        # @client.put_bucket_policy({ bucket: bucket, policy: policy })
      end
      bucket
    end

    def exist?(bucket)
      @client.head_bucket({ bucket: bucket })
      true
    rescue Aws::S3::Errors::NotFound
      false
    end

    def delete(bucket)
      if exist?(bucket)
        @client.delete_bucket({ bucket: bucket })
      end
    end

    def get_object(bucket:, key:, path: nil)
      if path
        @client.get_object(bucket: bucket, key: key, response_target: path)
      else
        @client.get_object(bucket: bucket, key: key)
      end
    end

    # TODO: Explicitly call out prefix and delimiter here?
    # Need to see how the other cloud providers implement this
    def list_objects(params)
      unless params[:max_keys]
        params[:max_keys] = 1000
      end
      token = nil
      result = []
      while true
        resp = @client.list_objects_v2(params)
        result.concat(resp.contents)
        break unless resp.is_truncated
        token = resp.next_continuation_token
      end
      result
    end

    # Lists the directories under a specified path
    def list_directories(bucket:, path:)
      # Trailing slash is important in AWS S3 when listing files
      # See https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Types/ListObjectsV2Output.html#common_prefixes-instance_method
      if path[-1] != '/'
        path += '/'
      end
      token = nil
      result = []
      while true
        resp = @client.list_objects_v2({
          bucket: bucket,
          max_keys: 1000,
          prefix: path,
          delimiter: '/',
          continuation_token: token
        })
        resp.common_prefixes.each do |item|
          # If path was DEFAULT/targets_modified/ then the
          # results look like DEFAULT/targets_modified/INST/
          result << item.prefix.split('/')[-1]
        end
        break unless resp.is_truncated
        token = resp.next_continuation_token
      end
      result
    end

    # TODO: tool_model, widget_model calls this with additional kwargs
    # Check that this is compatible in other implementations
    # put_object fires off the request to store but does not confirm
    def put_object(bucket:, key:, body:, **kwargs)
      @client.put_object(bucket: bucket, key: key, body: body, **kwargs)
    end

    # TODO: target_file calls this with additional kwargs
    # Check that this is compatible in other implementations
    # put_object fires off the request to store and verifies the object exists
    def put_and_check_object(bucket:, key:, body:, **kwargs)
      put_object(bucket: bucket, key: key, body: body, **kwargs)
      # polls in a loop, sleeping between attempts
      @client.wait_until(:object_exists,
        {
          bucket: bucket,
          key: key
        },
        {
          max_attempts: 30,
          delay: 0.1, # seconds
        }
      )
    end

    def delete_object(bucket:, key:)
      @client.delete_object(bucket: bucket, key: key)
    end

    # TODO: Need to see how the other cloud providers implement this
    def delete_objects(params)
      @client.delete_objects(params)
    end
  end
end
