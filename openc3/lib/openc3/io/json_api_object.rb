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

require 'openc3'
require 'openc3/utilities/authentication'
require 'openc3/io/json_drb'

require 'thread'
require 'socket'
require 'json'
# require 'drb/acl'
require 'drb/drb'
require 'uri'
require 'faraday'


module OpenC3

  class JsonApiError < StandardError; end

  # Used to forward all method calls to the remote server object. Before using
  # this class ensure the remote service has been started in the server class:
  #
  #   json = JsonDrb.new
  #   json.start_service('127.0.0.1', 7777, self)
  #
  # Now the JsonApiObject can be used to call server methods directly:
  #
  #   server = JsonApiObject('http://openc3-cosmos-cmd-tlm-api:2901', 1.0)
  #   server.cmd(*args)
  #
  class JsonApiObject
    attr_reader :request_data
    attr_reader :response_data

    USER_AGENT = 'OpenC3 / v5 (ruby/openc3/lib/io/json_api_object)'.freeze

    # @param url [String] The url of openc3-cosmos-cmd-tlm-api http://openc3-cosmos-cmd-tlm-api:2901
    # @param timeout [Float] The time to wait before disconnecting 1.0
    # @param authentication [OpenC3Authentication] The authentication object if nill initialize will generate
    def initialize(url: ENV['OPENC3_API_URL'], timeout: 1.0, authentication: nil)
      @http = nil
      @mutex = Mutex.new
      @request_data = ""
      @response_data = ""
      @url = url
      @log = [nil, nil, nil]
      @authentication = authentication.nil? ? generate_auth() : authentication
      @timeout = timeout
      @shutdown = false
    end

    # generate the auth object
    def generate_auth
      if ENV['OPENC3_API_TOKEN'].nil? and ENV['OPENC3_API_USER'].nil?
        if ENV['OPENC3_API_PASSWORD']
          return OpenC3Authentication.new()
        else
          return nil
        end
      else
        return OpenC3KeycloakAuthentication.new(ENV['OPENC3_KEYCLOAK_URL'])
      end
    end

    # Forwards all method calls to the remote service.
    #
    # @param method_params [Array] Array of parameters to pass to the method
    # @param keyword_params [Hash<Symbol, Variable>] Hash of keyword parameters
    # @return The result of the method call.
    def request(*method_params, **keyword_params)
      raise JsonApiError, "Shutdown" if @shutdown
      method = method_params[0]
      endpoint = method_params[1]
      @mutex.synchronize do
        kwargs = _generate_kwargs(keyword_params)
        @log = [nil, nil, nil]
        connect() if !@http
        return _send_request(method: method, endpoint: endpoint, kwargs: kwargs)
      end
    end

    # Disconnects from http server
    def disconnect
      @http.close if @http
      @http = nil
    end

    # Permanently disconnects from the http server
    def shutdown
      @shutdown = true
      disconnect()
    end

    private

    def connect
      begin
        # Per https://github.com/lostisland/faraday/blob/main/lib/faraday/options/env.rb
        # :timeout       - time limit for the entire request (Integer in seconds)
        # :open_timeout  - time limit for just the connection phase (e.g. handshake) (Integer in seconds)
        # :read_timeout  - time limit for the first response byte received from the server (Integer in seconds)
        # :write_timeout - time limit for the client to send the request to the server (Integer in seconds)
        @http = Faraday.new(request: { open_timeout: @timeout.to_i, read_timeout: nil }) do |f|
          f.adapter :net_http # adds the adapter to the connection, defaults to `Faraday.default_adapter`
        end
      rescue => e
        raise JsonApiError, e.message
      end
    end

    # NOTE: This is a helper method and should not be called directly
    def _generate_kwargs(keyword_params)
      kwargs = {}
      keyword_params.each do |key, value|
        kwargs[key.intern] = value
      end
      kwargs[:scope] = _generate_scope(kwargs)
      kwargs[:headers] = _generate_headers(kwargs)
      kwargs[:data] = _generate_data(kwargs)
      kwargs[:query] = _generate_query(kwargs)
      return kwargs
    end

    # NOTE: This is a helper method and should not be called directly
    def _generate_scope(kwargs)
      scope = kwargs[:scope]
      if scope.nil?
        raise JsonApiError, "no scope keyword found: #{kwargs}"
      elsif scope.is_a?(String) == false
        raise JsonApiError, "incorrect type for keyword 'scope' MUST be String: #{scope}"
      end
      return scope
    end

    # NOTE: This is a helper method and should not be called directly
    def _generate_headers(kwargs)
      headers = kwargs[:headers]
      if headers.nil?
        headers = kwargs[:headers] = {}
      elsif headers.is_a?(Hash) == false
        raise JsonApiError, "incorrect type for keyword 'headers' MUST be Hash: #{headers}"
      end

      headers['Content-Type'] = 'application/json' if kwargs[:json]
      token = kwargs[:token]
      token = @authentication.token if @authentication and not token
      if token
        return headers.update({
          'User-Agent' => USER_AGENT,
          'Authorization' => token,
        })
      else
        return headers.update({
          'User-Agent' => USER_AGENT,
        })
      end
    end

    # NOTE: This is a helper method and should not be called directly
    def _generate_data(kwargs)
      data = kwargs[:data]
      if data.nil?
        data = kwargs[:data] = {}
      elsif data.is_a?(Hash) == false and data.is_a?(String) == false
        raise JsonApiError, "incorrect type for keyword 'data' MUST be Hash or String: #{data}"
      end
      return kwargs[:json] ? JSON.generate(kwargs[:data]) : kwargs[:data]
    end

    # NOTE: This is a helper method and should not be called directly
    def _generate_query(kwargs)
      query = kwargs[:query]
      if query.nil?
        query = kwargs[:query] = {}
      elsif query.is_a?(Hash) == false
        raise JsonApiError, "incorrect type for keyword 'query' MUST be Hash: #{query}"
      end
      kwargs[:query].update(:scope => kwargs[:scope]) if kwargs[:scope]
    end

    # NOTE: This is a helper method and should not be called directly
    def _send_request(method:, endpoint:, kwargs:)
      begin
        uri = URI("#{@url}#{endpoint}")
        @log[0] = "#{method} Request: #{uri.to_s} #{kwargs}"
        STDOUT.puts @log[0] if JsonDRb.debug?
        resp = _http_request(method: method, uri: uri, kwargs: kwargs)
        @log[1] = "#{method} Response: #{resp.status} #{resp.headers} #{resp.body}"
        STDOUT.puts @log[1] if JsonDRb.debug?
        @response_data = resp.body
        return resp
      rescue StandardError => e
        @log[2] = "#{method} Exception: #{e.class}, #{e.message}, #{e.backtrace}"
        disconnect()
        error = "Api Exception: #{@log[0]} ::: #{@log[1]} ::: #{@log[2]}"
        raise error
      end
    end

    # NOTE: This is a helper method and should not be called directly
    def _http_request(method:, uri:, kwargs:)
      case method
      when 'get', :get
        return @http.get(uri, kwargs[:query], kwargs[:headers])
      when 'post', :post
        return @http.post(uri) do |req|
          req.params = kwargs[:query]
          req.headers = kwargs[:headers]
          req.body = kwargs[:data]
        end
      when 'put', :put
        return @http.put(uri) do |req|
          req.params = kwargs[:query]
          req.headers = kwargs[:headers]
          req.body = kwargs[:data]
        end
      when 'delete', :delete
        return @http.delete(uri, kwargs[:query], kwargs[:headers])
      else
        raise JsonApiError, "no method found: '#{method}'"
      end
    end
  end
end
