# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc.
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

require 'openc3/utilities/bucket_utilities'
require_relative 'message_log_reader'

class MessageFileReader
  FILE_TIMESTAMP_FORMAT = "%Y%m%d%H%M%S%N"
  DIRECTORY_TIMESTAMP_FORMAT = "%Y%m%d"

  def initialize(start_time:, end_time:, scope:)
    @scope = scope
    @start_time = start_time # nsec
    @end_time = end_time # nsec
    @start_time_object = nil
    @start_time_object = Time.from_nsec_from_epoch(start_time)
    @end_time_object = nil
    @end_time_object = Time.from_nsec_from_epoch(end_time) if end_time
    @current_time_object = @start_time_object
    @historical_file_list = {}
    build_file_list(overlap: true)
    BucketFileCache.hint(@file_list)
    @open_readers = []
    @extend_file_list = true
  end

  def each
    while true
      log_entry = read()
      if log_entry
        time = log_entry['time'].to_i
        next if time < @start_time
        # If we reach the end_time that means we found all the packets we asked for
        # This can be used by callers to know they are done reading
        return true if @end_time and time > @end_time
        yield log_entry
      else
        break
      end
    end
    return false
  end

  def read
    open_current_files()
    return next_log_entry()
  end

  def open_current_files
    opened_files = nil
    if not @file_list[0]
      if @extend_file_list
        # See if any new files have showed up once
        build_file_list()
        BucketFileCache.hint(@file_list)
        @extend_file_list = false
      else
        return # All files have been opened
      end
    end

    @file_list.each do |bucket_path|
      file_start_time_object, file_end_time_object = get_file_times(bucket_path)
      if file_start_time_object <= @current_time_object
        bucket_file = BucketFileCache.reserve(bucket_path)
        mlr = MessageLogReader.new(bucket_file)
        mlr.open(bucket_file.local_path)
        @open_readers << mlr
        opened_files ||= []
        opened_files << bucket_path
      else
        if @open_readers.length <= 0
          # Need to advance current time and try again
          @current_time_object = file_start_time_object
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

  def next_log_entry
    next_time = nil
    next_reader = nil
    closed_readers = nil
    @open_readers.each do |reader|
      time = reader.next_entry_time
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
      end
    end
    if next_reader
      log_entry = next_reader.read
      @current_time_object = Time.from_nsec_from_epoch(log_entry['time'].to_i)
      return log_entry
    else
      if @file_list.length > 0
        open_current_files()
        return next_log_entry()
      else
        return nil
      end
    end
  end

  def build_file_list(overlap: false)
    list = []
    prefix = "#{@scope}/text_logs/openc3_log_messages"
    list.concat(OpenC3::BucketUtilities.files_between_time(ENV['OPENC3_LOGS_BUCKET'], prefix, @start_time_object, @end_time_object, file_suffix: ".txt", overlap: overlap))

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

  def get_file_times(bucket_path)
    basename = File.basename(bucket_path)
    file_start_timestamp, file_end_timestamp, other = basename.split("__")
    file_start_time_object = DateTime.strptime(file_start_timestamp, FILE_TIMESTAMP_FORMAT).to_time
    file_end_time_object = DateTime.strptime(file_end_timestamp, FILE_TIMESTAMP_FORMAT).to_time
    return file_start_time_object, file_end_time_object
  end
end
