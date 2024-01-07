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

require 'openc3/config/config_parser'
require 'openc3/interfaces/protocols/protocol'
require 'thread' # For Queue
require 'timeout' # For Timeout::Error

module OpenC3
  # Protocol that waits for a response for any commands with a defined response packet.
  # The response packet is identified but not defined by the protocol.
  class CmdResponseProtocol < Protocol
    # @param response_timeout [Float] Number of seconds to wait before timing out
    #   when waiting for a response
    # @param response_polling_period [Float] Number of seconds to wait between polling
    #   for a response
    # @param raise_exceptions [String] Whether to raise exceptions when errors
    #   occur in the protocol like unexpected responses or response timeouts.
    # @param allow_empty_data [true/false/nil] See Protocol#initialize
    def initialize(
      response_timeout = 5.0,
      response_polling_period = 0.02,
      raise_exceptions = false,
      allow_empty_data = nil
    )
      super(allow_empty_data)
      @response_timeout = ConfigParser.handle_nil(response_timeout)
      @response_timeout = @response_timeout.to_f if @response_timeout
      @response_polling_period = response_polling_period.to_f
      @raise_exceptions = ConfigParser.handle_true_false(raise_exceptions)
      @write_block_queue = Queue.new
      @response_packet = nil
    end

    def connect_reset
      super()
      begin
        @write_block_queue.pop(true) while @write_block_queue.length > 0
      rescue
      end
    end

    def disconnect_reset
      super()
      @write_block_queue << nil # Unblock the write block queue
    end

    def read_packet(packet)
      if @response_packet
        # Grab the response packet specified in the command
        result_packet = System.telemetry.packet(@response_packet[0], @response_packet[1]).clone
        result_packet.buffer = packet.buffer
        result_packet.received_time = nil
        result_packet.stored = packet.stored
        result_packet.extra = packet.extra

        # Release the write
        @write_block_queue << nil

        # This returns the fully identified and defined packet
        # Received time is handled by the interface microservice
        return result_packet
      else
        return packet
      end
    end

    def write_packet(packet)
      # Setup the response packet (if there is one)
      # This primes waiting for the response in post_write_interface
      @response_packet = packet.response

      return packet
    end

    def post_write_interface(packet, data, extra = nil)
      if @response_packet
        if @response_timeout
          response_timeout_time = Time.now + @response_timeout
        else
          response_timeout_time = nil
        end

        # Block the write until the response is received
        begin
          @write_block_queue.pop(true)
        rescue
          sleep(@response_polling_period)
          retry if !response_timeout_time
          retry if response_timeout_time and Time.now < response_timeout_time
          handle_error("#{@interface ? @interface.name : ""}: Timeout waiting for response")
        end

        @response_packet = nil
      end
      return super(packet, data, extra)
    end

    def handle_error(msg)
      Logger.error(msg)
      raise msg if @raise_exceptions
    end
  end
end
