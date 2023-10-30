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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/activity_model'
require 'openc3/models/timeline_model'

module OpenC3
  module Api
    WHITELIST ||= []
    WHITELIST.concat([
      'list_timelines',
      'create_timeline',
      'get_timeline',
      'set_timeline_color',

    ])

    def list_timelines(scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', scope: scope, token: token)
      names = TimelineModel.names
      # names comes back as DEFAULT__TIMELINE__TEST so process
      # to only return the actual timeline name
      names.map! { |name| name.split('__')[-1] }.sort
    end

    def create_timeline(name, color: nil, updated_at: nil, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'script_run', scope: scope, token: token)
      model = TimelineModel.new(name: name, color: color, updated_at: updated_at, scope: scope)
      model.create()
      model.deploy()
    end

    def get_timeline(name, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', scope: scope, token: token)
      timeline = TimelineModel.get(name: name, scope: scope)
      timeline.as_json()
    end

    def set_timeline_color(name, color, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', scope: scope, token: token)
      timeline = TimelineModel.get(name: name, scope: scope)
      timeline.update_color(color: color)
      timeline.update()
    end

    def get_timeline_activities(name, start: nil, stop: nil, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', scope: scope, token: token)
      if start == nil and stop == nil
        return ActivityModel.all(name: name, scope: scope)
      else
        return ActivityModel.get(name: name, start: start, stop: stop, scope: scope)
      end
    end

    def create_timeline_activity(name, kind:, start:, stop:, data: {}, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'script_run', scope: scope, token: token)
      # Should match list in ActivityCreateDialog
      case kind.to_sym
      when :SCRIPT

      when :COMMAND
        # if data.keys.include?('cmd')
      when :RESERVE
        # No additional data necessary
      else
        raise "Unknown kind #{kind}. Must be one of #{kinds.join(", ")}"
      end

      model = ActivityModel.new(name: name, start: start, stop: stop, kind: kind, data: data, scope: scope)
      model.create()
    end
  end
end
