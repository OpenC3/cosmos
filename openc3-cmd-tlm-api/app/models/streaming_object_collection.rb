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

# Helper class to collect StreamingObjects and map them to threads
class StreamingObjectCollection
  attr_reader :objects_by_thread_id

  def initialize
    @objects_by_key = {}
    @objects_by_thread_id = {}
    @objects_by_thread_id[nil] = []
    @mutex = Mutex.new
  end

  def add(objects)
    @mutex.synchronize do
      objects.each do |object|
        existing_object = @objects_by_key[object.key]
        if existing_object
          @objects_by_thread_id[existing_object.thread_id].delete(existing_object)
        end
        @objects_by_key[object.key] = object
        @objects_by_thread_id[object.thread_id] ||= []
        @objects_by_thread_id[object.thread_id] << object
      end
    end
  end

  def remove(keys)
    @mutex.synchronize do
      keys.each do |key|
        object = @objects_by_key[key]
        if object
          @objects_by_key.delete(key)
          @objects_by_thread_id[object.thread_id].delete(object)
        end
      end
    end
  end

  def realtime_topics_offsets_and_objects
    topics_and_offsets = {}
    objects_by_topic = {}
    @mutex.synchronize do
      @objects_by_thread_id[nil].each do |object|
        if object.start_time == nil
          offset = topics_and_offsets[object.topic]
          topics_and_offsets[object.topic] = object.offset if !offset or object.offset < offset
          objects_by_topic[object.topic] ||= []
          objects_by_topic[object.topic] << object
        end
      end
    end
    return topics_and_offsets.keys, topics_and_offsets.values, objects_by_topic
  end

  def length
    return @objects_by_key.length
  end

  def empty?
    length() == 0
  end
end
