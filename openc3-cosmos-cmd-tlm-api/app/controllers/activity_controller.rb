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

require 'openc3/topics/timeline_topic'
require 'openc3/models/activity_model'

class ActivityController < ApplicationController
  NOT_FOUND = 'not found'

  def initialize
    super()
    @model_class = OpenC3::ActivityModel
  end

  # Returns an array/list of activities in json. With optional start_time and end_time parameters
  #
  # name [String] the timeline name, `system42`
  # scope [String] the scope of the timeline, `TEST`
  # start [String] (optional) The start time of the search window for timeline to return. Recommend in ISO format, `2031-04-16T01:02:00+00:00`.
  # stop [String] (optional) The stop time of the search window for timeline to return. Recommend in ISO format, `2031-04-16T01:02:00+00:00`.
  # @return [String] the array of activities converted into json format.
  def index
    return unless authorization('system')
    now = DateTime.now.new_offset(0) # Convert time to UTC
    begin
      start = params[:start].nil? ? (now - 7) : DateTime.parse(params[:start]) # minus 7 days
      stop = params[:stop].nil? ? (now + 7) : DateTime.parse(params[:stop]) # plus 7 days
      start = start.strftime('%s').to_i
      stop = stop.strftime('%s').to_i
      if params[:limit]
        limit = params[:limit]
      else
        limit = ((stop - start) / 60).to_i # 1 event every minute ... shouldn't ever be more than this!
      end
      model = @model_class.get(name: params[:name], scope: params[:scope], start: start, stop: stop, limit: limit)
      render json: model.as_json()
    rescue ArgumentError => e
      log_error(e)
      render json: { status: 'error', message: 'Invalid date provided. Recommend ISO format' }, status: 400
    rescue StandardError => e # includes ActivityInputError
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 400
    end
  end

  # Returns an object/hash of activity in json.
  #
  # name [String] the timeline name, `system42`
  # scope [String] the scope of the timeline, `TEST`
  # json [String] The json of the activity (see below)
  # @return [String] the activity converted into json format
  # Request Headers
  # ```json
  #  {
  #    "Authorization": "token/password",
  #    "Content-Type": "application/json"
  #  }
  # ```
  # Request Post Body
  # ```json
  #  {
  #    "start": "2031-04-16T01:02:00",
  #    "stop": "2031-04-16T01:02:00",
  #    "kind": "cmd",
  #    "data": {"cmd"=>"INST ABORT"}
  #  }
  # ```
  def create
    return unless authorization('script_run')
    begin
      hash = params.to_unsafe_h.slice(:start, :stop, :kind, :data, :recurring).to_h
      hash['data'] ||= {}
      hash['data']['username'] = username()
      if hash['start'].nil? || hash['stop'].nil?
        raise ArgumentError.new 'post body must contain start and stop'
      end
      hash['start'] = DateTime.parse(hash['start']).strftime('%s').to_i
      hash['stop'] = DateTime.parse(hash['stop']).strftime('%s').to_i
      if hash['recurring'] and hash['recurring']['end']
        hash['recurring']['end'] = DateTime.parse(hash['recurring']['end']).strftime('%s').to_i
      end
      model = @model_class.from_json(hash.symbolize_keys, name: params[:name], scope: params[:scope])
      model.create()
      OpenC3::Logger.info(
        "Activity created: #{params[:name]} #{hash}",
        scope: params[:scope],
        user: hash['data']['username']
      )
      render json: model.as_json(), status: 201
    rescue ArgumentError, TypeError => e
      log_error(e)
      render json: { status: 'error', message: "Invalid input: #{hash}", type: e.class, e: e.to_s }, status: 400
    rescue StandardError => e # includes ActivityInputError
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: 400
    rescue OpenC3::ActivityOverlapError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: 409
    rescue OpenC3::ActivityError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: 418
    end
  end

  # Returns an object/hash the contains `count` as a key in json.
  #
  # name [String] the timeline name, `system42`
  # scope [String] the scope of the timeline, `TEST`
  # @return [String] the object/hash converted into json format
  # Request Headers
  # ```json
  #  {
  #    "Authorization": "token/password",
  #    "Content-Type": "application/json"
  #  }
  # ```
  def count
    return unless authorization('system')
    begin
      count = @model_class.count(name: params[:name], scope: params[:scope])
      render json: { name: params[:name], count: count }
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: 400
    end
  end

  # Returns an object/hash of a single activity in json.
  #
  # name [String] the timeline name, `system42`
  # scope [String] the scope of the timeline, `TEST`
  # id [String] the start/id of the activity, `1620248449`
  # uuid [String] the uuid of the activity, `e8776b54-4c71-41c3-b2fd-309513cf85cf`
  # @return [String] the activity as a object/hash converted into json format
  # Request Headers
  # ```json
  #  {
  #    "Authorization": "token/password",
  #    "Content-Type": "application/json"
  #  }
  # ```
  def show
    return unless authorization('system')
    begin
      model = @model_class.score(name: params[:name], score: params[:id].to_i, uuid: params[:uuid], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
      else
        render json: model.as_json()
      end
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: 400
    end
  end

  # Adds an event to the object/hash of a single activity in json.
  #
  # name [String] the timeline name, `system42`
  # scope [String] the scope of the timeline, `TEST`
  # id [String] the score/id of the activity, `1620248449`
  # json [String] The json of the event (see #event_model)
  # @return [String] the activity as a object/hash converted into json format
  # Request Headers
  # ```json
  #  {
  #    "Authorization": "token/password",
  #    "Content-Type": "application/json"
  #  }
  # ```
  # Request Post Body
  # ```json
  #  {
  #    "status": "system42-ready",
  #    "message": "script was completed"
  #  }
  # ```
  def event
    return unless authorization('script_run')
    model = @model_class.score(name: params[:name], score: params[:id].to_i, uuid: params[:uuid], scope: params[:scope])
    if model.nil?
      render json: { status: 'error', message: NOT_FOUND }, status: 404
      return
    end
    begin
      hash = params.to_unsafe_h.slice(:status, :message).to_h
      model.commit(status: hash['status'], message: hash['message'])
      OpenC3::Logger.info(
        "Event created for activity: #{params[:name]} #{hash}",
        scope: params[:scope],
        user: username()
      )
      render json: model.as_json()
    rescue OpenC3::ActivityError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: 418
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: 400
    end
  end

  # Update and returns an object/hash of a single activity in json.
  #
  # name [String] the timeline name, `system42`
  # scope [String] the scope of the timeline, `TEST`
  # id [String] the score or id of the activity, `1620248449`
  # json [String] The json of the event (see #activity_model)
  # @return [String] the activity as a object/hash converted into json format
  # Request Headers
  # ```json
  #  {
  #    "Authorization": "token/password",
  #    "Content-Type": "application/json"
  #  }
  # ```
  # Request Post Body
  # ```json
  #  {
  #    "start": "2031-04-16T01:02:00+00:00",
  #    "stop": "2031-04-16T01:02:00+00:00",
  #    "kind": "cmd",
  #    "data": {"cmd"=>"INST ABORT"}
  #  }
  # ```
  def update
    return unless authorization('script_run')
    model = @model_class.score(name: params[:name], score: params[:id].to_i, uuid: params[:uuid], scope: params[:scope])
    if model.nil?
      render json: { status: 'error', message: NOT_FOUND }, status: 404
      return
    end
    begin
      hash = params.to_unsafe_h.slice(:start, :stop, :kind, :data).to_h
      hash['data'] ||= {}
      hash['data']['username'] = username()
      hash['start'] = DateTime.parse(hash['start']).strftime('%s').to_i
      hash['stop'] = DateTime.parse(hash['stop']).strftime('%s').to_i
      model.update(start: hash['start'], stop: hash['stop'], kind: hash['kind'], data: hash['data'])
      OpenC3::Logger.info(
        "Activity updated: #{params[:name]} #{hash}",
        scope: params[:scope],
        user: hash['data']['username']
      )
      render json: model.as_json()
    rescue ArgumentError, TypeError => e
      log_error(e)
      render json: { status: 'error', message: "Invalid input: #{hash}", type: e.class, e: e.to_s }, status: 400
    rescue OpenC3::ActivityOverlapError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: 409
    rescue OpenC3::ActivityError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: 418
    rescue StandardError => e # includes OpenC3::ActivityInputError
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: 400
    end
  end

  # Removes an activity activity by score/id.
  #
  # name [String] the timeline name, `system42`
  # scope [String] the scope of the timeline, `TEST`
  # id [String] the score or id of the activity, `1620248449`
  # uuid [String] the uuid of the activity, `e8776b54-4c71-41c3-b2fd-309513cf85cf`
  # @return [String] object/hash converted into json format but with a 200 status code
  # Request Headers
  # ```json
  #  {
  #    "Authorization": "token/password",
  #    "Content-Type": "application/json"
  #  }
  # ```
  def destroy
    return unless authorization('script_run')
    begin
      ret = @model_class.destroy(name: params[:name], scope: params[:scope], score: params[:id].to_i, uuid: params[:uuid], recurring: params[:recurring])
      if ret == 0
        render json: { status: 'error', message: NOT_FOUND }, status: 404
      else
        OpenC3::Logger.info(
          "Activity destroyed name: #{params[:name]} id:#{params[:id]} recurring:#{params[:recurring]}",
          scope: params[:scope],
          user: username()
        )
        render json: { status: ret }
      end
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: 400
    end
  end

  # Creates multiple activities by score/start/id.
  #
  # scope [String] the scope of the timeline, `TEST`
  # json [String] The json of the event (see #activity_model)
  # @return [String] the activity as a object/hash converted into json format
  # Request Headers
  # ```json
  #  {
  #    "Authorization": "token/password",
  #    "Content-Type": "application/json"
  #  }
  # ```
  # Request Post Body
  # ```json
  #  {
  #    "multi": [
  #      {
  #        "name": "test",
  #        "start": "2031-04-16T01:02:00+00:00",
  #        "stop": "2031-04-16T01:02:00+00:00",
  #        "kind": "cmd",
  #        "data": {"cmd"=>"INST ABORT"
  #      }
  #    ]
  #  }
  # ```
  def multi_create
    return unless authorization('script_run')
    input_activities = params.to_unsafe_h.slice(:multi).to_h['multi']
    unless input_activities.is_a?(Array)
      render json: { status: 'error', message: 'invalid input, must be json list/array' }, status: 400
      return
    end

    ret = Array.new
    input_activities.each do |input|
      next if input.is_a?(Hash) == false || input['start'].nil? || input['stop'].nil? || input['name'].nil?

      begin
        hash = input.dup
        hash['data'] ||= {}
        hash['data']['username'] = username()
        name = hash.delete('name')
        hash['start'] = DateTime.parse(hash['start']).strftime('%s').to_i
        hash['stop'] = DateTime.parse(hash['stop']).strftime('%s').to_i
        model = @model_class.from_json(hash.symbolize_keys, name: name, scope: params[:scope])
        model.create()
        OpenC3::Logger.info(
          "Activity created: #{name} #{hash}",
          scope: params[:scope],
          user: hash['data']['username']
        )
        ret << model.as_json()
      rescue ArgumentError, TypeError => e
        log_error(e)
        ret << { status: 'error', message: "Invalid input, #{e.message}", input: input, type: e.class, err: 400 }
      rescue OpenC3::ActivityOverlapError => e
        log_error(e)
        ret << { status: 'error', message: e.message, input: input, type: e.class, err: 409 }
      rescue OpenC3::ActivityError => e
        log_error(e)
        ret << { status: 'error', message: e.message, input: input, type: e.class, err: 418 }
      rescue StandardError => e # includes OpenC3::ActivityInputError
        log_error(e)
        ret << { status: 'error', message: e.message, input: input, type: e.class, err: 400 }
      end
    end
    render json: ret
  end

  # Removes multiple activities by score/start/id.
  #
  # scope [String] the scope of the timeline, `TEST`
  # json [String] The json below
  # @return [String] the activity as a object/hash converted into json format
  # Request Headers
  # ```json
  #  {
  #    "Authorization": "token/password",
  #    "Content-Type": "application/json"
  #  }
  # ```
  # Request Post Body
  # ```json
  #  {
  #    "multi": [
  #      {
  #        "name": "system42", # name of the timeline
  #        "id": "12345678" # score/start/id of the timeline
  #      }
  #    ]
  #  }
  # ```
  def multi_destroy
    return unless authorization('script_run')
    input_activities = params.to_unsafe_h.slice(:multi).to_h['multi']
    unless input_activities.is_a?(Array)
      render json: { status: 'error', message: 'invalid input' }, status: 400
      return
    end

    ret = Array.new
    input_activities.each do |input|
      next if input.is_a?(Hash) == false || input['id'].nil? || input['name'].nil? || input['uuid'].nil?

      begin
        result = @model_class.destroy(name: input[:name], score: input[:id].to_i, uuid: input[:uuid], scope: params[:scope])
        OpenC3::Logger.info("Activity destroyed: #{input['name']}", scope: params[:scope], user: username())
        ret << { status: 'removed', removed: result, input: input, type: e.class }
      rescue StandardError => e # includes OpenC3::ActivityInputError
        log_error(e)
        ret << { status: 'error', message: e.message, input: input, type: e.class, err: 400 }
      end
    end
    render json: ret
  end
end
