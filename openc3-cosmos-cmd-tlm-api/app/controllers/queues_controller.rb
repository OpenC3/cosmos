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
require 'openc3/models/offline_access_model'
require 'openc3/utilities/authentication'
require 'openc3/api/api'

class QueuesController < ApplicationController
  include OpenC3::Api

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
    return unless authorization('cmd_info')
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
    return unless authorization('cmd_info')
    begin
      model = @model_class.get(name: params[:name], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      render json: model.as_json()
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
    return unless authorization('cmd')
    begin
      model = @model_class.get(name: params[:name], scope: params[:scope])
      if model.nil?
        state = 'HOLD'
        state = params[:state] if params[:state]
        model = @model_class.new(name: params[:name], state: state, scope: params[:scope])
        model.create()
        render json: model.as_json(), status: 201
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
    return unless authorization('cmd_info')
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

  def insert_command
    command = params[:command]
    if command.nil?
      render json: { status: 'error', message: 'command is required' }, status: 400
      return
    end
    target_name, packet_name = command.strip.split(' ')
    return unless authorization('cmd', target_name: target_name, packet_name: packet_name)
    begin
      model = @model_class.get_model(name: params[:name], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      id = nil
      if params[:id]
        id = params[:id].to_f
      end
      # If params[:id] is not given this will be nil which means insert at the end
      model.insert_command(id, { username: username(), value: command, timestamp: Time.now.to_nsec_from_epoch })
      render json: { status: 'success', message: 'Command added to queue' }
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class.to_s, backtrace: e.backtrace }, status: 500
    end
  end

  def remove_command
    return unless authorization('cmd')
    begin
      model = @model_class.get_model(name: params[:name], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      id = params[:id]&.to_f
      command_data = model.remove_command(id)
      if command_data
        render json: command_data
      else
        render json: { status: 'error', message: 'Command not found in queue' }, status: 404
      end
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class.to_s, backtrace: e.backtrace }, status: 500
    end
  end

  def update_command
    command = params[:command]
    if command.nil?
      render json: { status: 'error', message: 'command is required' }, status: 400
      return
    end
    target_name, packet_name = command.strip.split(' ')
    return unless authorization('cmd', target_name: target_name, packet_name: packet_name)
    begin
      model = @model_class.get_model(name: params[:name], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      id = params[:id]
      if id.nil?
        render json: { status: 'error', message: 'id is required' }, status: 400
        return
      end
      model.update_command(id: id, username: username(), command: command)
      render json: { status: 'success', message: 'Command updated' }
    rescue OpenC3::QueueError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class.to_s }, status: 400
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class.to_s, backtrace: e.backtrace }, status: 500
    end
  end

  def exec_command
    return unless authorization('cmd')
    begin
      model = @model_class.get_model(name: params[:name], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      id = params[:id]&.to_f
      command_data = model.remove_command(id)
      if command_data
        hazardous = false
        token = get_token(username(), scope: params[:scope])
        begin
          if hazardous
            cmd_no_hazardous_check(command_data['value'], queue: false, scope: params[:scope], token: token)
          else
            cmd(command_data['value'], queue: false, scope: params[:scope], token: token)
          end
        rescue HazardousError => e
          # Rescue hazardous error and retry with cmd_no_hazardous_check
          hazardous = true
          retry
        rescue StandardError => e
          log_error(e)
          render json: { status: 'error', message: "Failed to execute command: #{e.message}", type: e.class.to_s, backtrace: e.backtrace }, status: 500
          return
        end
        render json: command_data
      else
        if id
          render json: { status: 'error', message: "No command in queue #{params[:name]} at id #{id}" }, status: 404
        else
          render json: { status: 'error', message: "No commands in queue #{params[:name]}" }, status: 404
        end
      end
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class.to_s, backtrace: e.backtrace }, status: 500
    end
  end

  def destroy
    return unless authorization('cmd')
    model = @model_class.get_model(name: params[:name], scope: params[:scope])
    if model.nil?
      render json: { status: 'error', message: NOT_FOUND }, status: 404
      return
    end
    model.destroy()
    render json: model.as_json()
  end

  private

  def change_state(params, state)
    return unless authorization('cmd')
    begin
      model = @model_class.get_model(name: params[:name], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: NOT_FOUND }, status: 404
        return
      end
      model.state = state
      model.update()
      render json: model.as_json()
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class.to_s, backtrace: e.backtrace }, status: 500
    end
  end

  def get_token(username, scope:)
    if ENV['OPENC3_API_CLIENT'].nil?
      ENV['OPENC3_API_PASSWORD'] ||= ENV['OPENC3_SERVICE_PASSWORD']
      return OpenC3::OpenC3Authentication.new().token
    else
      # Check for offline access token
      model = nil
      model = OpenC3::OfflineAccessModel.get_model(name: username, scope: scope) if username and username != ''
      if model and model.offline_access_token
        auth = OpenC3::OpenC3KeycloakAuthentication.new(ENV['OPENC3_KEYCLOAK_URL'])
        return auth.get_token_from_refresh_token(model.offline_access_token)
      else
        return nil
      end
    end
  end
end
