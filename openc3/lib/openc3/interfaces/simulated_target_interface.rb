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

require 'openc3/interfaces/interface'

module OpenC3
  # An interface class that provides simulated telemetry and command responses
  class SimulatedTargetInterface < Interface
    # @param sim_target_file [String] Filename of the simulator target class
    def initialize(sim_target_file)
      super()
      @connected = false
      @initialized = false
      @count_100hz = 0
      @next_tick_time = nil
      @pending_packets = []
      @sim_target_class = OpenC3.require_class sim_target_file
      @sim_target = nil
      @write_raw_allowed = false
    end

    def connection_string
      return @sim_target_class.to_s
    end

    # Initialize the simulated target object and "connect" to the target
    def connect
      unless @initialized
        # Create Simulated Target Object
        @sim_target = @sim_target_class.new(@target_names[0])
        # Set telemetry rates
        @sim_target.set_rates

        @initialized = true
      end

      @count_100hz = 0

      # Save the current time + delta as the next expected tick time
      @next_tick_time = Time.now.sys + @sim_target.tick_period_seconds

      super()
      @connected = true
    end

    # @return [Boolean] Whether the simulated target is connected (initialized)
    def connected?
      @connected
    end

    # @return [Packet] Returns a simulated target packet from the simulator
    def read
      packet = nil
      if @connected
        while true
          packet = first_pending_packet()
          break unless packet
          # Support read_packet (but not read data) in protocols
          # Generic protocol use is not supported
          @read_protocols.each do |protocol|
            packet = protocol.read_packet(packet)
            if packet == :DISCONNECT
              Logger.info("#{@name}: Protocol #{protocol.class} read_packet requested disconnect")
              return nil
            end
            break if packet == :STOP
          end
          return packet unless packet == :STOP
        end

        while true
          # Calculate time to sleep to make ticks the right distance apart
          now = Time.now.sys
          delta = @next_tick_time - now
          if delta > 0.0
            sleep(delta) # Sleep between packets
            return nil unless @connected
          elsif delta < -1.0
            # Fell way behind - jump next tick time
            @next_tick_time = Time.now.sys
          end

          @pending_packets = @sim_target.read(@count_100hz, @next_tick_time)
          @next_tick_time += @sim_target.tick_period_seconds
          @count_100hz += @sim_target.tick_increment

          packet = first_pending_packet()
          if packet
            # Support read_packet (but not read data) in protocols
            # Generic protocol use is not supported
            @read_protocols.each do |protocol|
              packet = protocol.read_packet(packet)
              if packet == :DISCONNECT
                Logger.info("#{@name}: Protocol #{protocol.class} read_packet requested disconnect")
                return nil
              end
              break if packet == :STOP
            end
            next if packet == :STOP

            return packet
          end
        end
      else
        raise "Interface not connected"
      end
      return packet
    end

    # @param packet [Packet] Command packet to send to the simulator
    def write(packet)
      if @connected
        # Update count of commands sent through this interface
        @write_count += 1
        @bytes_written += packet.length
        @written_raw_data_time = Time.now
        @written_raw_data = packet.buffer

        # Have simulated target handle the packet
        @sim_target.write(packet)
      else
        raise "Interface not connected"
      end
    end

    # write_raw is not implemented and will raise a RuntimeError
    def write_raw(_data)
      raise "write_raw not implemented for SimulatedTargetInterface"
    end

    # Raise an error because raw logging is not supported for this interface
    def stream_log_pair=(_stream_log_pair)
      raise "Raw logging not supported for SimulatedTargetInterface"
    end

    # Disconnect from the simulator
    def disconnect
      @connected = false
      super()
    end

    # protected

    def first_pending_packet
      packet = nil
      unless @pending_packets.empty?
        @read_count += 1
        packet = @pending_packets.pop.clone
        @bytes_read += packet.length
        @read_raw_data_time = Time.now
        @read_raw_data = packet.buffer
      end
      packet
    end
  end
end
