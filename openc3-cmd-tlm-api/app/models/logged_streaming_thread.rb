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
require_relative 'streaming_object_file_reader'
OpenC3.require_file 'openc3/utilities/bucket_file_cache'

class LoggedStreamingThread < StreamingThread
  ALLOWABLE_START_TIME_OFFSET_NSEC = 60 * Time::NSEC_PER_SECOND

  def initialize(streaming_api, collection, max_batch_size = 100, scope:)
    super(streaming_api, collection, max_batch_size)
    @thread_mode = :SETUP
    @scope = scope
  end

  def thread_body
    objects = @collection.objects
    # Cancel if we don't have any objects ... this can happen as things are processed
    # or if someone calls remove() from the StreamingApi
    @cancel_thread = true unless objects and objects.length > 0
    return if @cancel_thread

    if @thread_mode == :SETUP
      setup_thread_body(objects)
    elsif @thread_mode == :STREAM
      redis_thread_body()
      @cancel_thread = attempt_handoff_to_realtime()
    else # @thread_mode == :FILE
      file_thread_body(objects)
    end
  end

  def setup_thread_body(objects)
    first_object = objects[0]

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
  end

  def file_thread_body(objects)
    topics, offsets, item_objects_by_topic, packet_objects_by_topic = @collection.topics_offsets_and_objects
    results = []

    # This will read out packets until nothing is left
    file_reader = StreamingObjectFileReader.new(@collection, scope: @scope)
    done = file_reader.each do |packet, topic|
      break if @cancel_thread

      # Get the item objects that need this topic
      objects = item_objects_by_topic[topic]

      break if @cancel_thread
      if objects and objects.length > 0
        result_entry = handle_packet(packet, objects)
        results << result_entry if result_entry
      end
      break if @cancel_thread

      # Transmit if we have a full batch or more
      if results.length >= @max_batch_size
        @streaming_api.transmit_results(results)
        results.clear
      end

      # Get the packet objects that need this topic
      objects = packet_objects_by_topic[topic]

      if objects
        objects.each do |object|
          break if @cancel_thread
          result_entry = handle_packet(packet, [object])
          results << result_entry if result_entry
          # Transmit if we have a full batch or more
          if results.length >= @max_batch_size
            @streaming_api.transmit_results(results)
            results.clear
          end
        end
      end

      break if @cancel_thread
    end
    return if @cancel_thread

    # Transmit less than a batch if we have that
    @streaming_api.transmit_results(results)
    results.clear

    if done # We reached the end time
      OpenC3::Logger.info "Finishing LoggedStreamingThread for #{@collection.length} objects - Reached End Time"
      finish(@collection.objects)
      return
    end

    # Switch to Redis
    @thread_mode = :STREAM
  end

  def handle_packet(packet, objects)
    first_object = objects[0]
    if first_object.stream_mode == :RAW
      return handle_raw_packet(packet.buffer(false), objects, packet.packet_time.to_nsec_from_epoch)
    else # @stream_mode == :DECOM or :REDUCED_X
      return handle_json_packet(packet, objects)
    end
  end

  # Transfers item to realtime thread when complete (if continued)
  # Needs to mutex transfer
  #   checks if equal offset if packet already exists in realtime
  #   if doesn't exist adds with item offset
  #   if does exist and equal - transfer
  #   if does exist and less than - add item with less offset
  #   if does exist and greater than - catch up and try again
  def attempt_handoff_to_realtime
    if @collection.includes_realtime
      return @streaming_api.handoff_to_realtime(@collection)
    end
    return false
  end
end
