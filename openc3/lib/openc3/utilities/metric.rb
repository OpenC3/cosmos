# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc.
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
#
# Note: This file has been completely reimplemented post version 5.3.0

require 'openc3/models/metric_model'

module OpenC3
  class Metric
    # The update interval. How often in seconds metrics are updated by this process
    UPDATE_INTERVAL = 5

    # Mutex protecting class variables
    @@mutex = Mutex.new

    # Array of instances used to keep track of metrics
    @@instances = []

    # Thread used to post metrics across all classes
    @@update_thread = nil

    # Sleeper used to delay update thread
    @@update_sleeper = nil

    # Objects with a generate method to be called on each metric cycle (to generate metrics)
    @@update_generators = []

    attr_reader :microservice
    attr_reader :scope
    attr_reader :data
    attr_reader :mutex

    def initialize(microservice:, scope:)
      @scope = scope
      @microservice = microservice
      @data = {}
      @mutex = Mutex.new

      # Always make sure there is a update thread
      @@mutex.synchronize do
        @@instances << self

        unless @@update_thread
          @@update_thread = OpenC3.safe_thread("Metrics") do
            update_thread_body()
          end
        end
      end
    end

    def set(name:, value:, type: nil, unit: nil, help: nil, labels: nil, time_ms: nil)
      @mutex.synchronize do
        @data[name] ||= {}
        @data[name]['value'] = value
        @data[name]['type'] = type if type
        @data[name]['unit'] = unit if unit
        @data[name]['help'] = help if help
        @data[name]['labels'] = labels if labels
        @data[name]['time_ms'] = time_ms if time_ms
      end
    end

    def set_multiple(data)
      @mutex.synchronize do
        @data.merge!(data)
      end
    end

    def update_thread_body
      @@update_sleeper = Sleeper.new
      while true
        start_time = Time.now

        @@mutex.synchronize do
          @@update_generators.each do |generator|
            generator.generate(@@instances[0])
          end

          @@instances.each do |instance|
            instance.mutex.synchronize do
              json = {}
              json['name'] = instance.microservice
              values = instance.data
              json['values'] = values
              MetricModel.set(json, scope: instance.scope) if values.length > 0
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

    def shutdown
      @@mutex.synchronize do
        @@instances.delete(self)
        if @@instances.length <= 0
          @@update_sleeper.cancel if @@update_sleeper
          OpenC3.kill_thread(self, @@update_thread) if @@update_thread
          @@update_thread = nil
        end
      end
    end

    def graceful_kill
    end

    def self.add_update_generator(object)
      @@update_generators << object
    end
  end
end

begin
  require 'openc3-enterprise/utilities/metric'
rescue LoadError
  # Open Source Edition - Do nothing here
end
