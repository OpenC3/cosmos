# encoding: ascii-8bit

# Copyright 2024 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/interfaces/interface'
require 'openc3/config/config_parser'
require 'faraday'
require 'faraday/follow_redirects'
require 'openc3/accessors/http_accessor'

# TODO: Header Log Filtering? File Uploads? Authorization from secrets?

module OpenC3
  class HttpClientInterface < Interface
    # @param hostname [String] HTTP/HTTPS server to connect to
    # @param port [Integer] HTTP/HTTPS port
    # @param protocol [String] http or https
    def initialize(hostname, port = 80, protocol = 'http', write_timeout = 5, read_timeout = nil, connect_timeout = 5, include_request_in_response = false)
      super()
      @hostname = hostname
      @port = Integer(port)
      @protocol = protocol
      if (@port == 80 and @protocol == 'http') or (@port == 443 and @protocol == 'https')
        @url = "#{@protocol}://#{@hostname}"
      else
        @url = "#{@protocol}://#{@hostname}:#{@port}"
      end
      @write_timeout = ConfigParser.handle_nil(write_timeout)
      @write_timeout = Float(@write_timeout) if @write_timeout
      @read_timeout = ConfigParser.handle_nil(read_timeout)
      @read_timeout = Float(@read_timeout) if @read_timeout
      @connect_timeout = ConfigParser.handle_nil(connect_timeout)
      @connect_timeout = Float(@connect_timeout) if @connect_timeout
      @include_request_in_response = ConfigParser.handle_true_false(include_request_in_response)

      @response_queue = Queue.new
    end

    def connection_string
      return @url
    end

    # Connects the interface to its target(s)
    def connect
      # Per https://github.com/lostisland/faraday/blob/main/lib/faraday/options/env.rb
      # :timeout       - time limit for the entire request (Integer in seconds)
      # :open_timeout  - time limit for just the connection phase (e.g. handshake) (Integer in seconds)
      # :read_timeout  - time limit for the first response byte received from the server (Integer in seconds)
      # :write_timeout - time limit for the client to send the request to the server (Integer in seconds)
      request = {}
      request['open_timeout'] = @connect_timeout if @connect_timeout
      request['read_timeout'] = @read_timeout if @read_timeout
      request['write_timeout'] = @write_timeout if @write_timeout
      @http = Faraday.new(request: request) do |f|
        f.response :follow_redirects # use Faraday::FollowRedirects::Middleware
        f.adapter :net_http # adds the adapter to the connection, defaults to `Faraday.default_adapter`
      end
      super()
    end

    def connected?
      if @http
        return true
      else
        return false
      end
    end

    # Disconnects the interface from its target(s)
    def disconnect
      @http.close if @http
      @http = nil
      while @response_queue.length > 0
        @response_queue.pop
      end
      super()
      @response_queue.push(nil)
    end

    # Reads from the socket if the read_port is defined
    def read_interface
      # Get the Faraday Response
      data, extra = @response_queue.pop
      return nil if data.nil?

      read_interface_base(data, extra)
      return data, extra
    end

    # Writes to the socket
    # @param data [Hash] For the HTTP Interface, data is a hash with the needed request info
    def write_interface(data, extra = nil)
      extra ||= {}
      queries = extra['HTTP_QUERIES']
      queries ||= {}
      headers = extra['HTTP_HEADERS']
      headers ||= {}
      uri = extra['HTTP_URI']
      method = extra['HTTP_METHOD']

      resp = nil
      case method
      when 'get'
        resp = @http.get(uri, queries, headers)
      when 'put'
        resp = @http.put(uri) do |req|
          req.params = queries
          req.headers = headers
          req.body = data
        end
      when 'delete'
        resp = @http.delete(uri, queries, headers)
      else # 'post'
        resp = @http.post(uri) do |req|
          req.params = queries
          req.headers = headers
          req.body = data
        end
      end

      # Normalize Response into simple hash
      response_data = nil
      response_extra = {}
      if resp
        response_extra['HTTP_REQUEST'] = [data, extra]
        if resp.headers and resp.headers.length > 0
          response_extra['HTTP_HEADERS'] = resp.headers
        end
        response_extra['HTTP_STATUS'] = resp.status
        response_data = resp.body
        response_data ||= '' # Ensure an empty string if we got a response but no data
      end

      @response_queue.push([response_data, response_extra])

      write_interface_base(data, extra)
      return data, extra
    end

    # Called to convert the read data into a OpenC3 Packet object
    #
    # @param data [String] Raw packet data
    # @return [Packet] OpenC3 Packet with buffer filled with data
    def convert_data_to_packet(data, extra = nil)
      packet = Packet.new(nil, nil, :BIG_ENDIAN, nil, data.to_s)
      packet.accessor = HttpAccessor.new(packet)
      if extra
        # Identify the response
        request_target_name = extra['HTTP_REQUEST_TARGET_NAME']
        if request_target_name
          request_target_name = request_target_name.to_s.upcase
          response_packet_name = extra['HTTP_PACKET']
          error_packet_name = extra['HTTP_ERROR_PACKET']
          status = extra['HTTP_STATUS'].to_i
          if status >= 300 and error_packet_name
            # Handle error special case response packet
            packet.target_name = request_target_name
            packet.packet_name = error_packet_name.to_s.upcase
          else
            if response_packet_name
              packet.target_name = request_target_name
              packet.packet_name = response_packet_name.to_s.upcase
            end
          end
        end

        if not @include_request_in_response
          extra.delete("HTTP_REQUEST")
        end
        extra.delete("HTTP_REQUEST_TARGET_NAME")
        extra.delete("HTTP_REQUEST_PACKET_NAME")
        packet.extra = extra
      end

      return packet
    end

    # Called to convert a packet into the data to send
    #
    # @param packet [Packet] Packet to extract data from
    # @return data
    def convert_packet_to_data(packet)
      extra = packet.extra
      extra ||= {}
      data = packet.buffer(true) # Copy buffer so logged command isn't modified
      extra['HTTP_URI'] = URI("#{@url}#{packet.read('HTTP_PATH')}").to_s
      extra['HTTP_REQUEST_TARGET_NAME'] = packet.target_name
      extra['HTTP_REQUEST_PACKET_NAME'] = packet.packet_name
      return data, extra
    end
  end
end
