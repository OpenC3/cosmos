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

require 'openc3/logs/log_writer'
require 'socket'

module OpenC3
  # Creates a text log. Can automatically cycle the log based on an elasped
  # time period or when the log file reaches a predefined size.
  class TextLogWriter < LogWriter
    NEWLINE = "\n".freeze
    def initialize(*args)
      super(*args)
      @container_name = Socket.gethostname
    end

    # Write to the log file.
    #
    # If no log file currently exists in the filesystem, a new file will be
    # created.
    #
    # @param time_nsec_since_epoch [Integer] 64 bit integer nsecs since EPOCH
    # @param data [String] String of data
    # @param redis_offset [Integer] The offset of this packet in its Redis stream
    def write(time_nsec_since_epoch, data, redis_topic, redis_offset)
      return if !@logging_enabled

      @mutex.synchronize do
        prepare_write(time_nsec_since_epoch, data.length, redis_topic, redis_offset)
        write_entry(time_nsec_since_epoch, data) if @file
      end
    rescue => err
      Logger.instance.error "Error writing #{@filename} : #{err.formatted}"
      OpenC3.handle_critical_exception(err)
    end

    def write_entry(time_nsec_since_epoch, data)
      @file.write(data)
      @file.write(NEWLINE)
      @file_size += (data.length + NEWLINE.length)
      @first_time = time_nsec_since_epoch if !@first_time or time_nsec_since_epoch < @first_time
      @last_time = time_nsec_since_epoch if !@last_time or time_nsec_since_epoch > @last_time
    end

    def bucket_filename
      # Put the name of the redis topic in the filename, but remove the scope
      # because we're already in a directory with the scope name
      redis_topic = @last_offsets.keys[0].to_s
      split_index = redis_topic.index("__") + 2
      topic_name = redis_topic[split_index, redis_topic.length - split_index]
      "#{first_timestamp}__#{last_timestamp}__#{topic_name}" + extension
    end

    # Closing a log file isn't critical so we just log an error
    # Returns threads that moves log to bucket
    def close_file(take_mutex = true)
      threads = []
      @mutex.lock if take_mutex
      begin
        # Need to write the OFFSET_MARKER for each packet
        @last_offsets.each do |redis_topic, last_offset|
          time = Time.now
          data = { time: time.to_nsec_from_epoch, '@timestamp' => time.xmlschema(3), severity: 'INFO', "microservice_name" => Logger.microservice_name, "container_name" => @container_name, "last_offset" => last_offset, "redis_topic" => redis_topic, "type" => "offset" }
          write_entry(time.to_nsec_from_epoch, data.as_json(allow_nan: true).to_json(allow_nan: true)) if @file
        end

        threads.concat(super(false))

      ensure
        @mutex.unlock if take_mutex
      end
      return threads
    end

    def extension
      '.txt'.freeze
    end
  end
end
