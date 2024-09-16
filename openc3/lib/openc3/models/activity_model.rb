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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# https://www.rubydoc.info/gems/redis/Redis/Commands/SortedSets

require 'openc3/models/model'
require 'openc3/topics/timeline_topic'
require 'securerandom'

module OpenC3
  class ActivityError < StandardError; end
  class ActivityInputError < ActivityError; end
  class ActivityOverlapError < ActivityError; end

  class ActivityModel < Model
    MAX_DURATION = Time::SEC_PER_DAY
    PRIMARY_KEY = '__openc3_timelines'.freeze # MUST be equal to `TimelineModel::PRIMARY_KEY` minus the leading __
    # See run_activity(activity) in openc3/lib/openc3/microservices/timeline_microservice.rb
    VALID_KINDS = %w(command script reserve expire)

    # Called via the microservice this gets the previous 00:00:15 to 01:01:00. This should allow
    # for a small buffer around the timeline to make sure the schedule doesn't get stale.
    # 00:00:15 was selected as the schedule queue used in the microservice has round robin array
    # with 15 slots to make sure we don't miss a planned task.
    # @return [Array|nil] Array of the next hour in the sorted set
    def self.activities(name:, scope:)
      now = Time.now.to_f
      start_score = now - 15
      stop_score = (now + 3660)
      array = Store.zrangebyscore("#{scope}#{PRIMARY_KEY}__#{name}", start_score, stop_score)
      return array.map { |value| ActivityModel.from_json(value, name: name, scope: scope) }
    end

    # @return [Array|nil] Array up to 100 of this model or empty array if name not found under primary_key
    def self.get(name:, start:, stop:, scope:, limit: 100)
      if start > stop
        raise ActivityInputError.new "start: #{start} must be <= stop: #{stop}"
      end
      array = Store.zrangebyscore("#{scope}#{PRIMARY_KEY}__#{name}", start, stop, :limit => [0, limit])
      return array.map { |value| JSON.parse(value, :allow_nan => true, :create_additions => true) }
    end

    # @return [Array<Hash>] Array up to the limit of the models (as Hash objects) stored under the primary key
    def self.all(name:, scope:, limit: 100)
      array = Store.zrange("#{scope}#{PRIMARY_KEY}__#{name}", 0, -1, :limit => [0, limit])
      return array.map { |value| JSON.parse(value, :allow_nan => true, :create_additions => true) }
    end

    # @return [String|nil] String of the saved json or nil if score not found under primary_key
    def self.score(name:, score:, scope:)
      value = Store.zrangebyscore("#{scope}#{PRIMARY_KEY}__#{name}", score, score, :limit => [0, 1]).first
      if value
        return ActivityModel.from_json(value, name: name, scope: scope)
      end
      return nil
    end

    # @return [Integer] count of the members stored under the primary key
    def self.count(name:, scope:)
      return Store.zcard("#{scope}#{PRIMARY_KEY}__#{name}")
    end

    # Remove one member from a sorted set.
    # @return [Integer] count of the members removed
    def self.destroy(name:, scope:, score:, uuid: nil, recurring: nil)
      result = 0

      # Delete all recurring activities
      if recurring
        activity = self.score(name: name, score: score, scope: scope)
        if activity and activity.recurring['end'] and activity.recurring['uuid']
          uuid = activity.recurring['uuid']
          json = Store.zrangebyscore("#{scope}#{PRIMARY_KEY}__#{name}", activity.recurring['start'], activity.recurring['end'])
          parsed = json.map { |value| ActivityModel.from_json(value, name: name, scope: scope) }
          parsed.each_with_index do |value, index|
            if value.recurring['uuid'] == uuid
              Store.zrem("#{scope}#{PRIMARY_KEY}__#{name}", json[index])
            end
          end
        end
      end

      # First find all the activities at the score
      json = Store.zrangebyscore("#{scope}#{PRIMARY_KEY}__#{name}", score, score, :limit => [0, 100])
      parsed = json.map { |value| JSON.parse(value, :allow_nan => true, :create_additions => true) }
      parsed.each_with_index do |value, index|
        if uuid
          # If the uuid is given then only delete activities that match the uuid
          if value['uuid'] == uuid
            result = Store.zrem("#{scope}#{PRIMARY_KEY}__#{name}", json[index])
            break
          end
        else
          # If the uuid is not given (backwards compatibility) then delete all activities
          # at the score that do NOT have a uuid
          next if value['uuid']
          result = Store.zrem("#{scope}#{PRIMARY_KEY}__#{name}", json[index])
        end
      end

      notification = {
        # start / stop to match SortedModel
        'data' => JSON.generate({'start' => score}),
        'kind' => 'deleted',
        'type' => 'activity',
        'timeline' => name
      }
      TimelineTopic.write_activity(notification, scope: scope)
      return result
    end

    # Remove members from min to max of the sorted set.
    # @return [Integer] count of the members removed
    def self.range_destroy(name:, scope:, min:, max:)
      result = Store.zremrangebyscore("#{scope}#{PRIMARY_KEY}__#{name}", min, max)
      notification = {
        # start / stop to match SortedModel
        'data' => JSON.generate({'start' => min, 'stop' => max}),
        'kind' => 'deleted',
        'type' => 'activity',
        'timeline' => name
      }
      TimelineTopic.write_activity(notification, scope: scope)
      return result
    end

    # @return [ActivityModel] Model generated from the passed JSON
    def self.from_json(json, name:, scope:)
      json = JSON.parse(json, :allow_nan => true, :create_additions => true) if String === json
      raise "json data is nil" if json.nil?
      self.new(**json.transform_keys(&:to_sym), name: name, scope: scope)
    end

    attr_reader :start, :stop, :kind, :data, :fulfillment, :uuid, :events, :recurring

    def initialize(
      name:, # part of Model
      start:,
      stop:,
      kind:,
      data:,
      scope:, # part of Model
      updated_at: 0, # part of Model
      fulfillment: nil,
      uuid: nil,
      events: nil,
      recurring: {}
    )
      super("#{scope}#{PRIMARY_KEY}__#{name}", name: name, scope: scope)
      # Validate everything that isn't already in Model
      set_input(
        start: start,
        stop: stop,
        kind: kind,
        data: data,
        fulfillment: fulfillment,
        uuid: uuid,
        events: events,
        recurring: recurring,
      )
      @updated_at = updated_at
    end

    # validate_time searches from the current activity @stop (exclusive because we allow overlap of stop with start)
    # back through @start - MAX_DURATION. The method is trying to validate that this new activity does not
    # overlap with anything else. The reason we search back past @start through MAX_DURATION is because we
    # need to return all the activities that may start before us and verify that we don't overlap them.
    # Activities are only inserted by @start time so we need to go back to verify we don't overlap existing @stop.
    # Note: Score is the Seconds since the Unix Epoch: (%s) Number of seconds since 1970-01-01 00:00:00 UTC.
    # zrange rev byscore finds activities from in reverse order so the first task is the closest task to the current score.
    # In this case a parameter ignore_score allows the request to ignore that time and skip to the next time
    # but if nothing is found in the time range we can return nil.
    #
    # @param [Integer] ignore_score - should be nil unless you want to ignore a time when doing an update
    def validate_time(start, stop, ignore_score: nil)
      # Adding a '(' makes the max value exclusive
      array = Store.zrevrangebyscore(@primary_key, "(#{stop}", start - MAX_DURATION)
      array.each do |value|
        activity = JSON.parse(value, :allow_nan => true, :create_additions => true)
        if ignore_score == activity['start']
          next
        elsif activity['stop'] > start
          return activity['start']
        else
          return nil
        end
      end
      return nil
    end

    # validate the input to the rules we have created for timelines.
    # - A task's start MUST NOT be in the past.
    # - A task's start MUST be before the stop.
    # - A task CAN NOT be longer than MAX_DURATION (86400) in seconds.
    # - A task MUST have a kind.
    # - A task MUST have a data object/hash.
    def validate_input(start:, stop:, kind:, data:)
      begin
        DateTime.strptime(start.to_s, '%s')
        DateTime.strptime(stop.to_s, '%s')
      rescue Date::Error
        raise ActivityInputError.new "start and stop must be seconds: #{start}, #{stop}"
      end
      now_f = Time.now.to_f
      begin
        duration = stop - start
      rescue NoMethodError
        raise ActivityInputError.new "start and stop must be seconds: #{start}, #{stop}"
      end
      if now_f >= start and kind != 'expire'
        raise ActivityInputError.new "activity must be in the future, current_time: #{now_f} vs #{start}"
      elsif duration >= MAX_DURATION and kind != 'expire'
        raise ActivityInputError.new "activity can not be longer than #{MAX_DURATION} seconds"
      elsif duration <= 0
        raise ActivityInputError.new "start: #{start} must be before stop: #{stop}"
      elsif !VALID_KINDS.include?(kind)
        raise ActivityInputError.new "unknown kind: #{kind}, must be one of #{VALID_KINDS.join(', ')}"
      elsif data.nil?
        raise ActivityInputError.new "data must not be nil: #{data}"
      elsif data.is_a?(Hash) == false
        raise ActivityInputError.new "data must be a json object/hash: #{data}"
      end
    end

    # Set the values of the instance, @start, @kind, @data, @events...
    def set_input(start:, stop:, kind: nil, data: nil, uuid: nil, events: nil, fulfillment: nil, recurring: nil)
      kind = kind.to_s.downcase
      validate_input(start: start, stop: stop, kind: kind, data: data)
      @start = start
      @stop = stop
      @fulfillment = fulfillment.nil? ? false : fulfillment
      @kind = kind
      @data = data.nil? ? @data : data
      @uuid = uuid.nil? ? SecureRandom.uuid : uuid
      @events = events.nil? ? Array.new : events
      @recurring = recurring.nil? ? @recurring : recurring
    end

    # Update the Redis hash at primary_key and set the score equal to the start Epoch time
    # the member is set to the JSON generated via calling as_json
    def create(overlap: true)
      if @recurring['end'] and @recurring['frequency'] and @recurring['span']
        # First validate the initial recurring activity ... all others are just offsets
        validate_input(start: @start, stop: @stop, kind: @kind, data: @data)

        # Create a uuid for deleting related recurring in the future
        @recurring['uuid'] = SecureRandom.uuid
        @recurring['start'] = @start
        duration = @stop - @start
        recurrence = 0
        case @recurring['span']
        when 'minutes'
          recurrence = @recurring['frequency'].to_i * 60
        when 'hours'
          recurrence = @recurring['frequency'].to_i * 3600
        when 'days'
          recurrence = @recurring['frequency'].to_i * 86400
        end

        unless overlap
          # Get all the existing events in the recurring time range as well as those before
          # the start of the recurring time range to ensure we don't start inside an existing event
          existing = Store.zrevrangebyscore(@primary_key, @recurring['end'] - 1, @recurring['start'] - MAX_DURATION)
          existing.map! {|value| JSON.parse(value, :allow_nan => true, :create_additions => true) }
        end
        last_stop = nil

        # Update @updated_at and add an event assuming it all completes ok
        @updated_at = Time.now.to_nsec_from_epoch
        add_event(status: 'created')

        Store.multi do |multi|
          (@start..@recurring['end']).step(recurrence).each do |start_time|
            @start = start_time
            @stop = start_time + duration

            if last_stop and @start < last_stop
              @events.pop # Remove previously created event
              raise ActivityOverlapError.new "Recurring activity overlap. Increase recurrence delta or decrease activity duration."
            end
            unless overlap
              existing.each do |value|
                if (@start >= value['start'] and @start < value['stop']) ||
                  (@stop > value['start'] and @stop <= value['stop'])
                  @events.pop # Remove previously created event
                  raise ActivityOverlapError.new "activity overlaps existing at #{value['start']}"
                end
              end
            end
            multi.zadd(@primary_key, @start, JSON.generate(self.as_json(:allow_nan => true)))
            last_stop = @stop
          end
        end
        notify(kind: 'created')
      else
        validate_input(start: @start, stop: @stop, kind: @kind, data: @data)
        unless overlap
          # If we don't allow overlap we need to validate the time
          collision = validate_time(@start, @stop)
          unless collision.nil?
            raise ActivityOverlapError.new "activity overlaps existing at #{collision}"
          end
        end
        @updated_at = Time.now.to_nsec_from_epoch
        add_event(status: 'created')
        Store.zadd(@primary_key, @start, JSON.generate(self.as_json(:allow_nan => true)))
        notify(kind: 'created')
      end
    end

    # Update the Redis hash at primary_key and remove the current activity at the current score
    # and update the score to the new score equal to the start Epoch time this uses a multi
    # to execute both the remove and create.
    def update(start:, stop:, kind:, data:, overlap: true)
      array = Store.zrangebyscore(@primary_key, @start, @start)
      if array.length == 0
        raise ActivityError.new "failed to find activity at: #{@start}"
      end

      old_start = @start
      unless overlap
        # If we don't allow overlap we need to validate the time
        collision = validate_time(start, stop, ignore_score: old_start)
        unless collision.nil?
          raise ActivityOverlapError.new "failed to update #{old_start}, no activities can overlap, collision: #{collision}"
        end
      end
      set_input(start: start, stop: stop, kind: kind, data: data, events: @events)
      @updated_at = Time.now.to_nsec_from_epoch

      add_event(status: 'updated')
      json = Store.zrangebyscore(@primary_key, old_start, old_start)
      parsed = json.map { |value| JSON.parse(value, :allow_nan => true, :create_additions => true) }
      parsed.each_with_index do |value, index|
        if value['uuid'] == @uuid
          Store.multi do |multi|
            multi.zrem(@primary_key, json[index])
            multi.zadd(@primary_key, @start, JSON.generate(self.as_json(:allow_nan => true)))
          end
        end
      end
      notify(kind: 'updated', extra: old_start)
      return @start
    end

    # commit will make an event and save the object to the redis database
    # @param [String] status - the event status such as "complete" or "failed"
    # @param [String] message - an optional message to include in the event
    def commit(status:, message: nil, fulfillment: nil)
      event = {
        'time' => Time.now.to_i,
        'event' => status,
        'commit' => true
      }
      event['message'] = message unless message.nil?
      @fulfillment = fulfillment.nil? ? @fulfillment : fulfillment
      @events << event

      json = Store.zrangebyscore(@primary_key, @start, @start)
      parsed = json.map { |value| JSON.parse(value, :allow_nan => true, :create_additions => true) }
      parsed.each_with_index do |value, index|
        if value['uuid'] == @uuid
          Store.multi do |multi|
            multi.zrem(@primary_key, json[index])
            multi.zadd(@primary_key, @start, JSON.generate(self.as_json(:allow_nan => true)))
          end
        end
      end
      notify(kind: 'event')
    end

    # add_event will make an event. This will NOT save the object to the redis database
    # @param [String] status - the event status such as "queued" or "updated" or "created"
    def add_event(status:)
      event = {
        'time' => Time.now.to_i,
        'event' => status
      }
      @events << event
    end

    # update the redis stream / timeline topic that something has changed
    def notify(kind:, extra: nil)
      notification = {
        'data' => JSON.generate(as_json(:allow_nan => true)),
        'kind' => kind,
        'type' => 'activity',
        'timeline' => @name
      }
      notification['extra'] = extra unless extra.nil?
      begin
        TimelineTopic.write_activity(notification, scope: @scope)
      rescue StandardError => e
        raise ActivityError.new "Failed to write to stream: #{notification}, #{e}"
      end
    end

    # @return [Hash] generated from the ActivityModel
    def as_json(*a)
      {
        'name' => @name,
        'updated_at' => @updated_at,
        'start' => @start,
        'stop' => @stop,
        'kind' => @kind,
        'data' => @data.as_json(*a),
        'scope' => @scope,
        'fulfillment' => @fulfillment,
        'uuid' => @uuid,
        'events' => @events,
        'recurring' => @recurring.as_json(*a)
      }
    end
  end
end
