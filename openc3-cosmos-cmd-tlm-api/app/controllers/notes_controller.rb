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

require 'openc3/models/note_model'
require 'time'

class NotesController < ApplicationController
  NOT_FOUND = 'not found'

  def initialize
    super()
    @model_class = OpenC3::NoteModel
  end

  # Returns an array/list of notes in json. With op tional start_time and end_time parameters
  #
  # scope [String] the scope of the note, `DEFAULT`
  # start [String] (optional) The start time of the search window
  # stop [String] (optional) The stop time of the search window
  # limit [String] (optional) Maximum number of entries to return
  # @return [String] the array of entries converted into json format.
  def index
    return unless authorization('system')
    action do
      hash = params.to_unsafe_h.slice(:start, :stop, :limit)
      if (hash['start'] && hash['stop'])
        hash['start'] = Time.parse(hash['start']).to_i
        hash['stop'] = Time.parse(hash['stop']).to_i
        json = @model_class.range(**hash.symbolize_keys, scope: params[:scope])
      else
        json = @model_class.all(scope: params[:scope])
      end
      render json: json
    end
  end

  # Record note and returns an object/hash of in json.
  #
  # scope [String] the scope of the note, `TEST`
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
  #    "start": "2031-04-16T01:02:00+00:00",
  #    "stop": "2031-04-16T02:02:00+00:00",
  #    "color": "#FF0000",
  #    "description": "",
  #  }
  # ```
  def create
    return unless authorization('script_run')
    action do
      hash = params.to_unsafe_h.slice(:start, :stop, :color, :description).to_h
      if hash['start'].nil? || hash['stop'].nil?
        raise ArgumentError.new "Param '#{hash['start'].nil? ? 'start' : 'stop'}' is required"
      end

      hash['start'] = Time.parse(hash['start']).to_i
      hash['stop'] = Time.parse(hash['stop']).to_i
      model = @model_class.from_json(hash.symbolize_keys, scope: params[:scope])
      model.create
      OpenC3::Logger.info(
        "Note created: #{hash}",
        scope: params[:scope],
        user: username(),
      )
      render json: model.as_json(), status: 201
    end
  end

  # Returns an object/hash of a single activity in json.
  #
  # scope [String] the scope of the note, `DEFAULT`
  # id [String] the id of the entry, `1620248449`
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
    action do
      model_hash = @model_class.get(start: params[:id].to_i, scope: params[:scope])
      if model_hash
        render json: model_hash
      else
        render json: { status: 'error', message: NOT_FOUND }, status: 404
      end
    end
  end

  # Update and returns an object/hash of a single activity in json.
  #
  # id [String] the score or id of the activity, `1620248449`
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
  #    "start": "2031-04-16T01:02:00+00:00",
  #    "stop": "2031-04-16T01:04:00+00:00",
  #    "color": "#FF0000",
  #    "description": "",
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

      hash = params.to_unsafe_h.slice(:start, :stop, :color, :description).to_h
      hash['start'] = Time.parse(hash['start']).to_i
      hash['stop'] = Time.parse(hash['stop']).to_i
      model.update(
        start: hash['start'],
        stop: hash['stop'],
        color: hash['color'],
        description: hash['description'],
      )
      OpenC3::Logger.info(
        "Note updated: #{hash}",
        scope: params[:scope],
        user: username(),
      )
      render json: model.as_json()
    end
  end

  # Removes a note by score/id.
  #
  # scope [String] the scope of the timeline, `TEST`
  # id [String] the score or id of the activity, `1620248449`
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
    action do
      count = @model_class.destroy(start: params[:id].to_i, scope: params[:scope])
      if count == 0
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      OpenC3::Logger.info(
        "Note destroyed: #{params[:id]}",
        scope: params[:scope],
        user: username(),
      )
      render json: { status: count }
    end
  end

  # Returns an array/list of notes in json. With optional start_time and end_time parameters
  #
  # scope [String] the scope of the note, `DEFAULT`
  # start [String] (optional) The start time of the search window
  # stop [String] (optional) The stop time of the search window
  # description [String] (required) The string to contain in the note description
  # @return [String] the array of entries converted into json format.
  # def search
  #   return unless authorization()
  #   action do
  #     start, stop = parse_time_input(x_start: params[:start], x_stop: params[:stop])
  #     description = params[:description]
  #     raise SortedInputError "Must include description value" if description.nil?
  #     model_array = @model_class.range(scope: params[:scope], start: start, stop: stop)
  #     model_array.find { |model| model.description.include? description }
  #     render json: model_array
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
             },
             status: 400
    rescue OpenC3::SortedError => e
      log_error(e)
      render json: {
               status: 'error',
               message: e.message,
               type: e.class,
             },
             status: 400
    rescue StandardError => e
      log_error(e)
      render json: {
               status: 'error',
               message: e.message,
               type: e.class,
               backtrace: e.backtrace,
             },
             status: 400
    end
  end
end
