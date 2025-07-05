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

require 'openc3/utilities/bucket'
module Aws
  autoload(:S3, 'openc3/utilities/s3_autoload.rb')
end

module OpenC3
  class AwsBucket < Bucket
    CREATE_CHECK_COUNT = 100 # 10 seconds

    def initialize
      super()
      @client = Aws::S3::Client.new
      @aws_arn = ENV['OPENC3_AWS_ARN_PREFIX'] || 'arn:aws'
    end

    def create(bucket)
      unless exist?(bucket)
        @client.create_bucket({ bucket: bucket })
        count = 0
        until exist?(bucket) or count > CREATE_CHECK_COUNT
          sleep(0.1)
          count += 1
        end
      end
      bucket
    end

    def ensure_public(bucket)
      unless ENV['OPENC3_NO_BUCKET_POLICY']
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
                "#{@aws_arn}:s3:::#{bucket}"
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
                "#{@aws_arn}:s3:::#{bucket}/*"
              ],
              "Sid": ""
            }
          ]
        }
        EOL
        @client.put_bucket_policy({ bucket: bucket, policy: policy, checksum_algorithm: "SHA256" })
      end
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

    def get_object(bucket:, key:, path: nil, range: nil)
      if path
        @client.get_object(bucket: bucket, key: key, response_target: path, range: range)
      else
        @client.get_object(bucket: bucket, key: key, range: range)
      end
    # If the key is not found return nil
    rescue Aws::S3::Errors::NoSuchKey
      nil
    end

    def list_objects(bucket:, prefix: nil, max_request: 1000, max_total: 100_000)
      token = nil
      result = []
      while true
        resp = @client.list_objects_v2({
          bucket: bucket,
          max_keys: max_request,
          prefix: prefix,
          continuation_token: token
        })
        result.concat(resp.contents)
        break if result.length >= max_total
        break unless resp.is_truncated
        token = resp.next_continuation_token
      end
      # Array of objects with key and size methods
      result
    rescue Aws::S3::Errors::NoSuchBucket
      raise NotFound, "Bucket '#{bucket}' does not exist."
    end

    # Lists the files under a specified path
    def list_files(bucket:, path:, only_directories: false, metadata: false)
      # Trailing slash is important in AWS S3 when listing files
      # See https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Types/ListObjectsV2Output.html#common_prefixes-instance_method
      if path[-1] != '/'
        path += '/'
      end
      # If we're searching for the root then kill the path or AWS will return nothing
      path = nil if path == '/'

      token = nil
      result = []
      dirs = []
      files = []
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
          dirs << item.prefix.split('/')[-1]
        end
        if only_directories
          result = dirs
        else
          resp.contents.each do |aws_item|
            item = {}
            item['name'] = aws_item.key.split('/')[-1]
            item['modified'] = aws_item.last_modified
            item['size'] = aws_item.size
            if metadata
              item['metadata'] = head_object(bucket: bucket, key: aws_item.key)
            end
            files << item
          end
          result = [dirs, files]
        end
        break unless resp.is_truncated
        token = resp.next_continuation_token
      end
      result
    rescue Aws::S3::Errors::NoSuchBucket
      raise NotFound, "Bucket '#{bucket}' does not exist."
    end

    # get metadata for a specific object
    def head_object(bucket:, key:)
      @client.head_object({
        bucket: bucket,
        key: key
      })
    rescue Aws::S3::Errors::NotFound
      raise NotFound, "Object '#{bucket}/#{key}' does not exist."
    end

    # put_object fires off the request to store but does not confirm
    def put_object(bucket:, key:, body:, content_type: nil, cache_control: nil, metadata: nil)
      @client.put_object(bucket: bucket, key: key, body: body,
        content_type: content_type, cache_control: cache_control, metadata: metadata,
        checksum_algorithm: "SHA256")
    end

    # @returns [Boolean] Whether the file exists
    def check_object(bucket:, key:, retries: true)
      if retries
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
        true
      else
        head_object(bucket: bucket, key: key)
      end
    rescue NotFound, Aws::Waiters::Errors::TooManyAttemptsError
      false
    end

    def delete_object(bucket:, key:)
      @client.delete_object(bucket: bucket, key: key)
    rescue Exception
      Logger.error("Error deleting object bucket: #{bucket}, key: #{key}")
    end

    def delete_objects(bucket:, keys:)
      @client.delete_objects(bucket: bucket, delete: { objects: keys.map {|key| { key: key } } })
    rescue Exception
      Logger.error("Error deleting objects bucket: #{bucket}, keys: #{keys}")
    end

    def presigned_request(bucket:, key:, method:, internal: true)
      s3_presigner = Aws::S3::Presigner.new

      if internal
        prefix = '/'
      else
        prefix = '/files/'
      end

      url, headers = s3_presigner.presigned_request(method, bucket: bucket, key: key)
      return {
        :url => prefix + url.split('/')[3..-1].join('/'),
        :headers => headers,
        :method => method.to_s.split('_')[0],
      }
    end
  end
end
