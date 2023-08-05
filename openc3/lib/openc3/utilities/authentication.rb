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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/version'
require 'faraday'

module OpenC3
  # Basic exception for known errors
  class OpenC3AuthenticationError < StandardError; end
  class OpenC3AuthenticationRetryableError < OpenC3AuthenticationError; end

  # OpenC3 base / open source authentication code
  class OpenC3Authentication
    def initialize()
      @token = ENV['OPENC3_API_PASSWORD'] || ENV['OPENC3_SERVICE_PASSWORD']
      if @token.nil?
        raise OpenC3AuthenticationError, "Authentication requires environment variables OPENC3_API_PASSWORD or OPENC3_SERVICE_PASSWORD"
      end
    end

    # Load the token from the environment
    def token()
      @token
    end
  end

  # OpenC3 enterprise Keycloak authentication code
  class OpenC3KeycloakAuthentication < OpenC3Authentication
    # {
    #     "access_token": "",
    #     "expires_in": 600,
    #     "refresh_expires_in": 1800,
    #     "refresh_token": "",
    #     "token_type": "bearer",
    #     "id_token": "",
    #     "not-before-policy": 0,
    #     "session_state": "",
    #     "scope": "openid email profile"
    # }

    REFRESH_OFFSET_SECONDS = 60

    attr_reader :refresh_token

    # @param url [String] The url of the openc3 or keycloak in the cluster
    def initialize(url)
      @url = url
      @auth_mutex = Mutex.new
      @refresh_token = nil
      @expires_at = nil
      @refresh_expires_at = nil
      @token = nil
      @log = [nil, nil]
      @http = Faraday.new
    end

    # Load the token from the environment
    def token
      @auth_mutex.synchronize do
        @log = [nil, nil]
        current_time = Time.now.to_i
        if @token.nil?
          _make_token(current_time)
        elsif @refresh_expires_at < current_time
          _make_token(current_time)
        elsif @expires_at < current_time
          _refresh_token(current_time)
        end
      end
      "Bearer #{@token}"
    end

    def get_token_from_refresh_token(refresh_token)
      current_time = Time.now.to_i
      begin
        @refresh_token = refresh_token
        _refresh_token(current_time)
        return @token
      rescue OpenC3AuthenticationError
        return nil
      end
    end

    private

    # Make the token and save token to instance
    def _make_token(current_time)
      client_id = ENV['OPENC3_API_CLIENT'] || 'api'
      if ENV['OPENC3_API_USER'] and ENV['OPENC3_API_PASSWORD']
        # Username and password
        data = "username=#{ENV['OPENC3_API_USER']}&password=#{ENV['OPENC3_API_PASSWORD']}"
        data << "&client_id=#{client_id}"
        data << '&grant_type=password&scope=openid'
        headers = {
          'Content-Type' => 'application/x-www-form-urlencoded',
          'User-Agent' => "OpenC3KeycloakAuthorization / #{OPENC3_VERSION} (ruby/openc3/lib/utilities/authentication)",
        }
        oath = _make_request(headers, data)
        @token = oath['access_token']
        @refresh_token = oath['refresh_token']
        @expires_at = current_time + oath['expires_in'] - REFRESH_OFFSET_SECONDS
        @refresh_expires_at = current_time + oath['refresh_expires_in'] - REFRESH_OFFSET_SECONDS
      else
        # Offline Access Token
        @refresh_token ||= ENV['OPENC3_API_TOKEN']
        _refresh_token(current_time)
      end
    end

    # Refresh the token and save token to instance
    def _refresh_token(current_time)
      client_id = ENV['OPENC3_API_CLIENT'] || 'api'
      data = "client_id=#{client_id}&refresh_token=#{@refresh_token}&grant_type=refresh_token"
      headers = {
        'Content-Type' => 'application/x-www-form-urlencoded',
        'User-Agent' => "OpenC3KeycloakAuthorization / #{OPENC3_VERSION} (ruby/openc3/lib/utilities/authentication)",
      }
      oath = _make_request(headers, data)
      @token = oath["access_token"]
      @refresh_token = oath["refresh_token"]
      @expires_at = current_time + oath["expires_in"] - REFRESH_OFFSET_SECONDS
      @refresh_expires_at = current_time + oath["refresh_expires_in"] - REFRESH_OFFSET_SECONDS
    end

    # Make the post request to keycloak
    def _make_request(headers, data)
      realm = ENV['OPENC3_KEYCLOAK_REALM'] || 'openc3'
      uri = URI("#{@url}/realms/#{realm}/protocol/openid-connect/token")
      @log[0] = "request uri: #{uri.to_s} header: #{headers.to_s} body: #{data.to_s}"
      STDOUT.puts @log[0] if JsonDRb.debug?
      saved_verbose = $VERBOSE; $VERBOSE = nil
      begin
        resp = @http.post(uri, data, headers)
      ensure
        $VERBOSE = saved_verbose
      end
      @log[1] = "response status: #{resp.status} header: #{resp.headers} body: #{resp.body}"
      STDOUT.puts @log[1] if JsonDRb.debug?
      if resp.status >= 200 && resp.status <= 299
        return JSON.parse(resp.body, :allow_nan => true, :create_additions => true)
      elsif resp.status >= 500 && resp.status <= 599
        raise OpenC3AuthenticationRetryableError, "authentication request retryable #{@log[0]} ::: #{@log[1]}"
      else
        raise OpenC3AuthenticationError, "authentication request failed #{@log[0]} ::: #{@log[1]}"
      end
    end
  end
end
