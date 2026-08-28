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

  # Bad attempt counters are scoped per requesting client (see client_id) so a
  # malicious client can only lock itself out rather than every operator.
  USER_BAD_ATTEMPTS_KEY_PREFIX = 'openc3__auth_bad_attempts__user'
  SERVICE_BAD_ATTEMPTS_KEY_PREFIX = 'openc3__auth_bad_attempts__service'

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
        clear_user_bad_attempts
        render :plain => OpenC3::AuthModel.generate_session()
      else
        record_user_bad_attempt
        head :unauthorized
      end
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: :internal_server_error
    end
  end

  # Checks an existing session token. The login page calls this to skip the
  # login form when the browser already holds a valid session. Deliberately
  # separate from verify: a session token is never a valid password, so passing
  # one to verify always failed and counted as a bad password attempt, letting a
  # stale token in localStorage eat into the rate limit. Session tokens are
  # 128 bits of randomness, so there is nothing here to brute force.
  def verify_token
    # Reject anything that isn't shaped like a session token before touching
    # Redis. Without this, an unauthenticated caller can make us HGETALL the
    # entire session hash on every request. session_token? checks the full
    # shape, not just the prefix, so a caller that knows the prefix still can't
    # fall through with a token generate_session could never have produced. The
    # login page only ever holds a real token, so this costs us nothing. Note
    # this also keeps an OTP token out of verify_no_service, which would consume
    # it.
    unless OpenC3::AuthModel.session_token?(params[:token])
      head :unauthorized
      return
    end

    begin
      if OpenC3::AuthModel.verify_no_service(params[:token], mode: :token)
        head :ok
      else
        head :unauthorized
      end
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: :internal_server_error
    end
  end

  def verify_service
    if service_rate_limited?
      head :too_many_requests
      return
    end

    begin
      if OpenC3::AuthModel.verify(params[:password], service_only: true)
        clear_service_bad_attempts
        render :plain => OpenC3::AuthModel.generate_session()
      else
        record_service_bad_attempt
        head :unauthorized
      end
    rescue StandardError => e
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: :internal_server_error
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
      clear_user_bad_attempts
      OpenC3::Logger.info("Password changed", user: username())
      render :plain => OpenC3::AuthModel.generate_session()
    rescue StandardError => e
      if e.message == "old_password incorrect"
        record_user_bad_attempt
      end
      log_error(e)
      render json: { status: 'error', message: e.message, type: e.class }, status: :internal_server_error
    end
  end

  private

  # Identifies the client making the request so that bad attempt counters are
  # scoped per client instead of globally. A global counter allows any
  # unauthenticated client to lock out every operator by sending
  # MAX_BAD_ATTEMPTS bad passwords, so everything that counts bad attempts must
  # be namespaced by this value.
  #
  # This uses Rails request.remote_ip which honors X-Forwarded-For. COSMOS runs
  # behind traefik, which discards any client supplied X-Forwarded-* headers and
  # sets them from the real connection, so a client can't choose its own bucket.
  # See the forwardedHeaders comments in openc3-traefik/traefik.yaml: if traefik
  # is configured to trust a proxy that doesn't set X-Forwarded-For, every
  # client collapses into that proxy's bucket.
  def client_id
    ip = begin
      request.remote_ip
    rescue StandardError
      nil
    end
    ip ||= request.remote_addr
    # Only allow ip address characters in the key and bound the length so the
    # attacker controlled header can't be used to build arbitrary Redis keys
    ip = ip.to_s.gsub(/[^0-9a-fA-F:.]/, '')[0, 45]
    return ip.empty? ? 'unknown' : ip
  end

  def user_bad_attempts_key
    "#{USER_BAD_ATTEMPTS_KEY_PREFIX}__#{client_id}"
  end

  def service_bad_attempts_key
    "#{SERVICE_BAD_ATTEMPTS_KEY_PREFIX}__#{client_id}"
  end

  # Checks to see if this client has been rate limited due to bad user password attempts
  def user_rate_limited?
    rate_limited?(user_bad_attempts_key, 'user')
  end

  # Initializes or increments this client's bad attempt counter for the user password
  def record_user_bad_attempt
    record_bad_attempt(user_bad_attempts_key, 'user')
  end

  # Clears this client's bad attempt counter after a successful user authentication
  def clear_user_bad_attempts
    clear_bad_attempts(user_bad_attempts_key, 'user')
  end

  # Checks to see if this client has been rate limited due to bad service password attempts
  def service_rate_limited?
    rate_limited?(service_bad_attempts_key, 'service')
  end

  # Initializes or increments this client's bad attempt counter for the service password
  def record_service_bad_attempt
    record_bad_attempt(service_bad_attempts_key, 'service')
  end

  # Clears this client's bad attempt counter after a successful service authentication
  def clear_service_bad_attempts
    clear_bad_attempts(service_bad_attempts_key, 'service')
  end

  def rate_limited?(key, type)
    begin
      count = OpenC3::EphemeralStore.get(key)
      limited = count.to_i >= MAX_BAD_ATTEMPTS
      # A limited client returns before recording another bad attempt, so if the
      # counter somehow has no TTL (incr succeeded but expire didn't) nothing
      # would ever set one and the client would be locked out forever
      if limited and OpenC3::EphemeralStore.ttl(key) < 0
        OpenC3::EphemeralStore.expire(key, BAD_ATTEMPTS_WINDOW)
      end
      return limited
    rescue StandardError => error
      OpenC3::Logger.error("Redis error checking #{type} rate limit: #{error.message}")
      return false
    end
  end

  def record_bad_attempt(key, type)
    begin
      OpenC3::EphemeralStore.incr(key)
      # Refresh the TTL on every bad attempt so the window is measured from the
      # last bad attempt rather than the first. Note a client that is already
      # limited returns before getting here, so it can't extend its own lockout:
      # the lockout always ends BAD_ATTEMPTS_WINDOW after the attempt that
      # tripped it.
      OpenC3::EphemeralStore.expire(key, BAD_ATTEMPTS_WINDOW)
    rescue StandardError => error
      OpenC3::Logger.error("Redis error recording #{type} bad attempt: #{error.message}")
    end
  end

  def clear_bad_attempts(key, type)
    begin
      OpenC3::EphemeralStore.del(key)
    rescue StandardError => error
      OpenC3::Logger.error("Redis error clearing #{type} bad attempts: #{error.message}")
    end
  end
end
