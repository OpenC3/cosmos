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

class QueuesController < ApplicationController
  NOT_FOUND = 'queue not found'

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
      render json: { status: 'error', message: e.message, type: e.class.to_s, backtrace: e.backtrace }, status: 500
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
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      render json: model.as_json(:allow_nan => true)
    rescue OpenC3::QueueError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class.to_s }, status: 400
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class.to_s, backtrace: e.backtrace }, status: 500
    end
  end

  # Create a new queue and return the object/hash of the trigger in json.
  #
  # name [String] the queue name, `QUEUE0`
  # scope [String] the scope of the trigger, `TEST`
  def create
    return unless authorization('system')
    begin
      model = @model_class.get(name: params[:name], scope: params[:scope])
      if model.nil?
        model = @model_class.new(name: params[:name], scope: params[:scope])
        model.create()
        model.deploy()
        render json: model.as_json(:allow_nan => true), status: 201
      else
        render json: { status: 'error', message: "#{params[:name]} already exists", type: "OpenC3::QueueError" }, status: 400
      end
    rescue OpenC3::QueueError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class.to_s }, status: 400
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class.to_s, backtrace: e.backtrace }, status: 500
    end
  end

  def list
    return unless authorization('system')
    begin
      model = @model_class.get_model(name: params[:name], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      list = model.list()
      render json: list
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class.to_s, backtrace: e.backtrace }, status: 500
    end
  end

  def hold
    change_state(params, 'HOLD')
  end

  def release
    change_state(params, 'RELEASE')
  end

  def disable
    change_state(params, 'DISABLE')
  end

  def insert
    return unless authorization('system')
    begin
      model = @model_class.get_model(name: params[:name], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      command = params[:command]
      if command.nil?
        render json: { status: 'error', message: 'command is required' }, status: 400
        return
      end
      # If params[:index] is not given this will be nil which means insert at the end
      model.insert(params[:index].to_f, { username: username(), value: command, timestamp: Time.now.to_nsec_from_epoch })
      render json: { status: 'success', message: 'Command added to queue' }
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class.to_s, backtrace: e.backtrace }, status: 500
    end
  end

  def remove
    return unless authorization('system')
    begin
      model = @model_class.get_model(name: params[:name], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      if params[:index].nil?
        render json: { status: 'error', message: 'index is required' }, status: 400
        return
      end
      success = model.remove(params[:index].to_i)
      if success
        render json: { status: 'success', message: 'Command removed from queue' }
      else
        render json: { status: 'error', message: 'Command not found in queue' }, status: 404
      end
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class.to_s, backtrace: e.backtrace }, status: 500
    end
  end

  def destroy
    return unless authorization('system')
    model = @model_class.get_model(name: params[:name], scope: params[:scope])
    if model.nil?
      render json: { status: 'error', message: NOT_FOUND }, status: 404
      return
    end
    model.destroy()
    render json: model.as_json(:allow_nan => true)
  end

  private

  def change_state(params, state)
    return unless authorization('system')
    begin
      model = @model_class.get_model(name: params[:name], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      model.state = state
      model.update()
      render json: model.as_json(:allow_nan => true)
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class.to_s, backtrace: e.backtrace }, status: 500
    end
  end
end
