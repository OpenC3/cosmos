# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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

require_relative "topics_thread"
require_relative "message_file_reader"

class MessagesThread < TopicsThread
  ALLOWABLE_START_TIME_OFFSET_NSEC = 60 * Time::NSEC_PER_SECOND

  def initialize(
    channel,
    history_count = 0,
    max_batch_size = 100,
    start_offset: nil,
    start_time: nil,
    end_time: nil,
    types: nil,
    level: nil,
    scope:
  )
    @start_time = start_time
    @end_time = end_time
    @types = types
    if @types and (Array !== @types)
      @types = [@types]
    end
    @level = level
    @redis_offset = nil # Redis offset to transition from files
    @scope = scope
    @thread_mode = :SETUP
    @topics = ["#{scope}__openc3_log_messages", "#{scope}__openc3_ephemeral_messages"]

    offsets = nil
    # $ means only new messages for the ephemeral topic
    offsets = [start_offset, "$"] if start_offset
    super(@topics, channel, history_count, max_batch_size, offsets: offsets)
  end

  def setup_thread_body
    # The goal of this mode is to determine if we are starting with files or from
    # realtime
    if @start_time
      # start_time can be at most 1 minute in the future to prevent
      # spinning up threads that just block forever
      if (@start_time - ALLOWABLE_START_TIME_OFFSET_NSEC) > Time.now.to_nsec_from_epoch
        OpenC3::Logger.info "MessagesThread - Finishing stream start_time too far in future"
        @cancel_thread = true
        return
      end

      # Check the topic to figure out what we have in Redis
      oldest_msg_id, oldest_msg_hash = OpenC3::Topic.get_oldest_message(@topics[0])

      if oldest_msg_id
        # We have data in Redis
        # Determine oldest timestamp in stream to determine if we need to go to file
        oldest_time = oldest_msg_hash["time"].to_i

        # OpenC3::Logger.debug "first start time:#{@start_time} oldest:#{oldest_time}"
        if @start_time < oldest_time
          # Stream from Files
          @thread_mode = :FILE
        else
          if @end_time and @end_time < oldest_time
            # Bad times - just end
            OpenC3::Logger.info "MessagesThread - Finishing stream - start_time after end_time"
            @cancel_thread = true
            return
          else
            # Stream from Redis
            # Guesstimate start offset in stream based on first packet time and redis time
            redis_time = oldest_msg_id.split("-")[0].to_i * 1_000_000
            delta = redis_time - oldest_time
            # Start streaming from calculated redis time
            offset = ((@start_time + delta) / 1_000_000).to_s + "-0"
            # OpenC3::Logger.debug "stream from Redis offset:#{offset} redis_time:#{redis_time} delta:#{delta}"
            @offsets[@offset_index_by_topic[@topics[0]]] = offset
            @offsets[@offset_index_by_topic[@topics[1]]] = "$" # Only new ephemeral messages
            @thread_mode = :STREAM
          end
        end
      else
        # Might still have data in files
        @thread_mode = :FILE
      end
    else
      unless @offsets
        thread_setup() # From TopicsThread
        @offsets[@offset_index_by_topic[@topics[1]]] = "$" # Only new ephemeral messages
      end
      @thread_mode = :STREAM
    end
  end

  def thread_body
    return if @cancel_thread

    if @thread_mode == :SETUP
      setup_thread_body()
    elsif @thread_mode == :STREAM
      redis_thread_body()
    else # @thread_mode == :FILE
      file_thread_body()
    end
  end

  def file_thread_body
    results = []

    # This will read out packets until nothing is left
    file_reader = MessageFileReader.new(start_time: @start_time, end_time: @end_time, scope: @scope)
    file_reader.each do |log_entry|
      break if @cancel_thread
      result_entry = handle_log_entry(log_entry)
      results << result_entry if result_entry

      # Transmit if we have a full batch or more
      if results.length >= @max_batch_size
        transmit_results(results)
        results.clear
      end
    end

    # Transmit less than a batch if we have that
    transmit_results(results)
    results.clear

    return if @cancel_thread

    # Switch to Redis
    if @redis_offset
      @offsets[@offset_index_by_topic[@topics[0]]] = @redis_offset
    else
      @offsets[@offset_index_by_topic[@topics[0]]] = "0-0"
    end
    @offsets[@offset_index_by_topic[@topics[1]]] = "$" # Only new ephemeral messages
    @thread_mode = :STREAM
  end

  def redis_thread_body
    results = []
    OpenC3::Topic.read_topics(@topics, @offsets) do |topic, msg_id, msg_hash, _redis|
      @offsets[@offset_index_by_topic[topic]] = msg_id
      msg_hash[:msg_id] = msg_id
      result_entry = handle_log_entry(msg_hash)
      results << result_entry if result_entry
      if results.length > @max_batch_size
        transmit_results(results)
        results.clear
      end
      break if @cancel_thread
    end
    transmit_results(results)
  end

  def handle_log_entry(log_entry)
    log_entry_time = log_entry["time"].to_i

    # Filter based on start_time
    return nil if @start_time and log_entry_time < @start_time

    # Filter based on end_time
    if @end_time and log_entry_time > @end_time
      OpenC3::Logger.info "MessagesThread - Finishing #{@thread_mode} - Reached End Time"
      @cancel_thread = true
      return nil
    end

    # Grab next Redis offset
    type = log_entry["type"]
    if type == "offset"
      # Save Redis offset for transition
      @redis_offset = log_entry["last_offset"]
      return nil
    end

    # Filter based on type
    if @types and !@types.include?(type)
      return nil
    end

    # Filter based on level
    if @level
      level = log_entry["level"]
      case level
      when "DEBUG"
        return nil if @level != "DEBUG"
      when "INFO"
        return nil if @level == "WARN" or @level == "ERROR" or @level == "FATAL"
      when "WARN"
        return nil if @level == "ERROR" or @level == "FATAL"
      when "ERROR"
        return nil if @level == "FATAL"
      else # 'FATAL'
        return log_entry
      end
    end
    return log_entry
  end

  def thread_teardown
    OpenC3::Logger.info "MessagesThread - Sending stream complete marker"
    transmit_results([], force: true)
  end
end
