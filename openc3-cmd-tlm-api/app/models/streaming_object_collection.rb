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

# Helper class to collect StreamingObjects
class StreamingObjectCollection
  attr_reader :includes_realtime

  def initialize
    @objects = []
    @objects_by_id = {}
    @topics_and_offsets = {}
    @item_objects_by_topic = {}
    @packet_objects_by_topic = {}
    @includes_realtime = false
    @mutex = Mutex.new
  end

  def objects
    @mutex.synchronize do
      return @objects.dup
    end
  end

  def add(object)
    @mutex.synchronize do
      @includes_realtime = true if object.realtime
      found_object = @objects_by_id[object.id]
      unless found_object
        @objects << object
        @objects_by_id[object.id] = object
        offset = @topics_and_offsets[object.topic]
        @topics_and_offsets[object.topic] = object.offset if !offset or object.offset > offset
        if object.item_key
          @item_objects_by_topic[object.topic] ||= []
          @item_objects_by_topic[object.topic] << object
        else
          @packet_objects_by_topic[object.topic] ||= []
          @packet_objects_by_topic[object.topic] << object
        end
      end
    end
  end

  def remove(object)
    @mutex.synchronize do
      found_object = @objects_by_id[object.id]
      if found_object
        @objects.delete(found_object)
        @objects_by_id.delete(found_object.id)
        item_objects = @item_objects_by_topic[object.topic]
        item_objects.delete(found_object) if item_objects
        packet_objects = @packet_objects_by_topic[object.topic]
        packet_objects.delete(found_object) if packet_objects
        if item_objects
          if item_objects.length == 0
            if packet_objects
              if packet_objects.length == 0
                # Nothing left in either for this topic
                @topics_and_offsets.delete(object.topic)
              end
            else
              # Just item_objects and nothing left
              @topics_and_offsets.delete(object.topic)
            end
          end
        else
          if packet_objects
            if packet_objects.length == 0
              # Just packet_objects and nothing left
              @topics_and_offsets.delete(object.topic)
            end
          else
            # Neither objects - Shouldn't happen
            @topics_and_offsets.delete(object.topic)
          end
        end
      end
    end
  end

  def topics_offsets_and_objects
    @mutex.synchronize do
      @objects.each do |object|
        @topics_and_offsets[object.topic] = object.offset
      end
      return @topics_and_offsets.keys, @topics_and_offsets.values, @item_objects_by_topic.dup, @packet_objects_by_topic.dup
    end
  end

  def target_info
    targets_and_types = {}
    packets_by_target = {}
    start_time = nil
    end_time = nil
    @objects.each do |object|
      targets_and_types["#{object.target_name}__#{object.cmd_or_tlm}__#{object.stream_mode}"] = true
      start_time = Time.from_nsec_from_epoch(object.start_time)
      end_time = Time.from_nsec_from_epoch(object.end_time)
      packets_by_target[object.target_name] ||= []
      target_packets = packets_by_target[object.target_name]
      target_packets << object.packet_name unless target_packets.include?(object.packet_name)
    end
    return targets_and_types.keys, start_time, end_time, packets_by_target
  end

  def apply_last_offsets(last_offsets)
    last_offsets.each do |topic, last_offset|
      objects = @item_objects_by_topic[topic]
      if objects
        objects.each do |object|
          object.offset = last_offset
        end
      end
      objects = @packet_objects_by_topic[topic]
      if objects
        objects.each do |object|
          object.offset = last_offset
        end
      end
    end
  end

  def handoff(collection)
  end

  def length
    return @objects.length
  end

  def empty?
    length() == 0
  end
end
