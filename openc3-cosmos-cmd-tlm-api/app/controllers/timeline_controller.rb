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

class TimelineController < ApplicationController
  include OpenC3::Api

  # Returns an array/list of timeline values in json.
  #
  # scope [String] the scope of the timeline, `TEST`
  # @return [String] the array of timeline names converted into json format
  def index
    return unless authorization('system')
    render json: list_timelines(scope: params[:scope])
  end

  # Create a new timeline returns object/hash of the timeline in json.
  #
  # scope [String] the scope of the timeline, `TEST`
  # json [String] The json of the timeline name (see below)
  # @return [String] the timeline converted into json format
  # Request Headers
  #```json
  #  {
  #    "Authorization": "token/password",
  #    "Content-Type": "application/json"
  #  }
  #```
  # Request Post Body
  #```json
  #  {
  #    "name": "system42",
  #    "color": "#FFFFFF"
  #  }
  #```
  def create
    return unless authorization('script_run')
    begin
      result = create_timeline(params['name'], color: params['color'], scope: params[:scope])
      OpenC3::Logger.info("Timeline created: #{params['name']}", scope: params[:scope], user: username())
      render json: result, status: :created
    rescue RuntimeError, JSON::ParserError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: :bad_request
    rescue TypeError => e
      log_error(e)
      render json: { status: 'error', message: 'Invalid json object', type: e.class }, status: :bad_request
    rescue OpenC3::TimelineInputError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: :bad_request
    end
  end

  # Returns a timeline in json.
  #
  # name [String] the name of the timeline, `TEST`
  # scope [String] the scope of the timeline, `DEFAULT`
  # @return [String] timeline converted into json format
  def show
    return unless authorization('system')
    begin
      result = get_timeline(params[:name], scope: params[:scope])
      if result.nil?
        render json: { status: 'error', message: 'not found' }, status: :not_found
      else
        render json: result
      end
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, e: e.to_s }, status: :bad_request
    end
  end

  # Change the color returns object/hash of the timeline in json.
  #
  # name [String] the timeline name, `system42`
  # scope [String] the scope of the timeline, `TEST`
  # json [String] The json of the timeline name (see below)
  # @return [String] the timeline converted into json format
  # Request Headers
  #```json
  #  {
  #    "Authorization": "token/password",
  #    "Content-Type": "application/json"
  #  }
  #```
  # Request Post Body
  #```json
  #  {
  #    "color": "#FFFFFF"
  #  }
  #```
  def color
    return unless authorization('script_run')
    begin
      result = set_timeline_color(params[:name], params['color'], scope: params[:scope])
      if result.nil?
        render json: { status: 'error', message: "failed to find timeline: #{params[:name]}" }, status: :not_found
      else
        render json: result
      end
    rescue RuntimeError, JSON::ParserError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: :bad_request
    rescue TypeError => e
      log_error(e)
      render json: { status: 'error', message: 'Invalid json object', type: e.class }, status: :bad_request
    rescue OpenC3::TimelineInputError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: :bad_request
    end
  end

  # Set the timeline execution status
  #
  # name [String] the timeline name, `system42`
  # scope [String] the scope of the timeline, `TEST`
  # json [String] The json of the timeline name (see below)
  # @return [String] the timeline converted into json format
  # Request Headers
  #```json
  #  {
  #    "Authorization": "token/password",
  #    "Content-Type": "application/json"
  #  }
  #```
  # Request Post Body
  #```json
  #  {
  #    "enable": "false"
  #  }
  #```
  def execute
    return unless authorization('script_run')
    begin
      result = set_timeline_execute(params[:name], params['enable'], scope: params[:scope])
      if result.nil?
        render json: { status: 'error', message: "failed to find timeline: #{params[:name]}" }, status: :not_found
      else
        render json: result
      end
    rescue RuntimeError, JSON::ParserError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: :bad_request
    rescue TypeError => e
      log_error(e)
      render json: { status: 'error', message: 'Invalid json object', type: e.class }, status: :bad_request
    rescue OpenC3::TimelineInputError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: :bad_request
    end
  end

  # Delete timeline
  #
  # name [String] the timeline name, `system42`
  # scope [String] the scope of the timeline, `TEST`
  # @return [String] hash/object of timeline name in json with a 200 status code
  def destroy
    return unless authorization('script_run')
    begin
      use_force = params[:force].nil? == false && params[:force] == 'true'
      result = delete_timeline(params[:name], force: use_force, scope: params[:scope])
      if result.nil?
        render json: { status: 'error', message: "failed to find timeline: #{params[:name]}" }, status: :not_found
      else
        OpenC3::Logger.info("Timeline destroyed: #{params[:name]}", scope: params[:scope], user: username())
        render json: result
      end
    rescue OpenC3::TimelineError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: :bad_request
    end
  end
end
