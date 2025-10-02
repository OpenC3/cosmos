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

require 'openc3/interfaces/stream_interface'
require 'openc3/streams/serial_stream'

module OpenC3
  # Provides a base class for interfaces that use serial ports
  class SerialInterface < StreamInterface
    # Creates a serial interface which uses the specified stream protocol.
    #
    # @param write_port_name [String] The name of the serial port to write
    # @param read_port_name [String] The name of the serial port to read
    # @param baud_rate [Integer] The serial port baud rate
    # @param parity [Symbol] The parity which is normally :NONE.
    #   Must be one of :NONE, :EVEN, or :ODD.
    # @param stop_bits [Integer] The number of stop bits which is normally 1.
    # @param write_timeout [Float] Seconds to wait before aborting writes
    # @param read_timeout [Float|nil] Seconds to wait before aborting reads.
    #   Pass nil to block until the read is complete.
    # @param protocol_type [String] Combined with 'Protocol' to resolve
    #   to a OpenC3 protocol class
    # @param protocol_args [Array] Arguments to pass to the protocol constructor
    def initialize(write_port_name,
                   read_port_name,
                   baud_rate,
                   parity,
                   stop_bits,
                   write_timeout,
                   read_timeout,
                   protocol_type = nil,
                   *protocol_args)
      super(protocol_type, protocol_args)

      @write_port_name = ConfigParser.handle_nil(write_port_name)
      @read_port_name = ConfigParser.handle_nil(read_port_name)
      @baud_rate = baud_rate
      @parity = parity.to_s.intern
      @stop_bits = stop_bits
      @write_timeout = write_timeout
      @read_timeout = read_timeout
      @write_allowed = false unless @write_port_name
      @write_raw_allowed = false unless @write_port_name
      @read_allowed = false unless @read_port_name
      @flow_control = :NONE
      @data_bits = 8
    end

    def connection_string
      type = ''
      if @write_port_name and @read_port_name
        port = @write_port_name
        type = 'R/W'
      elsif @write_port_name
        port = @write_port_name
        type = 'write only'
      else
        port = @read_port_name
        type = 'read only'
      end
      return "#{port} (#{type}) #{@baud_rate} #{@parity} #{@stop_bits}"
    end

    # Creates a new {SerialStream} using the parameters passed in the constructor
    def connect
      @stream = SerialStream.new(
        @write_port_name,
        @read_port_name,
        @baud_rate,
        @parity,
        @stop_bits,
        @write_timeout,
        @read_timeout,
        @flow_control,
        @data_bits
      )
      super()
    end

    # Supported Options
    # FLOW_CONTROL - Flow control method NONE or RTSCTS. Defaults to NONE
    # DATA_BITS - Number of data bits 5, 6, 7, or 8. Defaults to 8
    def set_option(option_name, option_values)
      super(option_name, option_values)
      case option_name.upcase
      when 'FLOW_CONTROL'
        @flow_control = option_values[0]
      when 'DATA_BITS'
        @data_bits = option_values[0].to_i
      end
    end

    def details
      result = super()
      result['write_port_name'] = @write_port_name
      result['read_port_name'] = @read_port_name
      result['baud_rate'] = @baud_rate
      result['parity'] = @parity
      result['stop_bits'] = @stop_bits
      result['write_timeout'] = @write_timeout
      result['read_timeout'] = @read_timeout
      result['flow_control'] = @flow_control
      result['data_bits'] = @data_bits
      return result
    end
  end
end
