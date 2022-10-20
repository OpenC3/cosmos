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
    @complete_needed = false
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
      xread_result = OpenC3::Topic.read_topics(topics, offsets) do |topic, msg_id, msg_hash, redis|
        # Get the objects that need this topic
        objects = objects_by_topic[topic]

        # Update the offset for each object
        objects.each do |object|
          object.offset = msg_id
        end

        # Handle the received message once for each value type
        results_by_value_type = []
        grouped_objects = objects.group_by { |object| object.value_type }
        grouped_objects.each_value do |group_of_objects|
          results_by_value_type << handle_message(topic, msg_id, msg_hash, redis, group_of_objects)
        end
        results_by_value_type.compact! # Just array of results
        results.concat(results_by_value_type) if results_by_value_type.length > 0

        # Transmit if we have a full batch or more
        if results.length > @max_batch_size
          transmit_results(results)
          results.clear
        end

        break if @cancel_thread
      end

      # Transmit less than a batch if we have that
      transmit_results(results)
      results.clear

      if @complete_needed
        OpenC3::Logger.info "Sending stream complete marker"
        transmit_results([], force: true)
        @cancel_thread = true
        @complete_needed = false
      end

      # Check for completed objects by wall clock time if we got nothing
      check_for_completed_objects(topics, objects_by_topic) if xread_result and xread_result.length == 0
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
    objects = objects_active?(objects, time.to_nsec_from_epoch)
    return nil if objects.length <= 0
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
    objects = objects_active?(objects, time)
    return nil if objects.length <= 0
    return {
      packet: topic,
      buffer: Base64.encode64(buffer),
      time: time
    }
  end

  def objects_active?(objects, time)
    # If LoggedStreamingThread - every object will have the same end time
    # If RealtimeStreamingThread - objects will have no end time or end times in the future
    result = []
    objects.each do |object|
      if object.end_time and time > object.end_time
        finish([object], send_complete: false)
      else
        result << object
      end
    end
    return result
  end

  # Only use this method if nothing was received from Redis
  def check_for_completed_objects(topics, objects_by_topic)
    OpenC3::Logger.info "Checking for completed objects - #{@collection.length} objects remain in stream"

    # Check if any objects have completed
    completed_objects = []
    now = Time.now.to_nsec_from_epoch
    topics.each do |topic|
      objects = objects_by_topic[topic]
      objects.each do |object|
        # If time has passed the end_time this object is done
        completed_objects << object if object.end_time and object.end_time < now
      end
    end

    # Transmit that we are all done if necessary
    finish(completed_objects) if completed_objects.length > 0
  end

  def finish(objects, send_complete: true)
    OpenC3::Logger.info "Finishing #{objects.length} objects from stream"
    keys = []
    objects.each do |object|
      keys << object.key
    end
    @collection.remove(keys)
    OpenC3::Logger.info "#{@collection.length} objects remain in stream"
    if @collection.empty?
      if send_complete
        OpenC3::Logger.info "Sending stream complete marker"
        transmit_results([], force: true)
        @cancel_thread = true
      else
        @complete_needed = true
      end
    end
  end
end
