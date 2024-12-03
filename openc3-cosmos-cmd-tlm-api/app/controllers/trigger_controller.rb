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

require 'openc3/topics/autonomic_topic'
require 'openc3/models/trigger_model'

class TriggerController < ApplicationController
  NOT_FOUND = 'not found'

  def initialize
    @model_class = OpenC3::TriggerModel
  end

  # Returns an array/list of trigger values in json.
  #
  # group [String] the group name, `system`
  # scope [String] the scope of the trigger, `TEST`
  # @return [String] the array of triggers converted into json format
  def index
    return unless authorization('system')
    begin
      ret = Array.new
      triggers = @model_class.all(group: params[:group], scope: params[:scope])
      triggers.each do |_, trigger|
        ret << trigger
      end
      render json: ret
    rescue StandardError => e
      log_error(e)

      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Returns a single trigger in json.
  #
  # group [String] the group name, `systemGroup`
  # name [String] the trigger name, `TV1-12345`
  # scope [String] the scope of the trigger, `TEST`
  # @return [String] the array of triggers converted into json format.
  def show
    return unless authorization('system')
    begin
      model = @model_class.get(name: params[:name], group: params[:group], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      render json: model.as_json(:allow_nan => true)
    rescue OpenC3::TriggerInputError => e
      log_error(e)

      render json: { status: 'error', message: e.message, type: e.class }, status: 400
    rescue StandardError => e
      log_error(e)

      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Create a new trigger and return the object/hash of the trigger in json.
  #
  # group [String] the group name, `systemGroup`
  # name [String] the trigger name, `TV1-12345`
  # scope [String] the scope of the trigger, `TEST`
  # json [String] The json of the event (see #trigger_model)
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
  #    "group": "mango",
  #    "left": {
  #      "type": "item",
  #      "item": "POSX",
  #    },
  #    "operator": ">",
  #    "right": {
  #      "type": "value",
  #      "value": 690000,
  #    }
  #  }
  #```
  def create
    return unless authorization('script_run')
    hash = nil
    begin
      hash = params.to_unsafe_h.slice(:group, :left, :operator, :right).to_h
      name = @model_class.create_unique_name(group: hash['group'], scope: params[:scope])
      model = @model_class.from_json(hash.symbolize_keys, name: name, scope: params[:scope])
      model.create() # Create sends a notification
      render json: model.as_json(:allow_nan => true), status: 201
    rescue OpenC3::TriggerInputError => e
      log_error(e)

      render json: { status: 'error', message: e.message, type: e.class }, status: 400
    rescue OpenC3::TriggerError => e
      log_error(e)

      render json: { status: 'error', message: e.message, type: e.class }, status: 418
    rescue StandardError => e
      log_error(e)

      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Update a trigger and return the object/hash of the trigger in json.
  #
  # group [String] the group name, `systemGroup`
  # name [String] the trigger name, `TV1-12345`
  # scope [String] the scope of the trigger, `TEST`
  # json [String] The json of the event (see #trigger_model)
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
  #    "group": "mango",
  #    "left": {
  #      "type": "item",
  #      "item": "POSX",
  #    },
  #    "operator": ">",
  #    "right": {
  #      "type": "value",
  #      "value": 690000,
  #    }
  #  }
  #```
  def update
    return unless authorization('script_run')
    hash = nil
    begin
      model = @model_class.get(name: params[:name], group: params[:group], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      hash = params.to_unsafe_h.slice(:left, :operator, :right).to_h
      model.left = hash['left']
      model.operator = hash['operator']
      model.right = hash['right']
      # Notify the TriggerGroupMicroservice to update the TriggerModel
      # We don't update directly here to avoid a race condition between the microservice
      # updating state and an asynchronous user updating the trigger
      model.notify(kind: 'updated')
      render json: model.as_json(:allow_nan => true)
    rescue OpenC3::TriggerInputError => e
      log_error(e)

      render json: { status: 'error', message: e.message, type: e.class }, status: 400
    rescue OpenC3::TriggerError => e
      log_error(e)

      render json: { status: 'error', message: e.message, type: e.class }, status: 418
    rescue StandardError => e
      log_error(e)

      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Enable reaction
  #
  # group [String] the group name, `systemGroup`
  # name [String] the trigger name, `TV1-12345`
  # scope [String] the scope of the reaction, `TEST`
  # @return [String] the trigger as a object/hash converted into json format
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
      model = @model_class.get(name: params[:name], group: params[:group], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      # Notify the TriggerGroupMicroservice to enable the TriggerModel
      # We don't update directly here to avoid a race condition between the microservice
      # updating state and an asynchronous user enabling the trigger
      model.notify_enable()
      render json: model.as_json(:allow_nan => true)
    rescue StandardError => e
      log_error(e)

      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Disable reaction
  #
  # group [String] the group name, `systemGroup`
  # name [String] the trigger name, `TV1-1234`
  # scope [String] the scope of the reaction, `TEST`
  # @return [String] the trigger as a object/hash converted into json format
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
      model = @model_class.get(name: params[:name], group: params[:group], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      # Notify the TriggerGroupMicroservice to disable the TriggerModel
      # We don't update directly here to avoid a race condition between the microservice
      # updating state and an asynchronous user disabling the trigger
      model.notify_disable()
      render json: model.as_json(:allow_nan => true)
    rescue StandardError => e
      log_error(e)

      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # group [String] the group name, `DEFAULT`
  # name [String] the trigger name, `TRIG0`
  # scope [String] the scope of the trigger, `DEFAULT`
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
      model = @model_class.get(name: params[:name], group: params[:group], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      unless model.dependents.empty?
        render json: { status: 'error', message: "#{model.group}:#{model.name} has dependents: #{model.dependents}", type: 'TriggerError' }, status: 404
        return
      end
      # Notify the TriggerGroupMicroservice to delete the TriggerModel
      # We don't update directly here to avoid a race condition between the microservice
      # updating state and an asynchronous user deleting the trigger
      model.notify(kind: 'deleted')
      render json: model.as_json(:allow_nan => true)
    rescue StandardError => e
      log_error(e)

      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end
end
