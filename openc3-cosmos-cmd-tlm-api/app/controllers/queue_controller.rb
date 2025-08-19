# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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

require 'openc3/models/queue_model'

class QueueController < ApplicationController
  NOT_FOUND = 'not found'

  def initialize
    super()
    @model_class = OpenC3::QueueModel
  end

  # Returns an array/list of queues in json.
  #
  # scope [String] the scope of the queue, `TEST`
  # @return [String] the array of queues converted into json format
  def index
    return unless authorization('system')
    begin
      queues = @model_class.all(scope: params[:scope])
      ret = Array.new
      queues.each do |_, trigger|
        ret << trigger
      end
      render json: ret
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Returns a queue in json.
  #
  # name [String] the queue name, `QUEUE0`
  # scope [String] the scope of the queue, `TEST`
  # @return [String] the queue converted into json format.
  def show
    return unless authorization('system')
    begin
      model = @model_class.get(name: params[:name], scope: params[:scope])
      render json: model.as_json(:allow_nan => true)
    rescue OpenC3::QueueError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 400
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Create a new queue and return the object/hash of the trigger in json.
  #
  # name [String] the queue name, `QUEUE0`
  # scope [String] the scope of the trigger, `TEST`
  def create
    return unless authorization('system')
    begin
      hash = params.to_unsafe_h.slice(:triggers, :trigger_level, :actions, :snooze).to_h
      name = @model_class.create_unique_name(scope: params[:scope])
      hash[:username] = username()
      model = @model_class.from_json(hash.symbolize_keys, name: name, scope: params[:scope])
      model.create()
      model.deploy()
      render json: model.as_json(:allow_nan => true), status: 201
    rescue OpenC3::QueueInputError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 400
    rescue OpenC3::QueueError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 418
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Update and returns an object/hash of a single queue in json.
  #
  # name [String] the queue name, `QUEUE0`
  # scope [String] the scope of the queue, `TEST`
  # json [String] The json of the event (see #queue_model)
  # @return [String] the queue as a object/hash converted into json format
  def update
    return unless authorization('system')
    hash = nil
    begin
      model = @model_class.get(name: params[:name], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      # Notify the QueueMicroservice to update the QueueModel
      # We don't update directly here to avoid a race condition between the microservice
      # updating state and an asynchronous user updating the queue
      model.notify(kind: 'updated')
      render json: model.as_json(:allow_nan => true)
    rescue OpenC3::QueueError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 418
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Enable queue
  #
  # name [String] the queue name, `QUEUE0`
  # scope [String] the scope of the queue, `TEST`
  # @return [String] the queue as a object/hash converted into json format
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
      # Notify the QueueMicroservice to enable the QueueModel
      # We don't update directly here to avoid a race condition between the microservice
      # updating state and an asynchronous user enabling the queue
      model.notify_enable
      render json: model.as_json(:allow_nan => true)
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Disable queue
  #
  # name [String] the queue name, `QUEUE0`
  # scope [String] the scope of the queue, `TEST`
  # @return [String] the queue as a object/hash converted into json format
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
      # Notify the QueueMicroservice to disable the QueueModel
      # We don't update directly here to avoid a race condition between the microservice
      # updating state and an asynchronous user disabling the queue
      model.notify_disable
      render json: model.as_json(:allow_nan => true)
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Execute a queue's actions
  def execute
    return unless authorization('script_run')
    begin
      model = @model_class.get(name: params[:name], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      # Notify the QueueMicroservice to execute the QueueModel
      # We don't update directly here to avoid a race condition between the microservice
      # updating state and an asynchronous user executing the queue
      model.notify_execute
      render json: model.as_json(:allow_nan => true)
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Removes an queue by name/id.
  #
  # name [String] the queue name, `QUEUE1`
  # scope [String] the scope of the queue, `TEST`
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
      # Notify the QueueMicroservice to delete the QueueModel
      # We don't update directly here to avoid a race condition between the microservice
      # updating state and an asynchronous user deleting the queue
      model.notify(kind: 'deleted')
      render json: model.as_json(:allow_nan => true)
    rescue OpenC3::QueueInputError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 404
    rescue OpenC3::QueueError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 400
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end
end