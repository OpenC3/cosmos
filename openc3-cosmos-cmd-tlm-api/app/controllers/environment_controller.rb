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

require 'digest'
require 'openc3/models/environment_model'

class EnvironmentController < ApplicationController
  def initialize
    @model_class = OpenC3::EnvironmentModel
  end

  # Returns an array/list of environment values in json.
  #
  # scope [String] the scope of the environment, `TEST`
  # @return [String] the array of environment names converted into json format
  def index
    return unless authorization('system')
    values = @model_class.all(scope: params[:scope]).values
    render json: values
  end

  # Create a new environment returns object/hash of the environment in json.
  #
  # scope [String] the scope of the environment, `TEST`
  # json [String] The json of the environment name (see below)
  # @return [String] the environment converted into json format
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
  #    "key": "ENVIRONMENT_KEY",
  #    "value": "VALUE"
  #  }
  # ```
  def create
    return unless authorization('script_run')
    if params['key'].nil? || params['value'].nil?
      render json: {
        status: 'error',
        message: "Parameter '#{params['key'].nil? ? 'key' : 'value'}' is required",
      }, status: 400
      return
    end
    begin
      name = Digest::SHA1.hexdigest("#{params['key']}__#{params['value']}")
      unless @model_class.get(name: name, scope: params[:scope]).nil?
        raise OpenC3::EnvironmentError.new "Key: '#{params['key']}' value: '#{params['value']}' already exists"
      end

      model = @model_class.new(name: name, key: params['key'], value: params['value'], scope: params[:scope])
      model.create()
      OpenC3::Logger.info("Environment variable created: #{name} #{params['key']} #{params['value']}", scope: params[:scope], user: username())
      render json: model.as_json(), status: 201
    rescue RuntimeError, JSON::ParserError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 400
    rescue TypeError => e
      log_error(e)
      render json: { status: 'error', message: 'Invalid json object', type: e.class }, status: 400
    rescue OpenC3::EnvironmentError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 409
    end
  end

  # Returns hash/object of environment name in json with a 200 status code.
  #
  # name [String] the environment name, `bffcdb71ce38b7604db3c53000adef1ed851606d`
  # scope [String] the scope of the environment, `TEST`
  # @return [String] hash/object of environment name in json with a 200 status code
  def destroy
    return unless authorization('script_run')
    model = @model_class.get(name: params[:name], scope: params[:scope])
    if model.nil?
      render json: {
        status: 'error',
        message: "failed to find environment: #{params[:name]}",
      }, status: 404
      return
    end
    begin
      ret = @model_class.destroy(name: params[:name], scope: params[:scope])
      OpenC3::Logger.info("Environment variable destroyed: #{params[:name]}", scope: params[:scope], user: username())
      render json: { name: params[:name] }
    rescue OpenC3::EnvironmentError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 400
    end
  end
end
