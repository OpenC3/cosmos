# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/api/calendar_api'

class ActivityController < ApplicationController
  include OpenC3::Api

  NOT_FOUND = 'not found'

  # Returns an array/list of activities in json. With optional start_time and end_time parameters
  #
  # name [String] the timeline name, `system42`
  # scope [String] the scope of the timeline, `TEST`
  # start [String] (optional) The start time of the search window for timeline to return. Recommend in ISO format, `2031-04-16T01:02:00+00:00`.
  # stop [String] (optional) The stop time of the search window for timeline to return. Recommend in ISO format, `2031-04-16T01:02:00+00:00`.
  # @return [String] the array of activities converted into json format.
  def index
    return unless authorization('system')
    begin
      render json: get_timeline_activities(
        params[:name],
        start: params[:start],
        stop: params[:stop],
        limit: params[:limit],
        scope: params[:scope],
      )
    rescue ArgumentError => e
      log_error(e)
      render json: { status: 'error', message: 'Invalid date provided. Recommend ISO format' }, status: :bad_request
    rescue StandardError => e # includes ActivityInputError
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: :bad_request
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
    hash = params.permit(:start, :stop, :kind, data: {}, recurring: {}).to_h
    begin
      hash['data'] ||= {}
      hash['data']['username'] = username()
      if hash['start'].nil? || hash['stop'].nil?
        raise ArgumentError.new 'post body must contain start and stop'
      end
      result = create_timeline_activity(
        params[:name],
        kind: hash['kind'],
        start: hash['start'],
        stop: hash['stop'],
        data: hash['data'],
        recurring: hash['recurring'],
        scope: params[:scope],
      )
      OpenC3::Logger.info(
        "Activity created: #{params[:name]} #{hash}",
        scope: params[:scope],
        user: hash['data']['username']
      )
      render json: result, status: :created
    rescue ArgumentError, TypeError => e
      log_error(e)
      render json: { status: 'error', message: "Invalid input: #{hash}", type: e.class, e: e.to_s }, status: :bad_request
    rescue OpenC3::ActivityInputError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: :bad_request
    rescue OpenC3::ActivityOverlapError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: :conflict
    rescue OpenC3::ActivityError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: :unprocessable_entity
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: :bad_request
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
      render json: { name: params[:name], count: count_timeline_activities(params[:name], scope: params[:scope]) }
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: :bad_request
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
      result = get_timeline_activity(params[:name], params[:id], params[:uuid], scope: params[:scope])
      if result.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: :not_found
      else
        render json: result
      end
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: :bad_request
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
    begin
      hash = params.permit(:status, :message).to_h
      result = commit_timeline_activity(
        params[:name],
        params[:id],
        params[:uuid],
        status: hash['status'],
        message: hash['message'],
        scope: params[:scope],
      )
      if result.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: :not_found
        return
      end
      OpenC3::Logger.info(
        "Event created for activity: #{params[:name]} #{hash}",
        scope: params[:scope],
        user: username()
      )
      render json: result
    rescue OpenC3::ActivityError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: :unprocessable_entity
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: :bad_request
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
    hash = params.permit(:start, :stop, :kind, data: {}).to_h
    begin
      hash['data'] ||= {}
      hash['data']['username'] = username()
      result = update_timeline_activity(
        params[:name],
        id: params[:id],
        kind: hash['kind'],
        start: hash['start'],
        stop: hash['stop'],
        uuid: params[:uuid],
        data: hash['data'],
        scope: params[:scope],
      )
      if result.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: :not_found
        return
      end
      OpenC3::Logger.info(
        "Activity updated: #{params[:name]} #{hash}",
        scope: params[:scope],
        user: hash['data']['username']
      )
      render json: result
    rescue ArgumentError, TypeError => e
      log_error(e)
      render json: { status: 'error', message: "Invalid input: #{hash}", type: e.class, e: e.to_s }, status: :bad_request
    rescue OpenC3::ActivityInputError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: :bad_request
    rescue OpenC3::ActivityOverlapError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: :conflict
    rescue OpenC3::ActivityError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: :unprocessable_entity
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: :bad_request
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
      ret = delete_timeline_activity(
        params[:name],
        params[:id],
        params[:uuid],
        recurring: params[:recurring],
        scope: params[:scope],
      )
      if ret == 0
        render json: { status: 'error', message: NOT_FOUND }, status: :not_found
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
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: :bad_request
    end
  end
end
