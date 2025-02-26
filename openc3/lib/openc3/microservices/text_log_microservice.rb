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

require 'openc3/microservices/microservice'
require 'openc3/topics/topic'
require 'openc3/io/json_rpc'

module OpenC3
  class TextLogMicroservice < Microservice
    def initialize(name)
      super(name)
      @config['options'].each do |option|
        case option[0].upcase
        when 'CYCLE_TIME' # Maximum time between log files
          @cycle_time = option[1].to_i
        when 'CYCLE_SIZE' # Maximum size of a log file
          @cycle_size = option[1].to_i
        else
          @logger.error("Unknown option passed to microservice #{@name}: #{option}")
        end
      end

      # These settings limit the log file to 10 minutes or 50MB of data, whichever comes first
      @cycle_time = 600 unless @cycle_time # 10 minutes
      @cycle_size = 50_000_000 unless @cycle_size # ~50 MB

      @error_count = 0
      @metric.set(name: 'text_log_total', value: @count, type: 'counter')
      @metric.set(name: 'text_error_total', value: @error_count, type: 'counter')
    end

    def run
      setup_tlws()
      while true
        break if @cancel_thread

        Topic.read_topics(@topics) do |topic, msg_id, msg_hash, redis|
          break if @cancel_thread

          log_data(topic, msg_id, msg_hash, redis)
          @count += 1
          @metric.set(name: 'text_log_total', value: @count, type: 'counter')
        end
      end
    end

    def setup_tlws
      @tlws = {}
      @topics.each do |topic|
        topic_split = topic.gsub(/{|}/, '').split("__") # Remove the redis hashtag curly braces
        scope = topic_split[0]
        log_name = topic_split[1]
        remote_log_directory = "#{scope}/text_logs/#{log_name}"
        @tlws[topic] = TextLogWriter.new(remote_log_directory, true, @cycle_time, @cycle_size, nil, nil, false)
      end
    end

    def log_data(topic, msg_id, msg_hash, redis)
      msgid_seconds_from_epoch = msg_id.split('-')[0].to_i / 1000.0
      delta = Time.now.to_f - msgid_seconds_from_epoch
      @metric.set(name: 'text_log_topic_delta_seconds', value: delta, type: 'gauge', unit: 'seconds', help: 'Delta time between data written to stream and text log start')
      @tlws[topic].write(msg_hash["time"].to_i, msg_hash.as_json(allow_nan: true).to_json(allow_nan: true), topic, msg_id)
      @count += 1
    rescue => err
      @error = err
      @logger.error("#{@name} error: #{err.formatted}")
      @error_count += 1
      @metric.set(name: 'text_log_error_total', value: @error_count, type: 'counter')
    end

    def shutdown
      # Make sure all the existing logs are properly closed down
      threads = []
      @tlws.each do |topic, tlw|
        threads.concat(tlw.shutdown)
      end
      # Wait for all the logging threads to move files to buckets
      threads.flatten.compact.each do |thread|
        thread.join
      end
      super()
    end
  end
end

if __FILE__ == $0
  OpenC3::TextLogMicroservice.run
  ThreadManager.instance.shutdown
  ThreadManager.instance.join
end