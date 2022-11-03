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

require 'fileutils'
require 'tmpdir'
require 'openc3'
require 'openc3/utilities/bucket_utilities'
require 'openc3/utilities/bucket'

class BucketFile
  attr_reader :bucket_path
  attr_reader :local_path
  attr_reader :reservation_count
  attr_reader :size
  attr_reader :error
  attr_reader :topic_prefix
  attr_accessor :priority

  def initialize(bucket_path, client = nil)
    @bucket = client
    unless @bucket
      @bucket = OpenC3::Bucket.getClient()
    end
    @bucket_path = bucket_path
    @local_path = nil
    @reservation_count = 0
    @size = 0
    @priority = 0
    @error = nil
    @mutex = Mutex.new
    path_split = @bucket_path.split("/")
    scope = path_split[0].to_s.upcase
    stream_mode = path_split[1].to_s.split("_")[0].to_s.upcase
    cmd_or_tlm = path_split[2].to_s.upcase
    target_name = path_split[3].to_s.upcase
    if stream_mode == 'RAW'
      type = (@cmd_or_tlm == 'CMD') ? 'COMMAND' : 'TELEMETRY'
    else
      if stream_mode == 'DECOM'
        type = (@cmd_or_tlm == 'CMD') ? 'DECOMCMD' : 'DECOM'
      else
        type = stream_mode # REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
      end
    end
    @topic_prefix = "#{scope}__#{type}__{#{target_name}}"
  end

  def retrieve(client = @bucket)
    @mutex.synchronize do
      local_path = "#{BucketFileCache.instance.cache_dir}/#{File.basename(@bucket_path)}"
      unless File.exist?(local_path)
        OpenC3::Logger.debug "Retrieving #{@bucket_path} from logs bucket"
        client.get_object(bucket: "logs", key: @bucket_path, path: local_path)
        if File.exist?(local_path)
          @size = File.size(local_path)
          @local_path = local_path
          return true
        end
      end
      return false
    end
  rescue => err
    @error = err
    OpenC3::Logger.error "Failed to retrieve #{@bucket_path}\n#{err.formatted}"
    raise err
  end

  def reserve
    @reservation_count += 1
    return retrieve()
  end

  def unreserve
    @reservation_count -= 1
    delete() if @reservation_count <= 0
    return @reservation_count
  end

  # private

  def delete
    if @local_path and File.exist?(@local_path)
      File.delete(@local_path)
      @local_path = nil
    end
  end
end

class BucketFileCache
  MAX_DISK_USAGE = (ENV['OPENC3_BUCKET_FILE_CACHE_SIZE'] || 20_000_000_000).to_i # Default 20 GB

  attr_reader :cache_dir

  @@instance = nil
  @@mutex = Mutex.new

  def self.instance
    return @@instance if @@instance
    @@mutex.synchronize do
      @@instance ||= BucketFileCache.new
    end
    @@instance
  end

  def initialize
    @bucket = OpenC3::Bucket.getClient()

    # Create local file cache location
    @cache_dir = Dir.mktmpdir
    FileUtils.mkdir_p(@cache_dir)
    at_exit do
      FileUtils.remove_dir(@cache_dir, true)
    end

    @current_disk_usage = 0
    @queued_bucket_files = []
    @bucket_file_hash = {}

    @thread = Thread.new do
      client = OpenC3::Bucket.getClient()
      while true
        if @current_disk_usage < MAX_DISK_USAGE
          @@mutex.synchronize do
            bucket_file = @queued_bucket_files.shift
          end
          begin
            retrieved = bucket_file.retrieve(client)
            @@mutex.synchronize do
              @current_disk_usage += bucket_file.size if retrieved
            end
          rescue
            # Might have been deleted
          end
          sleep(0.01) # Small throttle
        else
          # Nothing to do
          sleep(1)
        end
      end
    rescue => err
      OpenC3::Logger.error "BucketFileCache thread unexpectedly died\n#{err.formatted}"
    end
  end

  def self.hint(bucket_paths)
    return instance().hint(bucket_paths)
  end

  def self.reserve(bucket_path)
    return instance().reserve(bucket_path)
  end

  def self.unreserve(bucket_path)
    return instance().unreserve(bucket_path)
  end

  def hint(bucket_paths)
    @@mutex.synchronize do
      bucket_paths.each_with_index do |bucket_path, index|
        bucket_file = create_bucket_file(bucket_path)
        bucket_file.priority = index
      end
      @queued_bucket_files.sort! {|file1, file2| file1.priority <=> file2.priority}
    end
  end

  def reserve(bucket_path)
    @@mutex.synchronize do
      bucket_file = create_bucket_file(bucket_path)
      retrieved = bucket_file.reserve
      @current_disk_usage += bucket_file.size if retrieved
      @queued_bucket_files.delete(bucket_file)
      return bucket_file
    end
  end

  def unreserve(bucket_path)
    @@mutex.synchronize do
      bucket_file = @bucket_file_hash[bucket_path]
      if bucket_file
        bucket_file.unreserve
        if bucket_file.reservation_count <= 0 and !@queued_bucket_files.include?(bucket_file)
          @current_disk_usage -= bucket_file.size
          @bucket_file_hash.delete(bucket_file)
        end
      end
    end
  end

  # Private

  def create_bucket_file(bucket_path)
    bucket_file = @bucket_file_hash[bucket_path]
    unless bucket_file
      bucket_file = BucketFile.new(bucket_path)
      @queued_bucket_files << bucket_file
      @bucket_file_hash[bucket_path] = bucket_file
    end
    return bucket_file
  end

end
