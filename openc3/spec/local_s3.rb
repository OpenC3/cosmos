# encoding: ascii-8bit

# Copyright 2024 OpenC3, Inc All Rights Reserved.
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
    attr_accessor :name
    attr_accessor :size
    attr_accessor :last_modified
  end

  class ClientLocal

    attr_reader :object

    @fs_root = ''
    @identifier = :s3

    def initialize(fs_root: nil) # optional local filesystem directory for buckets
      @fs_root = (defined?(::Rails)) ? Rails.root.to_s : '.'
      if fs_root.nil?
        @fs_root = File.join(@fs_root, 'tmp', 'local-s3')
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

    def delete_bucket(args)
      FileUtils.rm_r(File.expand_path(File.join(@fs_root, args[:bucket])))
    end

    def delete_object(args)
      response = Struct.new(:delete_marker, :version_id, :request_charged)
      resp = response.new(true, '1', 'requester')
      File.delete(File.expand_path(File.join(@fs_root, args[:bucket], args[:key])))
    rescue Errno::ENOENT
      resp.delete_marker = false
    ensure
      return resp
    end

    def delete_objects(args)
      args[:delete][:objects].each do |h|
        delete_object({bucket: args[:bucket], key: h[:key]})
      end
    end

    def get_bucket(bucket_name)
      if Dir.exist?(File.expand_path(File.join(@fs_root, bucket_name)))
        bucket = S3Bucket.new(bucket_name)
      end
      bucket
    end

    def get_object(bucket:, key:, response_target: nil, range: nil)
      s3_obj = S3Object.new(bucket_name: bucket, key: key)
      data = File.open(File.expand_path(File.join(@fs_root, bucket, key))) do |file|
        file.read
      end
      s3_obj.body = StringIO.new(data)
      s3_obj
    rescue Errno::ENOENT
      nil
    end

    def head_bucket(args)
      bucket = get_bucket(args[:bucket])
      raise Aws::S3::Errors::NotFound.new(nil, "no such bucket") if bucket.nil?
      bucket
    end

    ## returns true/raises only NotFound
    #
    def head_object(args)
      File.open(File.expand_path(File.join(@fs_root, args[:bucket], args[:key])))

      # h_obj = Aws::S3::Types::HeadObjectOutput.new()
      true
    rescue Exception => e
       raise Aws::S3::Errors::NotFound.new(nil, "not found")
    end

    def list_objects(args)
      resp = list_objects_v2(args)
      resp.contents
    end

    def list_objects_v2(args)
      bucket = get_bucket(args[:bucket])
      raise Aws::S3::Errors::NoSuchBucket.new(nil, nil) if bucket.nil?
      count = 0
      max = args[:max_keys].to_i
      max = 1000 unless (max.between?(1, 1000))
      is_truncated = false
      con_token = next_token = args[:continuation_token] # ???
      prefix = args[:prefix]
      cmn_pfxs = {}
      contents = []

      # Bucket::list_objects seems only called without a delimiter present and with prefix set to nil
      glob = "**/*"       # files in directories recursively
      prefix ||= ''
      if (args[:delimiter])
        glob = "*"        # just one directory, so most likely root
      end

      bucket_prefix = File.join(bucket.name, prefix)
      pfx_pattern = "\\S*\/#{bucket_prefix}(\\S*)" # get only between prefix and final directory
      oky_pattern = "\\S*#{args[:bucket]}\/(\\S*)" # get only prefix thru filename
      fullpath = File.expand_path(File.join(@fs_root, bucket_prefix))
      filenames = Dir.glob(File.join(fullpath, glob)).sort
      if (con_token)
        filenames = filenames.select {|fname| !(fname.nil?) && fname >= con_token}
      end

      filenames.each do |fname|
        b_name = File.basename(fname)
        next if b_name == '.' || b_name == '..'

        if (File.directory?(fname))
          if (match = fname.match(pfx_pattern))
            dir = match.captures[0]
            cmn_pfxs[dir] = 1
          end
        else
          if (count > max)
            next_token = fname
            is_truncated = true
            break
          else
            count += 1
            obj_key = (match = fname.match(oky_pattern)) ? obj_key = match.captures[0] : ""
            s3_obj = S3Object.new(bucket_name: args[:bucket], key: obj_key)
            s3_obj.last_modified = File.mtime(fname)
            s3_obj.size = File.size(fname)
            contents << s3_obj
          end
        end
      end

      common_prefixes =  cmn_pfxs.keys.sort.map do |cpfx|
        pfx = Aws::S3::Types::CommonPrefix.new()
        pfx.prefix = cpfx
        pfx
      end
      response = Struct.new(:contents, :is_truncated, :next_continuation_token, :common_prefixes)
      resp = response.new(contents, is_truncated, next_token, common_prefixes)
      return resp
    end

    def put_bucket_policy(*args)
      # no-op: this space intentionally left blank
    end

    def put_object(bucket:, key:, body:, content_type:, cache_control:, metadata:, checksum_algorithm:)
      bucket_obj = get_bucket(bucket)
      if !bucket_obj
        # Lazily create a bucket.  Make this return the proper error.
        bucket_obj = create_bucket(bucket)
      end
      # ignores args[:metadata] for now

      fullpath = File.expand_path(File.join(@fs_root, bucket, key))
      FileUtils.mkdir_p(File.dirname(fullpath))
      File.open(fullpath, 'wb') do |file|
        file.write(body)
      end
    end

    def wait_until(waiter, args, opts)
      max_attempts = opts[:max_attempts].to_i
      delay = opts[:delay].to_f
      case waiter
      when :object_exists
        max_attempts.downto(1) do
          if (obj_file_exists?(args))
            return true
          end
          sleep(delay)
        end
        raise Aws::Waiters::Errors::TooManyAttemptsError.new(max_attempts)
      else
        false
      end
      false
    end

    private

    ## returns yes/no
    #
    def obj_file_exists?(args)
      File.open(File.expand_path(File.join(@fs_root, args[:bucket], args[:key])))
      true
    rescue Errno::ENOENT
      false
    rescue Exception => e
      puts e.message
    end

  end

end
