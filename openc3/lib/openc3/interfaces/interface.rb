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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/api/api'
require 'openc3/logs/stream_log_pair'
require 'openc3/utilities/secrets'
require 'rufus-scheduler'

module OpenC3
  # Define a class to allow interfaces and protocols to reject commands without
  # disconnecting the interface
  class WriteRejectError < StandardError
  end

  # Defines all the attributes and methods common to all interface classes
  # used by OpenC3.
  class Interface
    include Api

    # @return [String] Name of the interface
    attr_reader :name

    # @return [String] State of the interface: CONNECTED, ATTEMPTING, DISCONNECTED
    attr_accessor :state

    # @return [Array<String>] Array of target names associated with this interface
    attr_accessor :target_names

    # @return [Array<String>] Array of cmd target names associated with this interface
    attr_accessor :cmd_target_names

    # @return [Array<String>] Array of tlm target names associated with this interface
    attr_accessor :tlm_target_names

    # @return [Boolean] Flag indicating if the interface should be connected
    #   to on startup
    attr_accessor :connect_on_startup

    # @return [Boolean] Flag indicating if the interface should automatically
    #   reconnect after losing connection
    attr_accessor :auto_reconnect

    # @return [Integer[ Delay between reconnect attempts
    attr_accessor :reconnect_delay

    # @return [Boolean] Flag indicating if the user is allowed to disconnect
    #   this interface
    attr_accessor :disable_disconnect

    # @return [Array] Array of packet logger classes for this interface
    attr_accessor :packet_log_writer_pairs

    # @return [Array] Array of stored packet log writers
    attr_accessor :stored_packet_log_writer_pairs

    # @return [StreamLogPair] StreamLogPair instance or nil
    attr_accessor :stream_log_pair

    # @return [Array<Routers>] Array of routers that receive packets
    #   read from the interface
    attr_accessor :routers

    # @return [Array<Routers>] Array of cmd routers that mirror packets
    #   sent from the interface
    attr_accessor :cmd_routers

    # @return [Integer] The number of packets read from this interface
    attr_accessor :read_count

    # @return [Integer] The number of packets written to this interface
    attr_accessor :write_count

    # @return [Integer] The number of bytes read from this interface
    attr_accessor :bytes_read

    # @return [Integer] The number of bytes written to this interface
    attr_accessor :bytes_written

    # @return [Integer] The number of active clients
    #   (when used as a Router)
    attr_accessor :num_clients

    # @return [Integer] The number of packets in the read queue
    #   (when used as a Router)
    attr_accessor :read_queue_size

    # @return [Integer] The number of packets in the write queue
    #   (when used as a Router)
    attr_accessor :write_queue_size

    # @return [Hash<option name, option values>] Hash of options supplied to interface/router
    attr_accessor :options

    # @return [Array<Protocol>] Array of protocols for reading
    attr_accessor :read_protocols

    # @return [Array<Protocol>] Array of protocols for writing
    attr_accessor :write_protocols

    # @return [Array<[Protocol Class, Protocol Args, Protocol kind (:READ, :WRITE, :READ_WRITE)>] Info to recreate protocols
    attr_accessor :protocol_info

    # @return [String] Most recently read raw data
    attr_accessor :read_raw_data

    # @return [String] Most recently written raw data
    attr_accessor :written_raw_data

    # @return [Time] Most recent read raw data time
    attr_accessor :read_raw_data_time

    # @return [Time] Most recent written raw data time
    attr_accessor :written_raw_data_time

    # @return [Array] Config params from the INTERFACE config line
    attr_accessor :config_params

    # @return [Array<Interface>] Array of interfaces to route packets to
    #   (when used as a BridgeRouter)
    attr_accessor :interfaces

    # @return [Secrets] Interface secrets manager class
    attr_accessor :secrets

    # @return [Scheduler] Scheduler used for periodic commanding
    attr_accessor :scheduler

    # Initialize default attribute values
    def initialize
      @name = self.class.to_s.split("::")[-1] # Remove namespacing if present
      @state = 'DISCONNECTED'
      @target_names = []
      @cmd_target_names = []
      @tlm_target_names = []
      @connect_on_startup = true
      @auto_reconnect = true
      @reconnect_delay = 5.0
      @disable_disconnect = false
      @packet_log_writer_pairs = []
      @stored_packet_log_writer_pairs = []
      @routers = []
      @cmd_routers = []
      @read_count = 0
      @write_count = 0
      @bytes_read = 0
      @bytes_written = 0
      @num_clients = 0
      @read_queue_size = 0
      @write_queue_size = 0
      @write_mutex = Mutex.new
      @read_allowed = true
      @write_allowed = true
      @write_raw_allowed = true
      @options = {}
      @read_protocols = []
      @write_protocols = []
      @protocol_info = []
      @read_raw_data = ''
      @written_raw_data = ''
      @read_raw_data_time = nil
      @written_raw_data_time = nil
      @config_params = []
      @interfaces = []
      @secrets = Secrets.getClient
      @scheduler = nil
    end

    # Should be implemented by subclass to return human readable connection string
    # which will be placed in log messages when connecting and during connection failures
    def connection_string
      return @name
    end

    # Connects the interface to its target(s). Must be implemented by a
    # subclass.
    def connect
      (@read_protocols | @write_protocols).each { |protocol| protocol.connect_reset }

      periodic_cmds = @options['PERIODIC_CMD']
      if periodic_cmds
        if not @scheduler
          @scheduler = Rufus::Scheduler.new

          periodic_cmds.each do |log_dont_log, period, cmd_string|
            log_dont_log.upcase!
            period = "#{period.to_f}s"
            @scheduler.every period do
              if connected?()
                begin
                  if log_dont_log == 'DONT_LOG'
                    cmd(cmd_string, log_message: false)
                  else
                    cmd(cmd_string)
                  end
                rescue Exception => e
                  Logger.error("Error sending periodic cmd(#{cmd_string}):\n#{e.formatted}")
                end
              end
            end
          end
        else
          @scheduler.resume
        end
      end
    end

    # Called immediately after the interface is connected.
    # By default this method will run any commands specified by the CONNECT_CMD option
    def post_connect
      connect_cmds = @options['CONNECT_CMD']
      if connect_cmds
        connect_cmds.each do |log_dont_log, cmd_string|
          if log_dont_log.upcase == 'DONT_LOG'
            cmd(cmd_string, log_message: false)
          else
            cmd(cmd_string)
          end
        end
      end
    end

    # Indicates if the interface is connected to its target(s) or not. Must be
    # implemented by a subclass.
    def connected?
      raise "connected? not defined by Interface"
    end

    # Disconnects the interface from its target(s). Must be implemented by a
    # subclass.
    def disconnect
      periodic_cmds = @options['PERIODIC_CMD']
      if periodic_cmds and @scheduler
        @scheduler.pause
      end

      (@read_protocols | @write_protocols).each { |protocol| protocol.disconnect_reset }
    end

    def read_interface
      raise "read_interface not defined by Interface"
    end

    def write_interface(_data, _extra = nil)
      raise "write_interface not defined by Interface"
    end

    # Retrieves the next packet from the interface.
    # @return [Packet] Packet constructed from the data. Packet will be
    #   unidentified (nil target and packet names)
    def read
      raise "Interface not connected for read: #{@name}" unless connected?
      raise "Interface not readable: #{@name}" unless read_allowed?

      first = true
      loop do
        # Protocols may have cached data for a packet, so initially just inject a blank string
        # Otherwise we can hold off outputting other packets where all the data has already
        # been received
        extra = nil
        if !first or @read_protocols.length <= 0
          # Read data for a packet
          data, extra = read_interface()
          unless data
            Logger.info("#{@name}: read_interface requested disconnect")
            return nil
          end
        else
          data = ''
          first = false
        end

        @read_protocols.each do |protocol|
          # Extra check is for backwards compatibility
          if extra
            data, extra = protocol.read_data(data, extra)
          else
            data, extra = protocol.read_data(data)
          end
          if data == :DISCONNECT
            Logger.info("#{@name}: Protocol #{protocol.class} read_data requested disconnect")
            return nil
          end
          break if data == :STOP
        end
        next if data == :STOP

        # Extra check is for backwards compatibility
        if extra
          packet = convert_data_to_packet(data, extra)
        else
          packet = convert_data_to_packet(data)
        end

        # Potentially modify packet
        @read_protocols.each do |protocol|
          packet = protocol.read_packet(packet)
          if packet == :DISCONNECT
            Logger.info("#{@name}: Protocol #{protocol.class} read_packet requested disconnect")
            return nil
          end
          break if packet == :STOP
        end
        next if packet == :STOP

        # Return packet
        @read_count += 1
        Logger.warn("#{@name}: Interface unexpectedly requested disconnect") unless packet
        return packet
      end
    rescue Exception => e
      Logger.error("#{@name}: Error reading from interface")
      disconnect()
      raise e
    end

    # Method to send a packet on the interface.
    # @param packet [Packet] The Packet to send out the interface
    def write(packet)
      raise "Interface not connected for write: #{@name}" unless connected?
      raise "Interface not writable: #{@name}" unless write_allowed?

      _write do
        @write_count += 1

        # Potentially modify packet
        @write_protocols.each do |protocol|
          packet = protocol.write_packet(packet)
          if packet == :DISCONNECT
            Logger.info("#{@name}: Protocol #{protocol.class} write_packet requested disconnect")
            disconnect()
            return
          end
          return if packet == :STOP
        end

        data, extra = convert_packet_to_data(packet)

        # Potentially modify packet data
        @write_protocols.each do |protocol|
          # Extra check is for backwards compatibility
          if extra
            data, extra = protocol.write_data(data, extra)
          else
            data, extra = protocol.write_data(data)
          end
          if data == :DISCONNECT
            Logger.info("#{@name}: Protocol #{protocol.class} write_data requested disconnect")
            disconnect()
            return
          end
          return if data == :STOP
        end

        # Actually write out data if not handled by protocol
        # Extra check is for backwards compatibility
        if extra
          write_interface(data, extra)
        else
          write_interface(data)
        end

        # Potentially block and wait for response
        @write_protocols.each do |protocol|
          if extra
            packet, data, extra = protocol.post_write_interface(packet, data, extra)
          else
            packet, data, extra = protocol.post_write_interface(packet, data)
          end
          if packet == :DISCONNECT
            Logger.info("#{@name}: Protocol #{protocol.class} post_write_packet requested disconnect")
            disconnect()
            return
          end
          return if packet == :STOP
        end
      end

      return nil
    end

    # Writes preformatted data onto the interface. Malformed data may cause
    # problems.
    # @param data [String] The raw data to send out the interface
    def write_raw(data, extra = nil)
      raise "Interface not connected for write_raw: #{@name}" unless connected?
      raise "Interface not write-rawable: #{@name}" unless write_raw_allowed?

      _write do
        write_interface(data, extra)
      end
    end

    # Wrap all writes in a mutex and handle errors
    def _write
      if @write_mutex.owned?
        yield
      else
        @write_mutex.synchronize { yield }
      end
    rescue WriteRejectError => e
      Logger.error("#{@name}: Write rejected by interface: #{e.message}")
      raise e
    rescue Exception => e
      Logger.error("#{@name}: Error writing to interface")
      disconnect()
      raise e
    end

    def as_json(*_a)
      config = {}
      config['name'] = @name
      config['state'] = @state
      config['clients'] = self.num_clients
      config['txsize'] = @write_queue_size
      config['rxsize'] = @read_queue_size
      config['txbytes'] = @bytes_written
      config['rxbytes'] = @bytes_read
      config['txcnt'] = @write_count
      config['rxcnt'] = @read_count
      config
    end

    # @return [Boolean] Whether reading is allowed
    def read_allowed?
      @read_allowed
    end

    # @return [Boolean] Whether writing is allowed
    def write_allowed?
      @write_allowed
    end

    # @return [Boolean] Whether writing raw data over the interface is allowed
    def write_raw_allowed?
      @write_raw_allowed
    end

    # Start raw logging for this interface
    def start_raw_logging
      @stream_log_pair = StreamLogPair.new(@name) unless @stream_log_pair
      @stream_log_pair.start
    end

    # Stop raw logging for this interface
    def stop_raw_logging
      @stream_log_pair.stop if @stream_log_pair
    end

    # Set the interface name
    def name=(name)
      @name = name.to_s.clone
      @stream_log_pair.name = name if @stream_log_pair
    end

    # Copy settings from this interface to another interface. All instance
    # variables are copied except for num_clients, read_queue_size,
    # and write_queue_size since these are all specific to the operation of the
    # interface rather than its instantiation.
    #
    # @param other_interface [Interface] The other interface to copy to
    def copy_to(other_interface)
      other_interface.name = self.name.clone
      other_interface.target_names = self.target_names.clone
      other_interface.cmd_target_names = self.cmd_target_names.clone
      other_interface.tlm_target_names = self.tlm_target_names.clone
      other_interface.connect_on_startup = self.connect_on_startup
      other_interface.auto_reconnect = self.auto_reconnect
      other_interface.reconnect_delay = self.reconnect_delay
      other_interface.disable_disconnect = self.disable_disconnect
      other_interface.packet_log_writer_pairs = self.packet_log_writer_pairs.clone
      other_interface.routers = self.routers.clone
      other_interface.cmd_routers = self.cmd_routers.clone
      other_interface.read_count = self.read_count
      other_interface.write_count = self.write_count
      other_interface.bytes_read = self.bytes_read
      other_interface.bytes_written = self.bytes_written
      other_interface.stream_log_pair = self.stream_log_pair.clone if @stream_log_pair
      # num_clients is per interface so don't copy
      # read_queue_size is the number of packets in the queue so don't copy
      # write_queue_size is the number of packets in the queue so don't copy
      self.options.each do |option_name, option_values|
        other_interface.set_option(option_name, option_values)
      end
      other_interface.protocol_info = []
      self.protocol_info.each do |protocol_class, protocol_args, read_write|
        unless read_write == :PARAMS
          other_interface.add_protocol(protocol_class, protocol_args, read_write)
        end
      end
    end

    # Set an interface or router specific option
    # @param option_name name of the option
    # @param option_values array of option values
    def set_option(option_name, option_values)
      option_name_upcase = option_name.upcase

      # CONNECT_CMD and PERIODIC_CMD are special because there could be more than 1
      # so we store them in an array for processing during connect()
      if option_name_upcase == 'PERIODIC_CMD' or option_name_upcase == 'CONNECT_CMD'
        # OPTION PERIODIC_CMD LOG/DONT_LOG 1.0 "INST COLLECT with TYPE NORMAL"
        @options[option_name_upcase] ||= []
        @options[option_name_upcase] << option_values.clone
      else
        @options[option_name_upcase] = option_values.clone
      end
    end

    # Called to convert the read data into a OpenC3 Packet object
    #
    # @param data [String] Raw packet data
    # @return [Packet] OpenC3 Packet with buffer filled with data
    def convert_data_to_packet(data, extra = nil)
      packet = Packet.new(nil, nil, :BIG_ENDIAN, nil, data)
      packet.extra = extra
      return packet
    end

    # Called to convert a packet into the data to send
    #
    # @param packet [Packet] Packet to extract data from
    # @return data
    def convert_packet_to_data(packet)
      return packet.buffer(true), packet.extra # Copy buffer so logged command isn't modified
    end

    # Called to read data and manipulate it until enough data is
    # returned. The definition of 'enough data' changes depending on the
    # protocol used which is why this method exists. This method is also used
    # to perform operations on the data before it can be interpreted as packet
    # data such as decryption. After this method is called the post_read_data
    # method is called. Subclasses must implement this method.
    #
    # @return [String] Raw packet data
    def read_interface_base(data, _extra = nil)
      @read_raw_data_time = Time.now
      @read_raw_data = data.clone
      @bytes_read += data.length
      @stream_log_pair.read_log.write(data) if @stream_log_pair
    end

    # Called to write data to the underlying interface. Subclasses must
    # implement this method and call super to count the raw bytes and allow raw
    # logging.
    #
    # @param data [String] Raw packet data
    # @return [String] The exact data written
    def write_interface_base(data, _extra = nil)
      @written_raw_data_time = Time.now
      @written_raw_data = data.clone
      @bytes_written += data.length
      @stream_log_pair.write_log.write(data) if @stream_log_pair
    end

    def add_protocol(protocol_class, protocol_args, read_write)
      protocol_args = protocol_args.clone
      protocol = protocol_class.new(*protocol_args)
      case read_write
      when :READ
        @read_protocols << protocol
      when :WRITE
        @write_protocols.unshift(protocol)
      when :READ_WRITE, :PARAMS
        @read_protocols << protocol
        @write_protocols.unshift(protocol)
      else
        raise "Unknown protocol descriptor: #{read_write}. Must be :READ, :WRITE, or :READ_WRITE."
      end
      @protocol_info << [protocol_class, protocol_args, read_write]
      protocol.interface = self
      return protocol
    end

    def interface_cmd(cmd_name, *_cmd_args)
      if cmd_name == 'clear_counters'
        @write_queue_size = 0
        @read_queue_size = 0
        @bytes_written = 0
        @bytes_read = 0
        @write_count = 0
        @read_count = 0
      end
    end

    def protocol_cmd(cmd_name, *cmd_args, read_write: :READ_WRITE, index: -1)
      read_write = read_write.to_s.upcase.intern
      raise "Unknown protocol descriptor: #{read_write}. Must be :READ, :WRITE, or :READ_WRITE." unless [:READ, :WRITE, :READ_WRITE].include?(read_write)
      handled = false

      if index >= 0 or read_write == :READ_WRITE
        # Reconstruct full list of protocols in correct order
        protocols = []
        read_protocols = @read_protocols
        write_protocols = @write_protocols.reverse
        read_index = 0
        write_index = 0
        @protocol_info.each do |_protocol_class, _protocol_args, protocol_read_write|
          case protocol_read_write
          when :READ
            protocols << read_protocols[read_index]
            read_index += 1
          when :WRITE
            protocols << write_protocols[write_index]
            write_index += 1
          when :READ_WRITE, :PARAMS
            protocols << read_protocols[read_index]
            read_index += 1
            write_index += 1
          end
        end

        protocols.each_with_index do |protocol, protocol_index|
          # If index is given that is all that matters
          result = protocol.protocol_cmd(cmd_name, *cmd_args) if index == protocol_index or index == -1
          handled = true if result
        end
      elsif read_write == :READ # and index == -1
        @read_protocols.each do |protocol|
          result = protocol.protocol_cmd(cmd_name, *cmd_args)
          handled = true if result
        end
      else # read_write == :WRITE and index == -1
        @write_protocols.each do |protocol|
          result = protocol.protocol_cmd(cmd_name, *cmd_args)
          handled = true if result
        end
      end
      return handled
    end
  end
end
