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
OpenC3.require_file 'openc3/config/config_parser'

class StreamingThread
  def initialize(streaming_api, collection, max_batch_size = 100)
    # OpenC3::Logger.level = OpenC3::Logger::DEBUG
    @streaming_api = streaming_api
    @collection = collection
    @max_batch_size = max_batch_size
    @cancel_thread = false
    @thread = nil
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
    ensure
      @streaming_api.complete_thread(self)
    end
  end

  def add(collection)
    collection.objects.each do |object|
      @collection.add(object)
    end
  end

  def remove(collection)
    collection.objects.each do |object|
      @collection.remove(object)
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

  def redis_thread_body
    topics, offsets, item_objects_by_topic, packet_objects_by_topic = @collection.topics_offsets_and_objects
    results = []
    if topics.length > 0
      # 500ms timeout to allow for thread to shutdown within 1 second
      xread_result = OpenC3::Topic.read_topics(topics, offsets, 500) do |topic, msg_id, msg_hash, _|
        stored = ConfigParser.handle_true_false(msg_hash["stored"])
        next if stored # Ignore stored packets while realtime streaming

        break if @cancel_thread
        topic_without_hashtag = topic.gsub(/{|}/, '')

        # Get the item objects that need this topic
        objects = item_objects_by_topic[topic]

        # Update the offset for each object
        objects.each do |object|
          object.offset = msg_id
        end

        break if @cancel_thread
        result_entry = handle_message(msg_hash, objects)
        results << result_entry if result_entry
        break if @cancel_thread

        # Transmit if we have a full batch or more
        if results.length >= @max_batch_size
          @streaming_api.transmit_results(results)
          results.clear
        end

        # Get the packet objects that need this topic
        objects = packet_objects_by_topic[topic]

        # Update the offset for each object
        objects.each do |object|
          object.offset = msg_id
        end

        objects.each do |object|
          break if @cancel_thread
          result_entry = handle_message(msg_hash, [object])
          results << result_entry if result_entry
          # Transmit if we have a full batch or more
          if results.length >= @max_batch_size
            @streaming_api.transmit_results(results)
            results.clear
          end
        end

        break if @cancel_thread
      end

      # Transmit less than a batch if we have that
      @streaming_api.transmit_results(results)
      results.clear

      # Check for completed objects by wall clock time if we got nothing
      check_for_completed_objects() if xread_result and xread_result.length == 0
    else
      @cancel_thread = true
    end
  end

  def handle_message(msg_hash, objects)
    first_object = objects[0]
    time = msg_hash['time'].to_i
    if first_object.stream_mode == :RAW
      return handle_raw_packet(msg_hash['buffer'], objects, time)
    else # @stream_mode == :DECOM or :REDUCED_X
      json_packet = OpenC3::JsonPacket.new(first_object.cmd_or_tlm, first_object.target_name, first_object.packet_name,
        time, OpenC3::ConfigParser.handle_true_false(msg_hash["stored"]), msg_hash["json_data"])
      return handle_json_packet(json_packet, objects)
    end
  end

  def handle_json_packet(json_packet, objects)
    time = json_packet.packet_time
    objects = objects_active?(objects, time.to_nsec_from_epoch)
    return nil if objects.length <= 0
    result = {}
    result['__time'] = time.to_nsec_from_epoch
    objects.each do |object|
      # OpenC3::Logger.debug("item:#{object.item_name} key:#{object.key} type:#{object.value_type}")
      if object.item_name
        result[object.item_key] = json_packet.read(object.item_name, object.value_type)
      else # whole packet
        result["__type"] = "PACKET"
        result['__packet'] = object.key
        this_packet = json_packet.read_all(object.value_type)
        result = result.merge(this_packet)
        return result
      end
    end
    result['__type'] = "ITEMS"
    return result
  end

  def handle_raw_packet(buffer, objects, time)
    objects = objects_active?(objects, time)
    return nil if objects.length <= 0
    return {
      "__type" => "PACKET",
      "__packet" => objects[0].key,
      "__time" => time,
      "buffer" => Base64.encode64(buffer),
    }
  end

  def objects_active?(objects, time)
    # If LoggedStreamingThread - every object will have the same end time
    # If RealtimeStreamingThread - objects will have no end time or end times in the future
    result = []
    completed_objects = []
    objects.each do |object|
      if object.end_time and time > object.end_time
        completed_objects << object
      else
        result << object
      end
    end
    finish(completed_objects) if completed_objects.length > 0
    return result
  end

  # Only use this method if nothing was received from Redis
  def check_for_completed_objects
    now = Time.now.to_nsec_from_epoch
    objects_active?(@collection.objects, now)
  end

  def finish(objects)
    OpenC3::Logger.info "Finishing #{objects.length} objects from stream"
    objects.each do |object|
      @collection.remove(object)
    end
    OpenC3::Logger.info "#{@collection.length} objects remain in stream"
    @cancel_thread = true if @collection.empty?
  end
end
