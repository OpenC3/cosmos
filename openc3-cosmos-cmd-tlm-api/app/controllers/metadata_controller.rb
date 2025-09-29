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

require 'openc3/models/metadata_model'
require 'time'

class MetadataController < ApplicationController
  NOT_FOUND = 'not found'

  def initialize
    @model_class = OpenC3::MetadataModel
  end

  # Returns an array/list of metadata in json. With optional start and stop parameters
  #
  # scope [String] the scope of the metadata, `DEFAULT`
  # start [String] (optional) The start time of the search window
  # stop [String] (optional) The stop time of the search window
  # limit [String] (optional) Maximum number of entries to return
  # @return [String] the array of entries converted into json format.
  def index
    return unless authorization('system')
    action do
      hash = params.to_unsafe_h.slice(:start, :stop, :limit)
      limit = hash['limit'] ? hash['limit'].to_i : 100
      if (hash['start'] && hash['stop'])
        start = Time.parse(hash['start']).to_i
        stop = Time.parse(hash['stop']).to_i
        json = @model_class.range(start: start, stop: stop, limit: limit, scope: params[:scope])
      else
        json = @model_class.all(limit: limit, scope: params[:scope])
      end
      render json: json
    end
  end

  # Record metadata and returns an object/hash of in json.
  #
  # scope [String] the scope of the metadata, `DEFAULT`
  # json [String] The json of the activity (see below)
  # @return [String] the metadata converted into json format
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
  #    "start": "2031-04-16T01:02:00.001+00:00", # ISO8061
  #    "color": "#FF0000",
  #    "metadata": {"version"=>"v1234567"}
  #  }
  # ```
  def create
    return unless authorization('script_run')
    action do
      hash = params.to_unsafe_h.slice(:start, :color, :metadata).to_h
      if hash['start'].nil?
        hash['start'] = Time.now.to_i
      else
        hash['start'] = Time.parse(hash['start']).to_i
      end
      model = @model_class.from_json(hash.symbolize_keys, scope: params[:scope])
      model.create
      OpenC3::Logger.info(
        "Metadata created: #{hash}",
        scope: params[:scope],
        user: username()
      )
      render json: model.as_json(), status: 201
    end
  end

  # Returns an object/hash of a single metadata in json.
  #
  # scope [String] the scope of the metadata, `DEFAULT`
  # id [String] the start of the entry, `1620248449`
  # @return [String] the metadata as a object/hash converted into json format
  # Request Headers
  # ```json
  #  {
  #    "Authorization": "token/password",
  #    "Content-Type": "application/json"
  #  }
  # ```
  def show
    return unless authorization('system')
    action do
      model_hash = @model_class.get(start: params[:id].to_i, scope: params[:scope])
      if model_hash
        render json: model_hash
      else
        render json: { status: 'error', message: NOT_FOUND }, status: 404
      end
    end
  end

  # Update metadata and returns an object/hash of in json.
  #
  # id [String] the id or start value, `12345667`
  # scope [String] the scope of the metadata, `TEST`
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
  #    "start": "2031-04-16T01:02:00.001+00:00",
  #    "metadata": {"version"=>"v1234567"}
  #    "color": "#FF0000",
  #  }
  # ```
  def update
    return unless authorization('script_run')
    action do
      hash = @model_class.get(start: params[:id].to_i, scope: params[:scope])
      if hash.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      model = @model_class.from_json(hash.symbolize_keys, scope: params[:scope])

      hash = params.to_unsafe_h.slice(:start, :color, :metadata).to_h
      hash['start'] = Time.parse(hash['start']).to_i
      model.update(
        start: hash['start'],
        color: hash['color'],
        metadata: hash['metadata'],
      )
      OpenC3::Logger.info(
        "Metadata updated: #{hash}",
        scope: params[:scope],
        user: username()
      )
      render json: model.as_json()
    end
  end

  # Removes metadata by score/id.
  #
  # scope [String] the scope of the timeline, `TEST`
  # id [String] the score or id of the activity, `1620248449`
  # @return [Integer] number of items deleted
  # Request Headers
  # ```json
  #  {
  #    "Authorization": "token/password",
  #    "Content-Type": "application/json"
  #  }
  # ```
  def destroy
    return unless authorization('script_run')
    action do
      count = @model_class.destroy(start: params[:id].to_i, scope: params[:scope])
      if count == 0
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      OpenC3::Logger.info(
        "Metadata destroyed: #{params[:id]}",
        scope: params[:scope],
        user: username()
      )
      render json: { status: count }
    end
  end

  # Returns the latest metadata in json
  #
  # scope [String] the scope of the metadata, `DEFAULT`
  # @return [String] the current metadata converted into json format.
  def latest
    return unless authorization('system')
    action do
      json = @model_class.get_current_value(scope: params[:scope])
      if json.nil?
        render json: { status: 'error', message: 'no metadata entries'}
        return
      end
      render json: json
    end
  end

  # Returns an array/list of metadata in json. With optional start_time and end_time parameters
  #
  # scope [String] the scope of the metadata, `DEFAULT`
  # start [String] (optional) The start time of the search window
  # stop [String] (optional) The stop time of the search window
  # key [String] (required) The key in the metadata
  # value [String] (required) The value equal to the value of the key in the metadata
  # @return [String] the array of entries converted into json format.
  # def search
  #   return unless authorization()
  #   action do
  #     # TODO: This whole search operation needs a method in the model or we're
  #     # basically just searching through the limited results returned
  #     hash = params.to_unsafe_h.slice(:start, :stop, :limit, :key, :value)
  #     if (hash['start'] && hash['stop'])
  #       hash['start'] = Time.parse(hash['start']).to_i
  #       hash['stop'] = Time.parse(hash['stop']).to_i
  #       json = @model_class.range(**hash.symbolize_keys, scope: params[:scope])
  #     else
  #       json = @model_class.all(scope: params[:scope])
  #     end
  #     key, value = [hash['key'], hash['value']]
  #     raise OpenC3::SortedInputError "Must include key, value in metadata search" if key.nil? || value.nil?
  #     selected_array = json_array.select { | json_model | json_model['metadata'][key] == value }
  #     render json: selected_array
  #   end
  # end

  private

  # Yield and rescue all the possible exceptions
  def action
    begin
      yield
    rescue ArgumentError, TypeError => e
      log_error(e)
      render json: {
               status: 'error',
               message: "Invalid input: #{e.message}",
               type: e.class,
             }, status: 400
    rescue OpenC3::SortedOverlapError => e
      log_error(e)
      render json: {
                status: 'error',
                message: e.message,
                type: e.class,
              }, status: 409 # Conflict
    rescue OpenC3::SortedError => e
      log_error(e)
      render json: {
               status: 'error',
               message: e.message,
               type: e.class,
             }, status: 400
    rescue StandardError => e
      log_error(e)
      render json: {
               status: 'error',
               message: e.message,
               type: e.class,
               backtrace: e.backtrace,
             }, status: 400
    end
  end
end
