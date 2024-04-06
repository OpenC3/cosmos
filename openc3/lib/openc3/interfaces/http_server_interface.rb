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
require 'openc3/accessors/http_accessor'
require 'webrick'

module OpenC3
  class HttpServerInterface < Interface
    # @param port [Integer] HTTP port
    def initialize(port = 80)
      super()
      @port = Integer(port)
      @server = nil
      @request_queue = Queue.new
    end

    def connection_string
      return "listening on #{@port}"
    end

    # Connects the interface to its target(s)
    def connect
      @server = WEBrick::HTTPServer.new :Port => @port
      @request_queue = Queue.new

      # Create a response hook for every command packet
      @target_names.each do |target_name|
        System.commands.packets(target_name).each do |packet_name, packet|
          packet.restore_defaults
          path = nil
          begin
            path = packet.read('HTTP_PATH')
          rescue => e
            # No HTTP_PATH is an error
            Logger.error("HttpServerInterface Packet #{target_name} #{packet_name} unable to read HTTP_PATH\n#{e.formatted}")
          end
          if path
            @server.mount_proc path do |req, res|
              # Build the Response
              begin
                status = packet.read('HTTP_STATUS')
                if status
                  res.status = status
                end
              rescue
                # No HTTP_STATUS - Leave at default
              end

              if packet.extra
                headers = packet.extra['HTTP_HEADERS']
                if headers
                  headers.each do |key, value|
                    res[key] = value
                  end
                end
              end

              res.body = packet.buffer

              # Save the Request
              packet_name = nil
              begin
                packet_name = packet.read('HTTP_PACKET')
              rescue
                # No packet name means dont save the request as telemetry
              end
              if packet_name
                data = req.body.to_s.dup # Dup to remove frozen
                extra = {}
                extra['HTTP_REQUEST_TARGET_NAME'] = target_name
                extra['HTTP_REQUEST_PACKET_NAME'] = packet_name

                headers = req.header
                if headers
                  extra['HTTP_HEADERS'] = {}
                  headers.each do |key, value|
                    extra['HTTP_HEADERS'][key.downcase] = value
                  end
                end

                queries = req.query
                if queries
                  extra['HTTP_QUERIES'] = {}
                  queries.each do |key, value|
                    extra['HTTP_QUERIES'][key] = value
                  end
                end

                @request_queue << [data, extra]
              end
            end
          end
        end
      end

      super()

      Thread.new do
        # This blocks, but will be unblocked by server.shutdown called in disconnect()
        @server.start
      end
    end

    def connected?
      if @server
        return true
      else
        return false
      end
    end

    # Disconnects the interface from its target(s)
    def disconnect
      @server.shutdown if @server
      @server = nil
      while @request_queue.length > 0
        @request_queue.pop
      end
      super()
      @request_queue.push(nil)
    end

    # Reads from the socket if the read_port is defined
    def read_interface
      # Get the Faraday Response
      data, extra = @request_queue.pop
      return nil if data.nil?

      read_interface_base(data, extra)
      return data, extra
    end

    # Writes to the socket
    # @param data [Hash] For the HTTP Interface, data is a hash with the needed request info
    def write_interface(_data, _extra = nil)
      raise "Commands cannot be sent to HttpServerInterface"
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
        request_packet_name = extra['HTTP_REQUEST_PACKET_NAME']
        if request_target_name and request_packet_name
          packet.target_name = request_target_name.to_s.upcase
          packet.packet_name = request_packet_name.to_s.upcase
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
    def convert_packet_to_data(_packet)
      raise "Commands cannot be sent to HttpServerInterface"
    end
  end
end
