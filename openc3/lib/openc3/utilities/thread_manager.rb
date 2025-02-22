# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

module OpenC3
  class ThreadManager
    MONITOR_SLEEP_SECONDS = 0.25

    # Variable that holds the singleton instance
    @@instance = nil

    # Mutex used to ensure that only one instance of is created
    @@instance_mutex = Mutex.new

    # Get the singleton instance of ThreadManager
    def self.instance
      return @@instance if @@instance

      @@instance_mutex.synchronize do
        return @@instance if @@instance
        @@instance ||= self.new
        return @@instance
      end
    end

    def initialize
      @threads = []
      @shutdown_started = false
    end

    def register(thread, stop_object: nil, shutdown_object: nil)
      @threads << [thread, stop_object, shutdown_object]
    end

    def monitor
      while true
        @threads.each do |thread, _, _|
          if !thread.alive?
            return
          end
        end
        sleep(MONITOR_SLEEP_SECONDS)
      end
    end

    def shutdown
      @@instance_mutex.synchronize do
        return if @shutdown_started
        @shutdown_started = true
      end
      @threads.each do |thread, stop_object, shutdown_object|
        if thread.alive?
          if stop_object
            stop_object.stop
          end
          if shutdown_object
            shutdown_object.shutdown
          end
        end
      end
    end

    def join
      @threads.each do |thread, _, _|
        thread.join
      end
    end
  end
end