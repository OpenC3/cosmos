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
OpenC3.require_file 'openc3/utilities/bucket_file_cache'

class LoggedStreamingThread < StreamingThread
  ALLOWABLE_START_TIME_OFFSET_NSEC = 60 * Time::NSEC_PER_SECOND

  def initialize(streaming_api, collection, max_batch_size = 100, scope:)
    super(streaming_api, collection, max_batch_size)
    @file_reader = StreamingObjectCollectionFileReader.new
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
      attempt_handoff_to_realtime()
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

    # This will read out packets until nothing is left
    done = @file_reader.each(@collection) do |packet, topic|
      break if @cancel_thread
      topic_without_hashtag = topic.gsub(/{|}/, '')

      # Get the item objects that need this topic
      objects = item_objects_by_topic[topic]

      break if @cancel_thread
      result_entry = handle_packet(packet, objects)
      results << result_entry if result_entry
      break if @cancel_thread

      # Transmit if we have a full batch or more
      if results.length >= @max_batch_size
        @streaming_api.transmit_results(results)
        results.clear
      end

      # Get the packet objects that need this topic
      objects = packet_objects_by_topic[topic]

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

      break if @cancel_thread
    end
    break if @cancel_thread

    if done # We reached the end time
      OpenC3::Logger.info "Finishing LoggedStreamingThread for #{@collection.length} objects - Reached End Time"
      finish(@collection.objects)
    end
  end

  def handle_packet(packet, objects)
    if first_object.stream_mode == :RAW
      return handle_raw_packet(packet.buffer(false), objects, packet.packet_time.to_nsec_from_epoch)
    else # @stream_mode == :DECOM or :REDUCED_X
      return handle_json_packet(packet, objects)
    end
  end

    # Get next file from file cache
    first_object = objects[0]
    file_end_time = first_object.end_time
    file_end_time = Time.now.to_nsec_from_epoch unless file_end_time
    file_path = BucketFileCache.instance.reserve_file(first_object.cmd_or_tlm, first_object.target_name, first_object.packet_name,
      first_object.start_time, file_end_time, @stream_mode, scope: @scope) # TODO: look at how @stream_mode is being used
    if file_path
      file_path_split = File.basename(file_path).split("__")
      file_end_time = DateTime.strptime(file_path_split[1], BucketFileCache::TIMESTAMP_FORMAT).to_f * Time::NSEC_PER_SECOND # TODO: get format from different class' constant?

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
      @last_offsets = plr.last_offsets

      # Move to the next file
      BucketFileCache.instance.unreserve_file(file_path)
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
        offsets = @last_offsets if @last_offsets

        # Guesstimate start offset in stream based on first packet time and redis time
        redis_time = msg_id.split('-')[0].to_i * 1000000
        delta = redis_time - oldest_time
        guess_offset = ((first_object.start_time + delta) / 1_000_000).to_s + '-0'

        OpenC3::Logger.debug "Oldest Redis id:#{msg_id} msg time:#{oldest_time} last object time:#{first_object.start_time} guess_offset:#{guess_offset} offsets:#{offsets}"
        objects.each do |object|
          offset = @last_offsets[object.topic]
          offset = guess_offset unless offset
          object.offset = offset
        end
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
  def attempt_handoff_to_realtime

  end
end
