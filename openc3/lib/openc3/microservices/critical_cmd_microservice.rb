# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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

require 'openc3/utilities/logger'
require 'openc3/microservices/microservice'
begin
  require 'openc3-enterprise/models/critical_cmd_model'
rescue LoadError
  module OpenC3
    class CriticalCmdModel
      def self.get_all_models(scope:)
        []
      end
    end
  end
end

module OpenC3
  class CriticalCmdMicroservice < Microservice
    SLEEP_PERIOD_SECONDS = 3 # Check every 3 seconds
    TWENTY_FOUR_HOURS_NSEC = 24 * 60 * 60 * 1_000_000_000

    def run
      @run_sleeper = Sleeper.new
      critical_cmd_waiting = false
      while true
        models = CriticalCmdModel.get_all_models(scope: @scope)
        pre_waiting = critical_cmd_waiting
        critical_cmd_waiting = false
        old_time = Time.now.to_nsec_from_epoch - TWENTY_FOUR_HOURS_NSEC
        models.each do |name, model|
          # Cleanup older than 24 hours
          if model.updated_at < old_time
            model.destroy
          elsif model.status == 'WAITING'
            # Tell the frontend about critical commands pending
            critical_cmd_waiting = true
            data = Logger.build_log_data(Logger::INFO_LEVEL, "Critical Cmd Waiting", user: model.username, type: Logger::EPHEMERAL, other: {"uuid" => model.name, "cmd_string" => model.cmd_hash["cmd_string"]})
            EphemeralStoreQueued.write_topic("#{scope}__openc3_ephemeral_messages", data, '*', 100)
          end
        end
        if pre_waiting and not critical_cmd_waiting
          data = Logger.build_log_data(Logger::INFO_LEVEL, "All Critical Cmds Handled", type: Logger::EPHEMERAL)
          EphemeralStoreQueued.write_topic("#{scope}__openc3_ephemeral_messages", data, '*', 100)
        end
        @count += 1
        break if @cancel_thread
        break if @run_sleeper.sleep(SLEEP_PERIOD_SECONDS)
      end
    end

    def shutdown
      @run_sleeper.cancel if @run_sleeper
      super()
    end
  end
end

OpenC3::CriticalCmdMicroservice.run if __FILE__ == $0
