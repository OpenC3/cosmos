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

require 'openc3/config/config_parser'
require 'openc3/interfaces/protocols/burst_protocol'

module OpenC3
  # Delineates packets by identifying them and then
  # reading out their entire fixed length. Packets lengths can vary but
  # they must all be fixed.
  class FixedProtocol < BurstProtocol
    # @param min_id_size [Integer] The minimum amount of data needed to
    #   identify a packet.
    # @param discard_leading_bytes (see BurstProtocol#initialize)
    # @param sync_pattern (see BurstProtocol#initialize)
    # @param telemetry [Boolean] Whether the interface is returning
    #   telemetry (true) or commands (false)
    # @param fill_fields (see BurstProtocol#initialize)
    # @param unknown_raise Whether to raise an exception on an unknown packet
    # @param allow_empty_data [true/false/nil] See Protocol#initialize
    def initialize(
      min_id_size,
      discard_leading_bytes = 0,
      sync_pattern = nil,
      telemetry = true,
      fill_fields = false,
      unknown_raise = false,
      allow_empty_data = nil
    )
      super(discard_leading_bytes, sync_pattern, fill_fields, allow_empty_data)
      @min_id_size = Integer(min_id_size)
      @telemetry = telemetry
      @unknown_raise = ConfigParser.handle_true_false(unknown_raise)
      @received_time = nil
      @target_name = nil
      @packet_name = nil
    end

    # Set the received_time, target_name and packet_name which we recorded when
    # we identified this packet. The server will also do this but since we know
    # the information here, we perform this optimization.
    def read_packet(packet)
      packet.received_time = @received_time
      packet.target_name = @target_name
      packet.packet_name = @packet_name
      return packet
    end

    # protected

    # Identifies an unknown buffer of data as a Packet. The raw data is
    # returned but the packet that matched is recorded so it can be set in the
    # read_packet callback.
    #
    # @return [String|Symbol] The identified packet data or :STOP if more data
    #   is required to build a packet
    def identify_and_finish_packet
      packet_data = nil
      identified_packet = nil

      if @telemetry
        target_names = @interface.tlm_target_names
      else
        target_names = @interface.cmd_target_names
      end

      target_names.each do |target_name|
        target_packets = nil
        unique_id_mode = false
        begin
          if @telemetry
            target_packets = System.telemetry.packets(target_name)
            unique_id_mode = System.telemetry.tlm_unique_id_mode(target_name)
          else
            target_packets = System.commands.packets(target_name)
            unique_id_mode = System.commands.cmd_unique_id_mode(target_name)
          end
        rescue RuntimeError
          # No commands/telemetry for this target
          next
        end

        if unique_id_mode
          target_packets.each do |_packet_name, packet|
            if not packet.subpacket and packet.identify?(@data[@discard_leading_bytes..-1]) # identify? handles virtual
              identified_packet = packet
              break
            end
          end
        else
          # Do a hash lookup to quickly identify the packet
          if target_packets.length > 0
            packet = nil
            target_packets.each do |_packet_name, target_packet|
              next if target_packet.virtual
              next if target_packet.subpacket
              packet = target_packet
              break
            end
            if packet
              key = packet.read_id_values(@data[@discard_leading_bytes..-1])
              if @telemetry
                hash = System.telemetry.config.tlm_id_value_hash[target_name]
              else
                hash = System.commands.config.cmd_id_value_hash[target_name]
              end
              identified_packet = hash[key]
              identified_packet = hash['CATCHALL'.freeze] unless identified_packet
            end
          end
        end

        if identified_packet
          if identified_packet.defined_length + @discard_leading_bytes > @data.length
            # Check if need more data to finish packet
            return :STOP
          end

          # Set some variables so we can update the packet in
          # read_packet
          @received_time = Time.now.sys
          @target_name = identified_packet.target_name
          @packet_name = identified_packet.packet_name

          # Get the data from this packet
          # Previous implementation looked like the following:
          #   packet_data = @data.slice!(0, identified_packet.defined_length + @discard_leading_bytes)
          # But slice! is 6x slower at small packets (1024)
          # and 1000x slower at large packets (1Mb)
          # Run test/benchmarks/string_mod_benchmark.rb for details

          # Triple dot range because it's effectively a length calculation and we start with 0
          packet_data = @data[0...(identified_packet.defined_length + @discard_leading_bytes)]
          @data = @data[(identified_packet.defined_length + @discard_leading_bytes)..-1]
          break
        end
      end

      unless identified_packet
        raise "Unknown data received by FixedProtocol" if @unknown_raise

        # Unknown packet? Just return all the current data
        @received_time = nil
        @target_name = nil
        @packet_name = nil
        packet_data = @data.clone
        @data.replace('')
      end

      return packet_data, @extra
    end

    def reduce_to_single_packet
      return :STOP if @data.length < @min_id_size

      identify_and_finish_packet()
    end

    def write_details
      result = super()
      result['min_id_size'] = @min_id_size
      result['telemetry'] = @telemetry
      result['unknown_raise'] = @unknown_raise
      return result
    end

    def read_details
      result = super()
      result['min_id_size'] = @min_id_size
      result['telemetry'] = @telemetry
      result['unknown_raise'] = @unknown_raise
      return result
    end
  end
end
