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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/utilities/bucket'
require 'openc3/models/reducer_model'
require 'zlib'

module OpenC3
  class BucketUtilities
    FILE_TIMESTAMP_FORMAT = "%Y%m%d%H%M%S%N"
    DIRECTORY_TIMESTAMP_FORMAT = "%Y%m%d"

    # @param bucket [String] Name of the bucket to list
    # @param prefix [String] Prefix to filter all files by
    # @param start_time [Time|nil] Ruby time to find files after. nil means no start (first file on).
    # @param end_time [Time|nil] Ruby time to find files before. nil means no end (up to last file).
    # @param overlap [Boolean] Whether to include files which overlap the start and end time
    # @param max_request [Integer] How many files to request in each API call
    # @param max_total [Integer] Total number of files before stopping API requests
    def self.files_between_time(bucket, prefix, start_time, end_time, file_suffix: nil,
                                overlap: false, max_request: 1000, max_total: 100_000)
      client = Bucket.getClient()
      oldest_list = []

      # Return nothing if bucket doesn't exist (it won't at the very beginning)
      unless client.exist?(bucket)
        return oldest_list
      end

      directories = client.list_files(bucket: bucket, path: prefix, only_directories: true)
      filtered_directories = filter_directories_to_time_range(directories, start_time, end_time)
      filtered_directories.each do |directory|
        directory_files = client.list_objects(bucket: bucket, prefix: "#{prefix}/#{directory}", max_request: max_request, max_total: max_total)
        files = filter_files_to_time_range(directory_files, start_time, end_time, file_suffix: file_suffix, overlap: overlap)
        oldest_list.concat(files)
      end
      return oldest_list
    end

    def self.move_log_file_to_bucket(filename, bucket_key, metadata: {})
      Thread.new do
        client = Bucket.getClient()

        zipped = filename
        file_mode = 'r'
        if File.extname(filename) != '.txt'
          zipped = compress_file(filename)
          bucket_key += '.gz'
          file_mode += 'b' # binary
        end
        # We want to open this as a file and pass that to put_object to allow
        # this to work with really large files. Otherwise the entire file has
        # to be held in memory!
        File.open(zipped, file_mode) do |file|
          client.put_object(bucket: ENV['OPENC3_LOGS_BUCKET'], key: bucket_key, body: file, metadata: metadata)
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
      return 'no-store'
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

    # Private methods

    def self.filter_directories_to_time_range(directories, start_time, end_time)
      result = []
      directories.each do |directory|
        result << directory if directory_in_time_range(directory, start_time, end_time)
      end
      return result
    end

    def self.directory_in_time_range(directory, start_time, end_time)
      basename = File.basename(directory)
      directory_start_time = DateTime.strptime(basename, DIRECTORY_TIMESTAMP_FORMAT).to_time
      directory_end_time = directory_start_time + Time::SEC_PER_DAY
      if (not start_time or start_time < directory_end_time) and (not end_time or end_time >= directory_start_time)
        return true
      else
        return false
      end
    end

    def self.filter_files_to_time_range(files, start_time, end_time, file_suffix: nil, overlap: false)
      result = []
      files.each do |file|
        file_key = file.key.to_s
        next if file_suffix and not file_key.end_with?(file_suffix)
        if file_in_time_range(file_key, start_time, end_time, overlap: overlap)
          result << file_key
        end
      end
      return result
    end

    def self.file_in_time_range(bucket_path, start_time, end_time, overlap:)
      file_start_time, file_end_time = get_file_times(bucket_path)
      if overlap
        if (not start_time or start_time <= file_end_time) and (not end_time or end_time >= file_start_time)
          return true
        end
      else
        if (not start_time or start_time <= file_start_time) and (not end_time or end_time >= file_end_time)
          return true
        end
      end
      return false
    end

    def self.get_file_times(bucket_path)
      basename = File.basename(bucket_path)
      file_start_timestamp, file_end_timestamp, _ = basename.split("__")
      file_start_time = DateTime.strptime(file_start_timestamp, FILE_TIMESTAMP_FORMAT).to_time
      file_end_time = DateTime.strptime(file_end_timestamp, FILE_TIMESTAMP_FORMAT).to_time
      return file_start_time, file_end_time
    end
  end
end
