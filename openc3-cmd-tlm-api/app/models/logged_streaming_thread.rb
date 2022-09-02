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

# TODO : Handoff to realtime thread

require_relative 'streaming_thread'

class LoggedStreamingThread < StreamingThread
  ALLOWABLE_START_TIME_OFFSET_NSEC = 60 * Time::NSEC_PER_SECOND

  def initialize(thread_id, channel, collection, stream_mode, max_batch_size = 100, scope:)
    super(channel, collection, stream_mode, max_batch_size)
    @thread_id = thread_id
    @thread_mode = :SETUP
    # Reduced has no Redis streams so go direct to file
    @thread_mode = :FILE if stream_mode.to_s.upcase.include?("REDUCED")
    @scope = scope
  end

  def thread_body
    objects = @collection.objects_by_thread_id[@thread_id]
    # Cancel if we don't have any objects ... this can happen as things are processed
    # or if someone calls remove() from the StreamingApi
    @cancel_thread = true unless objects and objects.length > 0
    return if @cancel_thread

    first_object = objects[0]
    if @thread_mode == :SETUP
      # The goal of this mode is to determine if we are starting with files or from
      # realtime

      # start_time can be at most 1 minute in the future to prevent
      # spinning up threads that just block forever
      if (first_object.start_time - ALLOWABLE_START_TIME_OFFSET_NSEC) > Time.now.to_nsec_from_epoch
        OpenC3::Logger.info "Finishing stream start_time too far in future"
        finish(objects)
        @cancel_thread = true
        return
      end

      # Check the topic to figure out what we have in Redis
      oldest_msg_id, oldest_msg_hash = OpenC3::Topic.get_oldest_message(first_object.topic)

      if oldest_msg_id
        # We have data in Redis
        # Determine oldest timestamp in stream to determine if we need to go to file
        oldest_time = oldest_msg_hash['time'].to_i

        # OpenC3::Logger.debug "first start time:#{first_object.start_time} oldest:#{oldest_time}"
        if first_object.start_time < oldest_time
          # Stream from Files
          @thread_mode = :FILE
        else
          if first_object.end_time and first_object.end_time < oldest_time
            # Bad times - just end
            OpenC3::Logger.info "Finishing stream - start_time after end_time"
            finish(objects)
            @cancel_thread = true
            return
          else
            # Stream from Redis
            # Guesstimate start offset in stream based on first packet time and redis time
            redis_time = oldest_msg_id.split('-')[0].to_i * 1_000_000
            delta = redis_time - oldest_time
            # Start streaming from calculated redis time
            offset = ((first_object.start_time + delta) / 1_000_000).to_s + '-0'
            # OpenC3::Logger.debug "stream from Redis offset:#{offset} redis_time:#{redis_time} delta:#{delta}"
            objects.each {|object| object.offset = offset}
            @thread_mode = :STREAM
          end
        end
      else
        # Might still have data in files
        @thread_mode = :FILE
      end
    elsif @thread_mode == :STREAM
      objects_by_topic = { objects[0].topic => objects }
      redis_thread_body([first_object.topic], [first_object.offset], objects_by_topic)
    else # @thread_mode == :FILE
      # Get next file from file cache
      file_end_time = first_object.end_time
      file_end_time = Time.now.to_nsec_from_epoch unless file_end_time
      file_path = S3FileCache.instance.reserve_file(first_object.cmd_or_tlm, first_object.target_name, first_object.packet_name,
        first_object.start_time, file_end_time, @stream_mode, scope: @scope) # TODO: look at how @stream_mode is being used
      if file_path
        file_path_split = File.basename(file_path).split("__")
        file_end_time = DateTime.strptime(file_path_split[1], S3FileCache::TIMESTAMP_FORMAT).to_f * Time::NSEC_PER_SECOND # TODO: get format from different class' constant?

        # Scan forward to find first packet needed
        # Stream forward until packet > end_time or no more packets
        results = []
        plr = OpenC3::PacketLogReader.new()
        topic_without_hashtag = first_object.topic.gsub(/{|}/, '') # This removes all curly braces, and we don't allow curly braces in our keys
        done = plr.each(file_path, false, Time.from_nsec_from_epoch(first_object.start_time), Time.from_nsec_from_epoch(first_object.end_time)) do |packet|
          time = packet.received_time if packet.respond_to? :received_time
          time ||= packet.packet_time
          result = nil
          if @stream_mode == :RAW
            result = handle_raw_packet(packet.buffer, objects, time.to_nsec_from_epoch, topic_without_hashtag)
          else # @stream_mode == :DECOM
            result = handle_json_packet(packet, objects, topic_without_hashtag)
          end
          if result
            results << result
          else
            break
          end
          if results.length > @max_batch_size
            transmit_results(results)
            results.clear
          end
          break if @cancel_thread
        end
        transmit_results(results)
        @last_file_redis_offset = plr.redis_offset

        # Move to the next file
        S3FileCache.instance.unreserve_file(file_path)
        objects.each {|object| object.start_time = file_end_time}

        if done # We reached the end time
          OpenC3::Logger.info "Finishing stream for topic: #{first_object.topic} - End of files"
          finish(objects)
        end
      else
        # Switch to stream from Redis
        # Determine oldest timestamp in stream
        msg_id, msg_hash = OpenC3::Topic.get_oldest_message(first_object.topic)
        if msg_hash
          OpenC3::Logger.info "Switch stream from file to Redis"
          oldest_time = msg_hash['time'].to_i
          # Stream from Redis
          offset = @last_file_redis_offset if @last_file_redis_offset
          if !offset
            # Guesstimate start offset in stream based on first packet time and redis time
            redis_time = msg_id.split('-')[0].to_i * 1000000
            delta = redis_time - oldest_time
            # Start streaming from calculated redis time
            offset = ((first_object.start_time + delta) / 1_000_000).to_s + '-0'
          end
          OpenC3::Logger.debug "Oldest Redis id:#{msg_id} msg time:#{oldest_time} last object time:#{first_object.start_time} offset:#{offset}"
          objects.each {|object| object.offset = offset}
          @thread_mode = :STREAM
        else
          OpenC3::Logger.info "Finishing stream for topic: #{first_object.topic} - No data in Redis"
          finish(objects)
        end
      end
    end

    # Transfers item to realtime thread when complete (if continued)
    # Needs to mutex transfer
    #   checks if equal offset if packet already exists in realtime
    #   if doesn't exist adds with item offset
    #   if does exist and equal - transfer
    #   if does exist and less than - add item with less offset
    #   if does exist and greater than - catch up and try again
  end
end
