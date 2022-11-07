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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved

require 'openc3/utilities/bucket'
require 'openc3/models/reducer_model'
require 'zlib'

module OpenC3
  class BucketUtilities
    def self.list_files_before_time(bucket, prefix, time)
      client = Bucket.getClient
      oldest_list = []

      # Return nothing if bucket doesn't exist (it won't at the very beginning)
      unless client.exist?(bucket)
        return oldest_list
      end

      next_folder = false
      resp = client.list_objects(bucket: bucket, prefix: prefix)
      resp.each do |item|
        t = File.basename(item.key).split('__')[1]
        file_end_time = Time.utc(t[0..3], t[4..5], t[6..7], t[8..9], t[10..11], t[12..13])
        if file_end_time < time
          oldest_list << item.key
        else
          break
        end
      end
      return oldest_list
    end

    def self.move_log_file_to_bucket(filename, bucket_key, metadata: {})
      Thread.new do
        client = Bucket.getClient

        zipped = compress_file(filename)
        bucket_key = bucket_key + '.gz'
        File.open(zipped, 'rb') do |read_file|
          client.put_object(bucket: ENV['OPENC3_LOGS_BUCKET'], key: bucket_key, body: read_file, metadata: metadata)
        end
        Logger.debug "wrote #{ENV['OPENC3_LOGS_BUCKET']}/#{bucket_key}"
        ReducerModel.add_file(bucket_key) # Record the new file for data reduction

        File.delete(zipped)
        File.delete(filename)
      rescue => err
        Logger.error("Error saving log file to bucket: #{filename}\n#{err.formatted}")
      end
    end

    def self.get_cache_control(filename)
      # Allow caching for files that have a filename versioning strategy
      has_version_number = /(-|_|\.)\d+(-|_|\.)\d+(-|_|\.)\d+\./.match(filename)
      has_content_hash = /\.[a-f0-9]{20}\./.match(filename)
      return nil if has_version_number or has_content_hash
      return 'no-cache'
    end

    def self.compress_file(filename, chunk_size = 50_000_000)
      zipped = "#{filename}.gz"

      Zlib::GzipWriter.open(zipped) do |gz|
        gz.mtime = File.mtime(filename)
        gz.orig_name = filename
        File.open(filename, 'rb') do |file|
          while chunk = file.read(chunk_size) do
            gz.write(chunk)
          end
        end
      end

      return zipped
    end

    def self.uncompress_file(filename, chunk_size = 50_000_000)
      unzipped = filename[0..-4] # Drop .gz

      Zlib::GzipReader.open(filename) do |gz|
        File.open(unzipped, 'wb') do |file|
          while chunk = gz.read(chunk_size)
            file.write(chunk)
          end
        end
      end

      return unzipped
    end
  end
end
