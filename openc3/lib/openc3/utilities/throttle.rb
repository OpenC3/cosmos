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

# Usage:
# throttle = OpenC3::Throttle.new(50.0) # Use max 50% cpu for work
#
# throttle.reset # Necessary if there are large periods of idle between hard work
# 1000.times do
#   throttle.start
#   # Do one iteration of cpu itensive work here
#   # complete will sleep if necessary to not use too much CPU
#   throttle.complete
# end

module OpenC3
  class Throttle
    MIN_SLEEP_SECONDS = 0.001
    MAX_SLEEP_SECONDS = 0.05

    # @param max_cpu_utilization [Float] 0.0-100.0
    def initialize(max_cpu_utilization)
      @max_cpu_utilization = Float(max_cpu_utilization)
      raise ArgumentError "max_cpu_utilization must be between 0.0 and 100.0" if @max_cpu_utilization > 100.0 or @max_cpu_utilization < 0.0
      reset()
    end

    def reset
      @work_start_time = nil
      @total_work_time = 0
      @reset_time = Time.now
    end

    def start
      @work_start_time = Time.now
    end

    def complete
      duration = Time.now - @work_start_time
      @total_work_time += duration
      total_time = Time.now - @reset_time
      if total_time > 0
        cpu_utilization = @total_work_time / total_time
        if cpu_utilization > @max_cpu_utilization
          # Need to throttle
          delta = cpu_utilization - @max_cpu_utilization
          sleep_time = delta * total_time
          if sleep_time > MIN_SLEEP_SECONDS
            sleep_time = MAX_SLEEP_SECONDS if sleep_time > MAX_SLEEP_SECONDS
            sleep(MAX_SLEEP_SECONDS)
          end
        end
      end
    end
  end
end