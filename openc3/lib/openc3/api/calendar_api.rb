# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'date'
require 'openc3/models/timeline_model'
require 'openc3/models/activity_model'
require 'openc3/topics/timeline_topic'

module OpenC3
  module Api
    # NOTE: These methods are intentionally NOT added to WHITELIST. Their signatures
    # match openc3/lib/openc3/script/calendar.rb (no manual:/token: kwargs), so they
    # cannot be dispatched via JSON-RPC (which auto-injects manual/token from headers).
    # The script-side calendar methods reach the server through the timeline/activity
    # HTTP controllers, which call these helpers after performing their own
    # authorization.

    # Returns an array of all timelines for the given scope.
    def list_timelines(scope: $openc3_scope)
      ret = []
      TimelineModel.all.each do |timeline, value|
        if scope == timeline.split('__')[0]
          ret << value
        end
      end
      ret
    end

    # Creates a new timeline and deploys its microservice.
    # @return [Hash] the created timeline as a hash
    def create_timeline(name, color: nil, scope: $openc3_scope)
      model = TimelineModel.new(name: name, color: color, scope: scope)
      model.create()
      model.deploy()
      model.as_json()
    end

    # @return [Hash, nil] the timeline as a hash, or nil if not found
    def get_timeline(name, scope: $openc3_scope)
      model = TimelineModel.get(name: name, scope: scope)
      return nil if model.nil?
      model.as_json()
    end

    # Updates the color of an existing timeline.
    # @return [Hash, nil] the updated timeline as a hash, or nil if not found
    def set_timeline_color(name, color, scope: $openc3_scope)
      model = TimelineModel.get(name: name, scope: scope)
      return nil if model.nil?
      model.color = color
      model.update()
      model.notify(kind: 'updated')
      model.as_json()
    end

    # Updates the execute flag of an existing timeline.
    # @return [Hash, nil] the updated timeline as a hash, or nil if not found
    def set_timeline_execute(name, enable, scope: $openc3_scope)
      model = TimelineModel.get(name: name, scope: scope)
      return nil if model.nil?
      model.execute = enable
      model.update()
      model.notify(kind: 'updated')
      model.as_json()
    end

    # Deletes a timeline (and optionally all of its activities when force is true).
    # @return [Hash, nil] {'name' => name}, or nil if not found
    def delete_timeline(name, force: false, scope: $openc3_scope)
      model = TimelineModel.get(name: name, scope: scope)
      return nil if model.nil?
      TimelineModel.delete(name: name, scope: scope, force: force)
      model.undeploy()
      model.notify(kind: 'deleted')
      { 'name' => name }
    end

    # Creates a new activity on the specified timeline.
    # username is read from data['username'] if present and is used for the audit event.
    # @return [Hash] the created activity as a hash
    def create_timeline_activity(name, kind:, start:, stop:, data: {}, recurring: nil, scope: $openc3_scope)
      data ||= {}
      hash = {
        kind: kind,
        start: _cal_to_epoch(start),
        stop: _cal_to_epoch(stop),
        data: data,
      }
      if recurring
        recurring = recurring.dup
        if recurring['end']
          recurring['end'] = _cal_to_epoch(recurring['end'])
        end
        hash[:recurring] = recurring
      end
      model = ActivityModel.from_json(hash, name: name, scope: scope)
      model.create(username: data['username'])
      model.as_json()
    end

    # Updates an existing activity on the specified timeline.
    # @return [Hash, nil] the updated activity as a hash, or nil if not found
    def update_timeline_activity(name, id:, kind:, start:, stop:, uuid:, data: {}, scope: $openc3_scope)
      data ||= {}
      model = ActivityModel.score(name: name, score: id.to_i, uuid: uuid, scope: scope)
      return nil if model.nil?
      model.update(
        start: _cal_to_epoch(start),
        stop: _cal_to_epoch(stop),
        kind: kind,
        data: data,
        username: data['username'],
      )
      model.as_json()
    end

    # @return [Hash, nil] the activity as a hash, or nil if not found
    def get_timeline_activity(name, start, uuid, scope: $openc3_scope)
      model = ActivityModel.score(name: name, score: start.to_i, uuid: uuid, scope: scope)
      return nil if model.nil?
      model.as_json()
    end

    # Returns activities on the timeline in the given window.
    # When start/stop are nil, defaults to a window of [now - 7 days, now + 7 days].
    # When limit is nil, defaults to one event per minute over the window.
    # @return [Array<Hash>] the matching activities
    def get_timeline_activities(name, start: nil, stop: nil, limit: nil, scope: $openc3_scope)
      now = DateTime.now.new_offset(0)
      start_score = start.nil? ? (now - 7).strftime('%s').to_i : _cal_to_epoch(start)
      stop_score = stop.nil? ? (now + 7).strftime('%s').to_i : _cal_to_epoch(stop)
      limit ||= ((stop_score - start_score) / 60).to_i
      ActivityModel.get(name: name, scope: scope, start: start_score, stop: stop_score, limit: limit)
    end

    # Removes an activity (or all members of its recurring group when recurring is truthy).
    # @return [Integer] number of activities removed (0 indicates not found)
    def delete_timeline_activity(name, start, uuid, recurring: nil, scope: $openc3_scope)
      ActivityModel.destroy(name: name, scope: scope, score: start.to_i, uuid: uuid, recurring: recurring)
    end

    # @return [Integer] count of activities on the timeline
    def count_timeline_activities(name, scope: $openc3_scope)
      ActivityModel.count(name: name, scope: scope)
    end

    # Commits an event to an existing activity.
    # @return [Hash, nil] the activity as a hash, or nil if not found
    def commit_timeline_activity(name, start, uuid, status:, message: nil, scope: $openc3_scope)
      model = ActivityModel.score(name: name, score: start.to_i, uuid: uuid, scope: scope)
      return nil if model.nil?
      model.commit(status: status, message: message)
      model.as_json()
    end

    # Convert a value to an epoch integer. Accepts Integer/Numeric (treated as already-epoch),
    # numeric strings, and ISO-style date/time strings or DateTime/Time objects.
    def _cal_to_epoch(value)
      case value
      when Integer
        value
      when Numeric
        value.to_i
      when DateTime, Time, Date
        value.to_datetime.strftime('%s').to_i
      else
        s = value.to_s
        return s.to_i if s.match?(/\A-?\d+\z/)
        DateTime.parse(s).strftime('%s').to_i
      end
    end
  end
end
