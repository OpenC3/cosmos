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
  MAX_BAD_ATTEMPTS = ENV.fetch('OPENC3_AUTH_RATE_LIMIT_TO', '10').to_i
  BAD_ATTEMPTS_WINDOW = ENV.fetch('OPENC3_AUTH_RATE_LIMIT_WITHIN', '120').to_i

  USER_BAD_ATTEMPTS_KEY = 'openc3__auth_bad_attempts__user'
  SERVICE_BAD_ATTEMPTS_KEY = 'openc3__auth_bad_attempts__service'

  def token_exists
    result = OpenC3::AuthModel.set?
    render json: {
      result: result
    }
  end

  def verify
    if user_rate_limited?
      head :too_many_requests
      return
    end

    begin
      if OpenC3::AuthModel.verify_no_service(params[:password], mode: :password)
        render :plain => OpenC3::AuthModel.generate_session()
      else
        record_user_bad_attempt
        head :unauthorized
      end
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 500
    end
  end

  def verify_service
    if service_rate_limited?
      head :too_many_requests
      return
    end

    begin
      if OpenC3::AuthModel.verify(params[:password], service_only: true)
        render :plain => OpenC3::AuthModel.generate_session()
      else
        record_service_bad_attempt
        head :unauthorized
      end
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 500
    end
  end

  def get_otp
    user = authorization('system')
    return unless user
    render :plain => OpenC3::Authorization.generate_otp(user)
  end

  def set
    if user_rate_limited?
      head :too_many_requests
      return
    end

    begin
      # Set throws an exception if it fails for any reason
      OpenC3::AuthModel.set(params[:password], params[:old_password])
      OpenC3::Logger.info("Password changed", user: username())
      render :plain => OpenC3::AuthModel.generate_session()
    rescue StandardError => e
      if e.message == "old_password incorrect"
        record_user_bad_attempt
      end
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: 500
    end
  end

  private

  # Checks to see if the user password has been rate limited due to bad attempts
  def user_rate_limited?
    begin
      count = OpenC3::EphemeralStore.get(USER_BAD_ATTEMPTS_KEY)
      return count.to_i >= MAX_BAD_ATTEMPTS
    rescue StandardError => error
      OpenC3::Logger.error("Redis error checking user rate limit: #{error.message}")
      return false
    end
  end
  
  # Initializes or increments the bad attempt counter for the user password
  def record_user_bad_attempt
    begin
      count = OpenC3::EphemeralStore.incr(USER_BAD_ATTEMPTS_KEY)
      OpenC3::EphemeralStore.expire(USER_BAD_ATTEMPTS_KEY, BAD_ATTEMPTS_WINDOW) if count == 1
    rescue StandardError => error
      OpenC3::Logger.error("Redis error recording user bad attempt: #{error.message}")
    end
  end
  
  # Checks to see if the service password has been rate limited due to bad attempts
  def service_rate_limited?
    begin
      count = OpenC3::EphemeralStore.get(SERVICE_BAD_ATTEMPTS_KEY)
      return count.to_i >= MAX_BAD_ATTEMPTS
    rescue StandardError => error
      OpenC3::Logger.error("Redis error checking service rate limit: #{error.message}")
      return false
    end
  end
  
  # Initializes or increments the bad attempt counter for the service password
  def record_service_bad_attempt
    begin
      count = OpenC3::EphemeralStore.incr(SERVICE_BAD_ATTEMPTS_KEY)
      OpenC3::EphemeralStore.expire(SERVICE_BAD_ATTEMPTS_KEY, BAD_ATTEMPTS_WINDOW) if count == 1
    rescue StandardError => error
      OpenC3::Logger.error("Redis error recording service bad attempt: #{error.message}")
    end
  end
end
