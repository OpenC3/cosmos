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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require "spec_helper"
require "openc3/utilities/thread_manager"

module OpenC3
  describe ThreadManager do
    before(:all) do
      ThreadManager.class_variable_set("@@instance", nil)
      @sleep_seconds = ThreadManager::MONITOR_SLEEP_SECONDS
      OpenC3.disable_warnings { ThreadManager::MONITOR_SLEEP_SECONDS = 0.01 }
    end
    after(:all) do
      OpenC3.disable_warnings { ThreadManager::MONITOR_SLEEP_SECONDS = @sleep_seconds }
      ThreadManager.class_variable_set("@@instance", nil)
    end

    it "monitors threads until 1 dies then stops and shutdowns" do
      @continue2 = true
      @continue3 = true
      stop_object = double("stop_object")
      expect(stop_object).to receive(:stop) do
        @continue2 = false
      end
      shutdown_object = double("shutdown_object")
      expect(shutdown_object).to receive(:shutdown) do
        @continue3 = false
      end
      thread1 = Thread.new { sleep 0.05 }
      thread2 = Thread.new do
        while @continue2
          sleep 0.01
        end
      end
      thread3 = Thread.new do
        while @continue3
          sleep 0.01
        end
      end
      ThreadManager.instance.register(thread1)
      ThreadManager.instance.register(thread2, stop_object: stop_object)
      ThreadManager.instance.register(thread3, shutdown_object: shutdown_object)
      manager_thread = Thread.new do
        ThreadManager.instance.monitor()
        ThreadManager.instance.shutdown()
      end
      thread1.join()
      sleep 0.01
      manager_thread.join()
      sleep 0.02 # Allow the other threads to finish
      expect(thread1.alive?).to be false
      expect(thread2.alive?).to be false
      expect(thread3.alive?).to be false
    end

    it "joins all the registered threads" do
      thread1 = Thread.new { sleep 0.01 }
      thread2 = Thread.new { sleep 0.1 }
      thread3 = Thread.new { sleep 0.05 }
      ThreadManager.instance.register(thread1)
      ThreadManager.instance.register(thread2)
      ThreadManager.instance.register(thread3)
      start = Time.now
      ThreadManager.instance.join()
      expect(Time.now - start).to be_within(0.01).of(0.1)
      expect(thread1.alive?).to be false
      expect(thread2.alive?).to be false
      expect(thread3.alive?).to be false
    end
  end
end
