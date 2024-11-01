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
require 'openc3/models/activity_model'

class TriggerGroupController < ApplicationController
  def initialize
    super()
    @model_class = OpenC3::TriggerGroupModel
  end

  # Returns an array/list of trigger values in json.
  #
  # scope [String] the scope of the group, `TEST`
  # @return [String] the array of triggers converted into json format
  def index
    return unless authorization('system')
    begin
      ret = Array.new
      trigger_groups = @model_class.all(scope: params[:scope])
      trigger_groups.each do |_, trigger_group|
        ret << trigger_group
      end
      render json: ret
    rescue StandardError => e
      logger.error(e.formatted)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Returns a single trigger in json.
  #
  # name [String] the trigger name, `systemGroup`
  # scope [String] the scope of the group, `TEST`
  # @return [String] the array of triggers converted into json format.
  def show
    return unless authorization('system')
    begin
      model = @model_class.get(name: params[:name], scope: params[:scope])
      if model.nil?
        render json: { status: 'error', message: 'not found' }, status: 404
        return
      end
      render json: model.as_json(:allow_nan => true)
    rescue OpenC3::TriggerGroupInputError => e
      logger.error(e.formatted)
      render json: { status: 'error', message: e.message, type: e.class }, status: 400
    rescue StandardError => e
      logger.error(e.formatted)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Create a new group and return the object/hash of the trigger in json.
  #
  # scope [String] the scope of the group, `TEST`
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
  #    "name": "systemGroup",
  #  }
  #```
  def create
    return unless authorization('script_run')
    begin
      model = @model_class.new(name: params[:name], scope: params[:scope])
      model.create()
      model.deploy()
      render json: model.as_json(:allow_nan => true), status: 201
    rescue OpenC3::TriggerGroupInputError => e
      logger.error(e.formatted)
      render json: { status: 'error', message: e.message, type: e.class }, status: 400
    rescue OpenC3::TriggerGroupError => e
      logger.error(e.formatted)
      render json: { status: 'error', message: e.message, type: e.class }, status: 418
    rescue StandardError => e
      logger.error(e.formatted)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end

  # Removes a trigger group by name
  #
  # group [String] the trigger group name, `systemGroup`
  # scope [String] the scope of the trigger, `TEST`
  # id [String] the score or id of the trigger, `1620248449`
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
      @model_class.delete(name: params[:group], scope: params[:scope])
      render json: { delete: true, group: params[:group] }
    rescue OpenC3::TriggerGroupInputError => e
      logger.error(e.formatted)
      render json: { status: 'error', message: e.message, type: e.class }, status: 404
    rescue OpenC3::TriggerGroupError => e
      logger.error(e.formatted)
      render json: { status: 'error', message: e.message, type: e.class }, status: 400
    rescue StandardError => e
      logger.error(e.formatted)
      render json: { status: 'error', message: e.message, type: e.class, backtrace: e.backtrace }, status: 500
    end
  end
end
