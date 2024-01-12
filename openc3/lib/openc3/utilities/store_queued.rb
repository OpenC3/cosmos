# encoding: ascii-8bit

# Copyright 2024 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/utilities/store'

module OpenC3
  class StoreQueued
    # How often in seconds the store is updated
    UPDATE_INTERVAL = 2

    # Variable that holds the singleton instance
    @instance = nil

    # Mutex used to ensure that only one instance is created
    @@instance_mutex = Mutex.new

    # Thread used to post metrics across all classes
    @@update_thread = nil

    # Sleeper used to delay update thread
    @@update_sleeper = nil

    # Get the singleton instance
    def self.instance()
      return @instance if @instance

      @@instance_mutex.synchronize do
        @instance ||= self.new()
        return @instance
      end
    end

    def self.shutdown
      @@update_sleeper.cancel if @@update_sleeper
      OpenC3.kill_thread(self, @@update_thread) if @@update_thread
      @@update_thread = nil
    end

    def initialize()
      @store = store_instance()
      # Queue to hold the store requests
      @store_queue = Queue.new

      @@update_thread = OpenC3.safe_thread("StoreQueued") do
        store_thread_body()
      end
    end

    # Method to allow it be overriden in EphemeralStoreQueued
    def store_instance
      Store.instance
    end

    def store_thread_body
      @@update_sleeper = Sleeper.new
      while true
        start_time = Time.now

        unless @store_queue.empty?
          # Pipeline the requests to redis to improve performance
          @store.pipelined do
            while !@store_queue.empty?
              action = @store_queue.pop()
              @store.method_missing(action.message, *action.args, **action.kwargs, &action.block)
            end
          end
        end

        # Only check whether to update at a set interval
        run_time = Time.now - start_time
        sleep_time = UPDATE_INTERVAL - run_time
        sleep_time = 0 if sleep_time < 0
        break if @@update_sleeper.sleep(sleep_time)
      end
    end

    # Delegate all unknown class methods to delegate to the instance
    def self.method_missing(message, *args, **kwargs, &)
      self.instance.public_send(message, *args, **kwargs, &)
    end

    # Record the message for pipelining by the thread
    def method_missing(message, *args, **kwargs, &block)
      o = OpenStruct.new
      o.message = message
      o.args = args
      o.kwargs = kwargs
      o.block = block
      @store_queue.push(o)
    end
  end

  class EphemeralStoreQueued < StoreQueued
    def store_instance
      EphemeralStore.instance
    end
  end
end
