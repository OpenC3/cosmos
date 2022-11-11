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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license 
# if purchased from OpenC3, Inc.

require 'openc3/utilities/open_telemetry'

class ApiController < ApplicationController

  def api
    OpenC3.in_span('jsonrpc_api') do |span|
      req = Rack::Request.new(request.env)

      if request.post?
        request_headers = Hash[*request.env.select {|k,v| k.start_with? 'HTTP_'}.sort.flatten]
        request_data = req.body.read
        span.add_attributes({ "request_data" => request_data }) if span and request_data.length <= 1000
        status = nil
        content_type = nil
        body = nil
        begin
          OpenC3::Logger.info("API data: #{request_data}", scope: params[:scope], user: user_info(request.headers['HTTP_AUTHORIZATION']))
          OpenC3::Logger.debug("API headers: #{request_headers}", scope: params[:scope], user: user_info(request.headers['HTTP_AUTHORIZATION']))
          status, content_type, body = handle_post(request_data, request_headers)
        rescue OpenC3::AuthError => error
          error_code = OpenC3::JsonRpcError::ErrorCode::AUTH_ERROR
          response = OpenC3::JsonRpcErrorResponse.new(
            OpenC3::JsonRpcError.new(error_code, error.message, error), request.id
          )
          status = 401
          content_type = "application/json-rpc"
          body = response.to_json(:allow_nan => true)
        end
      else
        status       = 405
        content_type = "text/plain"
        body         = "Request not allowed"
      end

      response_headers = { 'Content-Type' => content_type }
      # Individual tools can set 'Ignore-Errors' to an error code
      # they potentially expect, e.g. '500', or '404, 500' in which case we ignore those
      # For example in CommandSender.vue:
      # obs = this.api.cmd(targetName, commandName, paramList, {
      #   'Ignore-Errors': '500',
      # })
      if request_headers.include?('HTTP_IGNORE_ERRORS')
        response_headers['Ignore-Errors'] = request_headers['HTTP_IGNORE_ERRORS']
      end
      rack_response = Rack::Response.new([body], status, response_headers)
      self.response = ActionDispatch::Response.new(*rack_response.to_a)
      self.response.close
    end
  end

  # Handles an http post.
  #
  # @param request_data [String] - A String of the post body from the request
  # @param request_headers [Hash] - A Hash of the headers from the post request
  # @return [Integer, String, String] - Http response code, content type,
  #   response body.
  def handle_post(request_data, request_headers)
    response_data, error_code = OpenC3::Cts.instance.json_drb.process_request(
      request_data: request_data,
      request_headers: request_headers,
      start_time: Time.now.sys)

    # Convert json error code into html status code
    # see http://www.jsonrpc.org/historical/json-rpc-over-http.html#errors
    if error_code
      case error_code
      when OpenC3::JsonRpcError::ErrorCode::PARSE_ERROR      then status = 500 # Internal server error
      when OpenC3::JsonRpcError::ErrorCode::INVALID_REQUEST  then status = 400 # Bad request
      when OpenC3::JsonRpcError::ErrorCode::METHOD_NOT_FOUND then status = 404 # Not found
      when OpenC3::JsonRpcError::ErrorCode::INVALID_PARAMS   then status = 500 # Internal server error
      when OpenC3::JsonRpcError::ErrorCode::INTERNAL_ERROR   then status = 500 # Internal server error
      when OpenC3::JsonRpcError::ErrorCode::AUTH_ERROR       then status = 401
      when OpenC3::JsonRpcError::ErrorCode::FORBIDDEN_ERROR  then status = 403
      else status = 500 # Internal server error
      end
      # Note we don't log an error here because it's logged in JsonDRb::process_request
    else
      status = 200 # OK
    end
    return status, "application/json-rpc", response_data
  end
end
