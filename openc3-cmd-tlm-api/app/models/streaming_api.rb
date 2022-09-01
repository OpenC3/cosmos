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

require 'openc3'
OpenC3.require_file 'openc3/utilities/authorization'
require_relative 'logged_streaming_thread'
require_relative 'realtime_streaming_thread'
require_relative 'streaming_object'
require_relative 'streaming_object_collection'

class StreamingApi
  include OpenC3::Authorization

  def initialize(uuid, channel, scope: nil, token: nil)
    authorize(permission: 'tlm', scope: scope, token: token)
    @thread_id = 1
    @uuid = uuid
    @channel = channel
    @mutex = Mutex.new
    @collection = StreamingObjectCollection.new
    @realtime_thread = nil
    @logged_threads = []
    # OpenC3::Logger.level = OpenC3::Logger::DEBUG
  end

  def add(data)
    # OpenC3::Logger.debug "start:#{Time.at(data["start_time"].to_i/1_000_000_000.0).formatted}" if data["start_time"]
    # OpenC3::Logger.debug "end:#{Time.at(data["end_time"].to_i/1_000_000_000.0).formatted}" if data["end_time"]
    @mutex.synchronize do
      start_time = nil
      start_time = data["start_time"].to_i if data["start_time"]
      end_time = nil
      end_time = data["end_time"].to_i if data["end_time"]
      stream_mode = data["mode"].to_s.intern
      scope = data["scope"]
      token = data["token"]
      keys = []
      keys.concat(data["items"]) if data["items"]
      keys.concat(data["packets"]) if data["packets"]
      objects = []
      objects_by_topic = {}
      keys.each do |key|
        object = StreamingObject.new(key, start_time, end_time, stream_mode: stream_mode, scope: scope, token: token)
        objects_by_topic[object.topic] ||= []
        objects_by_topic[object.topic] << object
        objects << object
      end
      @collection.add(objects)
      if start_time
        # Create a thread that will first try to stream from log files for each topic (packet)
        objects_by_topic.each do |topic, objects|
          # OpenC3::Logger.debug "topic:#{topic} objs:#{objects} mode:#{stream_mode}"
          objects.each {|object| object.thread_id = @thread_id}
          thread = LoggedStreamingThread.new(@thread_id, @channel, @collection, stream_mode, scope: scope)
          thread.start
          @logged_threads << thread
          @thread_id += 1
        end
      elsif end_time.nil? or end_time > Time.now.to_nsec_from_epoch
        # Create a single realtime streaming thread to use the entire collection
        if @realtime_thread.nil?
          @realtime_thread = RealtimeStreamingThread.new(@channel, @collection, stream_mode)
          @realtime_thread.start
        end
      end
    end
  end

  def remove(data)
    keys = []
    keys.concat(data["items"]) if data["items"]
    keys.concat(data["packets"]) if data["packets"]
    @collection.remove(keys)
  end

  def kill
    threads = []
    if @realtime_thread
      @realtime_thread.stop
      threads << @realtime_thread
    end
    @logged_threads.each do |thread|
      thread.stop
      threads << thread
    end
    # Allow the threads a chance to stop (1.1s total)
    i = 0
    threads.each do |thread|
      while thread.alive? or i < 110 do
        sleep 0.01
        i += 1
      end
    end
    # Ok we tried, now initialize everything
    @realtime_thread = nil
    @logged_threads = []
  end
end
