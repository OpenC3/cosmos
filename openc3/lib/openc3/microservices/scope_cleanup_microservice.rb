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

require 'openc3/models/scope_model'
require 'openc3/microservices/cleanup_microservice'

module OpenC3
  class ScopeCleanupMicroservice < CleanupMicroservice
    def run
      scope = ScopeModel.get_model(name: @scope)

      areas = [
        ["#{@scope}/text_logs", scope.text_log_retain_time],
        ["#{@scope}/tool_logs", scope.tool_log_retain_time],
      ]

      if @scope == 'DEFAULT'
        areas << ["NOSCOPE/text_logs", scope.text_log_retain_time]
        areas << ["NOSCOPE/tool_logs", scope.tool_log_retain_time]
      end

      cleanup(areas, scope.cleanup_poll_time)
    end
  end
end

OpenC3::CleanupMicroservice.run if __FILE__ == $0
