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

require 'openc3/models/reaction_model'

class ReactionController < ApplicationController
  NOT_FOUND = 'not found'

  def initialize
    super()
    @model_class = OpenC3::ReactionModel
  end

  # Returns an array/list of reactions in json.
  #
  # scope [String] the scope of the reaction, `TEST`
  # @return [String] the array of triggers converted into json format
  def index
    return unless authorization('system')
    begin
      triggers = @model_class.all(scope: params[:scope])
      ret = []
      triggers.each do |_, trigger|
        ret << trigger
      end
      render json: ret
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Returns an reactions in json.
  #
  # name [String] the reaction name, `REACT0`
  # scope [String] the scope of the reaction, `TEST`
  # @return [String] the array of reactions converted into json format.
  def show
    return unless authorization('system')
    begin
      model = @model_class.get(name: params[:name], scope: params[:scope])
      render json: model.as_json()
    rescue OpenC3::ReactionInputError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 404
    rescue OpenC3::ReactionError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 400
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Create a new reaction and return the object/hash of the trigger in json.
  #
  # name [String] the reaction name, `REACT0`
  # scope [String] the scope of the trigger, `TEST`
  # json [String] The json of the event (see #reaction_model)
  # @return [String] the trigger converted into json format
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
  #    "triggers": [
  #      {
  #        "name": "TV0-1234",
  #        "group": "foo",
  #      }
  #    ],
  #    "trigger_level": 'EDGE',
  #    "actions": [
  #      {
  #        "type": "command",
  #        "value": "INST CLEAR",
  #      }
  #    ],
  #    "snooze": 300,
  #  }
  #```
  def create
    return unless authorization('script_run')
    begin
      hash = params.to_unsafe_h.slice(:triggers, :trigger_level, :actions, :snooze).to_h
      name = @model_class.create_unique_name(scope: params[:scope])
      hash[:username] = username()
      model = @model_class.from_json(hash.symbolize_keys, name: name, scope: params[:scope])
      model.create()
      model.deploy()
      render json: model.as_json(), status: 201
    rescue OpenC3::ReactionInputError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 400
    rescue OpenC3::ReactionError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 418
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Update and returns an object/hash of a single reaction in json.
  #
  # name [String] the reaction name, `REACT0`
  # scope [String] the scope of the reaction, `TEST`
  # json [String] The json of the event (see #reaction_model)
  # @return [String] the reaction as a object/hash converted into json format
  # Request Headers
  #```json
  #  {
  #    "Authorization": "token/password",
  #    "Content-Type": "application/json"
  #  }
  #```
  # Request Post Body
  #```json
  #  {}
  #```
  def update
    return unless authorization('script_run')
    hash = nil
    begin
      model = @model_class.get(name: params[:name], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      hash = params.to_unsafe_h.slice(:snooze, :triggers, :trigger_level, :actions).to_h
      model.triggers = hash['triggers'] if hash['triggers']
      model.actions = hash['actions'] if hash['actions']
      model.trigger_level = hash['trigger_level'] if hash['trigger_level']
      model.snooze = hash['snooze'] if hash['snooze']
      # Notify the ReactionMicroservice to update the ReactionModel
      # We don't update directly here to avoid a race condition between the microservice
      # updating state and an asynchronous user updating the reaction
      model.notify(kind: 'updated')
      render json: model.as_json()
    rescue OpenC3::ReactionInputError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 400
    rescue OpenC3::ReactionError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 418
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Enable reaction
  #
  # name [String] the reaction name, `REACT0`
  # scope [String] the scope of the reaction, `TEST`
  # @return [String] the reaction as a object/hash converted into json format
  # Request Headers
  #```json
  #  {
  #    "Authorization": "token/password",
  #    "Content-Type": "application/json"
  #  }
  #```
  # Request Post Body
  #```json
  #  {}
  #```
  def enable
    return unless authorization('script_run')
    begin
      model = @model_class.get(name: params[:name], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      # Notify the ReactionMicroservice to enable the ReactionModel
      # We don't update directly here to avoid a race condition between the microservice
      # updating state and an asynchronous user enabling the reaction
      model.notify_enable
      render json: model.as_json()
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Disable reaction
  #
  # name [String] the reaction name, `REACT0`
  # scope [String] the scope of the reaction, `TEST`
  # @return [String] the reaction as a object/hash converted into json format
  # Request Headers
  #```json
  #  {
  #    "Authorization": "token/password",
  #    "Content-Type": "application/json"
  #  }
  #```
  # Request Post Body
  #```json
  #  {}
  #```
  def disable
    return unless authorization('script_run')
    begin
      model = @model_class.get(name: params[:name], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      # Notify the ReactionMicroservice to disable the ReactionModel
      # We don't update directly here to avoid a race condition between the microservice
      # updating state and an asynchronous user disabling the reaction
      model.notify_disable
      render json: model.as_json()
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Execute a reaction's actions
  def execute
    return unless authorization('script_run')
    begin
      model = @model_class.get(name: params[:name], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      # Notify the ReactionMicroservice to execute the ReactionModel
      # We don't update directly here to avoid a race condition between the microservice
      # updating state and an asynchronous user executing the reaction
      model.notify_execute
      render json: model.as_json()
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Removes an reaction by name/id.
  #
  # name [String] the reaction name, `REACT1`
  # scope [String] the scope of the reaction, `TEST`
  # @return [String] object/hash converted into json format but with a 200 status code
  # Request Headers
  #```json
  #  {
  #    "Authorization": "token/password",
  #    "Content-Type": "application/json"
  #  }
  #```
  def destroy
    return unless authorization('script_run')
    begin
      model = @model_class.get(name: params[:name], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      # Notify the ReactionMicroservice to delete the ReactionModel
      # We don't update directly here to avoid a race condition between the microservice
      # updating state and an asynchronous user deleting the reaction
      model.notify(kind: 'deleted')
      render json: model.as_json()
    rescue OpenC3::ReactionInputError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 404
    rescue OpenC3::ReactionError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 400
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end
end
