# encoding: ascii-8bit

# Copyright 2024 OpenC3, Inc
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation; version 3 with attribution # addendums as found in the
# LICENSE.txt
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of # MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the # GNU Affero General Public
# License for more details.
#
# This file may also be used under the terms of a commercial license if
# purchased from OpenC3, Inc.

require 'aws-sdk-s3'

module LocalS3

  class S3Bucket < ::Aws::S3::Bucket
  end

  class S3Object < ::Aws::S3::Object
    attr_accessor :body
  end

  class ClientLocal

    attr_reader :object

    @fs_root = ''
    @identifier = :s3

    def initialize(fs_root: nil) # optional local filesystem directory for buckets
      @fs_root = (defined?(::Rails)) ? Rails.root.to_s : '.'
      if fs_root.nil?
        @fs_root = File.join(@fs_root, 'tmp', 'local-s3', Process.pid.to_s)
      else
        @fs_root = fs_root
      end
      FileUtils.mkdir_p(@fs_root)
    end

    def create_bucket(args)
      Dir.mkdir(File.expand_path(File.join(@fs_root, args[:bucket])))
      opts = {bucket_name: args[:bucket], key: ''}
      bucket = S3Bucket.new(args[:bucket], '', opts)
    end

    def check_object(args)
      File.open(File.expand_path(File.join(@fs_root, args[:bucket], args[:key])))
      puts File.expand_path(File.join(@fs_root, args[:bucket], args[:key]))
      true
    rescue Errno::ENOENT
      false
    end

    def delete_bucket(args)
      # Dir.rmdir(File.expand_path(File.join(@fs_root, args[:bucket])))
      FileUtils.rm_r(File.expand_path(File.join(@fs_root, args[:bucket])))
    end

    def delete_object(args)
      File.delete(File.expand_path(File.join(@fs_root, args[:bucket], args[:key])))
    end

    def get_bucket(bucket_name)
      if Dir.exist?(File.expand_path(File.join(@fs_root, bucket_name)))
        bucket = S3Bucket.new(bucket_name)
      end
      bucket
    end

    def get_object(bucket:, key:, response_target: nil)
      s3_obj = S3Object.new(bucket_name: bucket, key: key)
      data = File.open(File.expand_path(File.join(@fs_root, bucket, key))) do |file|
        file.read
      end
      s3_obj.body = StringIO.new(data)
      s3_obj
    rescue Errno::ENOENT
      nil
    end

    def head_object(args)
      s3_obj = S3Object.new(bucket_name: bucket, key: key)
      s3_obj = get_object(args[:bucket], args[:key])
      raise Aws::S3::Errors::NotFound.new(nil, nil) if s3_obj.nil?
      true
    rescue
      raise Aws::S3::Errors::NotFound.new(nil, nil)
    end

    def head_bucket(args)
      bucket = get_bucket(args[:bucket])
      raise Aws::S3::Errors::NotFound.new(nil, "no such bucket") if bucket.nil?
      bucket
    end

    def put_bucket_policy(*args)
      # no-op: this space intentionally left blank
    end

    # MEMO: raise ::Aws::S3::Errors::NoSuchKey.new(nil, nil) if s3_obj.nil?

    def put_object(bucket:, key:, body:, content_type:, cache_control:, metadata:, checksum_algorithm:)
      bucket_obj = get_bucket(bucket)
      if !bucket_obj
        # Lazily create a bucket.  TODO fix this to return the proper error
        bucket_obj = create_bucket(bucket)
      end
      # ignores args[:metadata] for now

      fullpath = File.expand_path(File.join(@fs_root, bucket, key))
      FileUtils.mkdir_p(File.dirname(fullpath))
      File.open(fullpath, 'wb') do |file|
        file.write(body)
      end
      #store_object(bucket_obj, args[:key])
    end

=begin
    def list_objects_v2(args)
     bucket = get_bucket(args[:bucket])
     raise Aws::S3::Errors::NoSuchBucket.new(nil, nil) if bucket.nil?
     cont_token = args[:continuation_token] # ???
     # TODO: bucket query goes here
     response = Struct.new(:contents, :is_truncated, :next_continuation_token, :common_prefixes)
     resp = response.new(bq.matches, bq.is_truncated, nil, cmn_pfxs)
     return resp
    end

    alias list_objects list_objects_v2

    def get_objects(args)
      # TODO:
    end

    def delete_objects(args)
      names = []
      args[:delete][:objects].each {|h| names<< h[:key]}
      bucket_obj = get_bucket(args[:bucket])
      #TODD delete_objects(bucket_obj, names)
    end
=end
    def wait_until(waiter, args, opts)
      max_attempts = opts[:max_attempts].to_i
      delay = opts[:delay].to_f
      case waiter
      when :object_exists
        max_attempts.downto(1) do
           if (check_object(args))
             return true
           end
          sleep(delay)
        end
        raise Aws::Waiters::Errors::TooManyAttemptsError.new(max_attempts)
      end
      false
    end
  end
end
