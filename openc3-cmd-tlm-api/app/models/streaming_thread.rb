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

require 'base64'
require 'openc3'

OpenC3.require_file 'openc3/packets/packet'
OpenC3.require_file 'openc3/utilities/store'
OpenC3.require_file 'openc3/utilities/s3_file_cache'
OpenC3.require_file 'openc3/packets/json_packet'
OpenC3.require_file 'openc3/logs/packet_log_reader'

class StreamingThread
  def initialize(channel, collection, stream_mode, max_batch_size = 100)
    # OpenC3::Logger.level = OpenC3::Logger::DEBUG
    @channel = channel
    @collection = collection
    @max_batch_size = max_batch_size
    @cancel_thread = false
    @thread = nil
    @stream_mode = stream_mode
  end

  def start
    @thread = Thread.new do
      while true
        break if @cancel_thread
        thread_body()
        break if @cancel_thread
      end
    rescue => err
      OpenC3::Logger.error "#{self.class.name} unexpectedly died\n#{err.formatted}"
    end
  end

  def alive?
    if @thread
      @thread.alive?
    else
      false
    end
  end

  def thread_body
    raise "Must be defined by subclasses"
  end

  def stop
    @cancel_thread = true
  end

  def transmit_results(results, force: false)
    if results.length > 0 or force
      # Fortify: This send is intentionally bypassing access control to get to the
      # private transmit method
      @channel.send(:transmit, JSON.generate(results.as_json(:allow_nan => true)))
    end
  end

  def redis_thread_body(topics, offsets, objects_by_topic)
    # OpenC3::Logger.debug "#{self.class} redis_thread_body topics:#{topics} offsets:#{offsets} objects:#{objects_by_topic}"
    results = []
    if topics.length > 0
      rtr = OpenC3::Topic.read_topics(topics, offsets) do |topic, msg_id, msg_hash, redis|
        # OpenC3::Logger.debug "read_topics topic:#{topic} offsets:#{offsets} id:#{msg_id} msg time:#{msg_hash['time']}"
        objects = objects_by_topic[topic]
        objects.each do |object|
          object.offset = msg_id
        end
        results_by_value_type = []
        value_types = objects.group_by { |object| object.value_type }
        value_types.each_value do |value|
          results_by_value_type << handle_message(topic, msg_id, msg_hash, redis, value)
        end
        results_by_value_type.compact!
        if results_by_value_type.length > 0
          results.concat(results_by_value_type)
        else
          break results
        end
        if results.length > @max_batch_size
          transmit_results(results)
          results.clear
        end
        break results if @cancel_thread
        results
      end

      # If we're no longer grabbing packets from the stream (empty result)
      # we check to see if we need to continue
      # OpenC3::Logger.debug "rtr:#{rtr} empty?:#{rtr.empty?} results:#{results} topics:#{topics} offsets:#{offsets}"
      if rtr.nil? or rtr.empty?
        topics.each do |topic|
          objects = objects_by_topic[topic]
          objects.each do |object|
            keys = []
            # If time has passed the end_time and we're still not getting anything we're done
            if object.end_time and object.end_time < Time.now.to_nsec_from_epoch
              keys << object.key
              @cancel_thread = true
            end
            @collection.remove(keys)
          end
        end
      end
      transmit_results(results, force: @collection.empty?)
      transmit_results([], force: true) if !results.empty? and @collection.empty?
    else
      sleep(1)
    end
  end

  def handle_message(topic, msg_id, msg_hash, redis, objects)
    topic_without_hashtag = topic.gsub(/{|}/, '') # This removes all curly braces, and we don't allow curly braces in our keys
    first_object = objects[0]
    time = msg_hash['time'].to_i
    if @stream_mode == :RAW
      return handle_raw_packet(msg_hash['buffer'], objects, time, topic_without_hashtag)
    else # @stream_mode == :DECOM
      json_packet = OpenC3::JsonPacket.new(first_object.cmd_or_tlm, first_object.target_name, first_object.packet_name,
        time, OpenC3::ConfigParser.handle_true_false(msg_hash["stored"]), msg_hash["json_data"])
      return handle_json_packet(json_packet, objects, topic_without_hashtag)
    end
  end

  def handle_json_packet(json_packet, objects, topic)
    time = json_packet.packet_time
    keys_remain = objects_active?(objects, time.to_nsec_from_epoch)
    return nil unless keys_remain
    result = {}
    objects.each do |object|
      # OpenC3::Logger.debug("item:#{object.item_name} key:#{object.key} type:#{object.value_type}")
      if object.item_name
        result[object.key] = json_packet.read(object.item_name, object.value_type)
      else # whole packet
        this_packet = json_packet.read_all(object.value_type)
        result = result.merge(this_packet)
        result['packet'] = topic + "__" + object.value_type.to_s
      end
    end
    result['time'] = time.to_nsec_from_epoch
    return result
  end

  def handle_raw_packet(buffer, objects, time, topic)
    keys_remain = objects_active?(objects, time)
    return nil unless keys_remain
    return {
      packet: topic,
      buffer: Base64.encode64(buffer),
      time: time
    }
  end

  def objects_active?(objects, time)
    first_object = objects[0]
    if first_object.end_time and time > first_object.end_time
      # These objects have expired and are removed from the collection
      keys = []
      objects.each do |object|
        keys << object.key
      end
      @collection.remove(keys)
      return false
    end
    return true
  end
end

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
      # Get the newest message because we only stream if there is data after our start time
      _, msg_hash_new = OpenC3::Topic.get_newest_message(first_object.topic)
      # OpenC3::Logger.debug "first time:#{first_object.start_time} newest:#{msg_hash_new['time']}"
      # Allow 1 minute in the future to account for big time discrepancies, which may be caused by:
      #   - the JavaScript client using the machine's local time, which might not be set with NTP
      #   - browser security settings rounding the value within a few milliseconds
      allowable_start_time = first_object.start_time - ALLOWABLE_START_TIME_OFFSET_NSEC
      if msg_hash_new && msg_hash_new['time'].to_i > allowable_start_time
        # Determine oldest timestamp in stream to determine if we need to go to file
        msg_id, msg_hash = OpenC3::Topic.get_oldest_message(first_object.topic)
        oldest_time = msg_hash['time'].to_i
        # OpenC3::Logger.debug "first start time:#{first_object.start_time} oldest:#{oldest_time}"
        if first_object.start_time < oldest_time
          # Stream from Files
          @thread_mode = :FILE
        else
          # Stream from Redis
          # Guesstimate start offset in stream based on first packet time and redis time
          redis_time = msg_id.split('-')[0].to_i * 1_000_000
          delta = redis_time - oldest_time
          # Start streaming from calculated redis time
          offset = ((first_object.start_time + delta) / 1_000_000).to_s + '-0'
          # OpenC3::Logger.debug "stream from Redis offset:#{offset} redis_time:#{redis_time} delta:#{delta}"
          objects.each {|object| object.offset = offset}
          @thread_mode = :STREAM
        end
      else
        # Since we're not going to transmit anything cancel and transmit an empty result
        # OpenC3::Logger.debug "NO DATA DONE! transmit 0 results"
        @cancel_thread = true
        transmit_results([], force: true)
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
          @cancel_thread = true
          transmit_results([], force: true)
        end
      else
        OpenC3::Logger.info "Switch stream from file to Redis"
        # TODO: What if there is no new data in the Redis stream?

        # Switch to stream from Redis
        # Determine oldest timestamp in stream
        msg_id, msg_hash = OpenC3::Topic.get_oldest_message(first_object.topic)
        if msg_hash
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
          @cancel_thread = true
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
