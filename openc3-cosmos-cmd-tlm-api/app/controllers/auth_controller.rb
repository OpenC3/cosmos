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

require 'openc3'
require 'openc3/models/auth_model'

class AuthController < ApplicationController
  def token_exists
    result = OpenC3::AuthModel.set?
    render json: {
      result: result
    }
  end

  def verify
    begin
      if OpenC3::AuthModel.verify_no_service(params[:password], no_password: false)
        render :plain => OpenC3::AuthModel.generate_session()
      else
        head :unauthorized
      end
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 500
    end
  end

  def verify_service
    begin
      if OpenC3::AuthModel.verify(params[:password], service_only: true)
        render :plain => OpenC3::AuthModel.generate_session()
      else
        head :unauthorized
      end
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 500
    end
  end

  def set
    begin
      # Set throws an exception if it fails for any reason
      OpenC3::AuthModel.set(params[:password], params[:old_password])
      OpenC3::Logger.info("Password changed", user: username())
      render :plain => OpenC3::AuthModel.generate_session()
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 500
    end
  end
end
