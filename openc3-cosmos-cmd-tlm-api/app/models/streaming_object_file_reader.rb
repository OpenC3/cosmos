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

require_relative 'streaming_object_collection'
require 'openc3/logs/buffered_packet_log_reader'

class StreamingObjectFileReader
  FILE_TIMESTAMP_FORMAT = "%Y%m%d%H%M%S%N"
  DIRECTORY_TIMESTAMP_FORMAT = "%Y%m%d"

  def initialize(collection, scope:)
    @scope = scope
    @bucket = OpenC3::Bucket.getClient()
    @collection = collection
    targets_and_types, start_time, end_time, packets_by_target = collection.target_info
    @historical_file_list = {}
    build_file_list(targets_and_types, start_time, end_time, include_earlier_start: true)
    BucketFileCache.hint(@file_list)
    @open_readers = []
    @start_time = start_time
    @end_time = end_time
    @current_time = start_time
  end

  def each
    while true
      packet, topic = read()
      if packet and topic
        time = packet.packet_time
        next if time < @start_time
        # If we reach the end_time that means we found all the packets we asked for
        # This can be used by callers to know they are done reading
        return true if @end_time and time > @end_time
        yield packet, topic
      else
        break
      end
    end
    return false
  end

  def read
    open_current_files()
    return next_packet_and_topic()
  end

  def open_current_files
    opened_files = nil
    unless @file_list[0]
      targets_and_types, start_time, end_time, packets_by_target = @collection.target_info
      build_file_list(targets_and_types, @current_time, end_time)
      BucketFileCache.hint(@file_list)
    end

    @file_list.each do |bucket_path|
      file_start_time, file_end_time = get_file_times(bucket_path)
      if file_start_time <= @current_time
        bucket_file = BucketFileCache.reserve(bucket_path)
        bplr = OpenC3::BufferedPacketLogReader.new(bucket_file)
        bplr.open(bucket_file.local_path)
        @open_readers << bplr
        opened_files ||= []
        opened_files << bucket_path
      else
        if @open_readers.length <= 0
          # Need to advance current time and try again
          @current_time = file_start_time
          redo
        else
          break
        end
      end
    end
    if opened_files
      opened_files.each do |opened_file|
        @file_list.delete(opened_file)
      end
    end
  end

  def next_packet_and_topic
    next_time = nil
    next_reader = nil
    closed_readers = nil
    @open_readers.each do |reader|
      time = reader.next_packet_time
      if time
        if next_time.nil? or time < next_time
          next_time = time
          next_reader = reader
        end
      else
        reader.close
        BucketFileCache.unreserve(reader.bucket_file)
        closed_readers ||= []
        closed_readers << reader
      end
    end
    if closed_readers
      closed_readers.each do |reader|
        @open_readers.delete(reader)
        @collection.apply_last_offsets(reader.last_offsets)
      end
    end
    if next_reader
      packet = next_reader.buffered_read
      @current_time = packet.packet_time
      topic = next_reader.bucket_file.topic_prefix + '__' + packet.packet_name
      return packet, topic
    else
      if @file_list.length > 0
        open_current_files()
        return next_packet_and_topic()
      else
        return nil
      end
    end
  end

  def build_file_list(targets_and_types, start_time, end_time, include_earlier_start: false)
    list = []
    targets_and_types.each do |target_and_type|
      target_name, cmd_or_tlm, stream_mode = target_and_type.split("__")
      directories = @bucket.list_directories(bucket: ENV['OPENC3_LOGS_BUCKET'], path: "#{@scope}/#{stream_mode.to_s.downcase}_logs/#{cmd_or_tlm.to_s.downcase}/#{target_name}")
      filtered_directories = filter_directories_to_time_range(directories, start_time, end_time)
      filtered_directories.each do |directory|
        directory_files = @bucket.list_objects(bucket: ENV['OPENC3_LOGS_BUCKET'], prefix: "#{@scope}/#{stream_mode.to_s.downcase}_logs/#{cmd_or_tlm.to_s.downcase}/#{target_name}/#{directory}")
        files = filter_files_to_time_range(directory_files, start_time, end_time, include_earlier_start: include_earlier_start)
        list.concat(files)
      end
    end
    @file_list = list.sort
    to_remove = []
    @file_list.each do |file|
      if @historical_file_list[file]
        to_remove << file
      else
        @historical_file_list[file] = true
      end
    end
    to_remove.each do |file|
      @file_list.delete(file)
    end
  end

  def filter_directories_to_time_range(directories, start_time, end_time)
    result = []
    directories.each do |directory|
      result << directory if directory_in_time_range(directory, start_time, end_time)
    end
    return result
  end

  def directory_in_time_range(directory, start_time, end_time)
    basename = File.basename(directory)
    directory_start_time = DateTime.strptime(basename, DIRECTORY_TIMESTAMP_FORMAT).to_time
    directory_end_time = directory_start_time + Time::SEC_PER_DAY
    if (start_time < directory_end_time) and (not end_time or end_time >= directory_start_time)
      return true
    else
      return false
    end
  end

  def filter_files_to_time_range(files, start_time, end_time, include_earlier_start:)
    result = []
    files.each do |file|
      result << file.key if File.extname(file.key) == '.bin' and file_in_time_range(file.key, start_time, end_time, include_earlier_start: include_earlier_start)
    end
    return result
  end

  def file_in_time_range(bucket_path, start_time, end_time, include_earlier_start:)
    file_start_time, file_end_time = get_file_times(bucket_path)
    if include_earlier_start
      if (start_time < file_end_time) and (not end_time or end_time >= file_start_time)
        return true
      end
    else
      if (start_time < file_start_time) and (not end_time or end_time >= file_start_time)
        return true
      end
    end
    return false
  end

  def get_file_times(bucket_path)
    basename = File.basename(bucket_path)
    file_start_timestamp, file_end_timestamp, other = basename.split("__")
    file_start_time = DateTime.strptime(file_start_timestamp, FILE_TIMESTAMP_FORMAT).to_time
    file_end_time = DateTime.strptime(file_end_timestamp, FILE_TIMESTAMP_FORMAT).to_time
    return file_start_time, file_end_time
  end
end
