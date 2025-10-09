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

require 'socket'
require 'timeout' # For Timeout::Error
require 'openc3/interfaces/stream_interface'
require 'openc3/streams/tcpip_socket_stream'
require 'openc3/config/config_parser'

module OpenC3
  # TCP/IP Server which can both read and write on a single port or two
  # independent ports. A listen thread is setup which waits for client
  # connections. For each connection to the read port, a thread is spawned that
  # calls the read method from the interface. This data is then
  # available by calling the TcpipServer read method. For each connection to the
  # write port, a thread is spawned that calls the write method from the
  # interface when data is send to the TcpipServer via the write method.
  class TcpipServerInterface < StreamInterface
    # Data class which stores the interface and associated information
    class InterfaceInfo
      attr_reader :interface, :hostname, :host_ip, :port

      def initialize(interface, hostname, host_ip, port)
        @interface = interface
        @hostname = hostname
        @host_ip = host_ip
        @port = port
      end
    end

    # Callback method to call when a new client connects to the write port.
    # This method will be called with the Interface as the only argument.
    attr_accessor :write_connection_callback
    # Callback method to call when a new client connects to the read port.
    # This method will be called with the Interface as the only argument.
    attr_accessor :read_connection_callback
    # @return [StreamLogPair] StreamLogPair instance or nil
    attr_accessor :stream_log_pair
    # @return [String] The ip address to bind to.  Default to ANY (0.0.0.0)
    attr_accessor :listen_address

    # @param write_port [Integer] The server write port. Clients should connect
    #   and expect to receive data from this port.
    # @param read_port [Integer] The server read port. Clients should connect
    #   and expect to send data to this port.
    # @param write_timeout [Float] Seconds to wait before aborting writes
    # @param read_timeout [Float|nil] Seconds to wait before aborting reads.
    #   Pass nil to block until the read is complete.
    # @param protocol_type [String] The name of the stream to
    #   use for both the read and write ports. This name is combined with
    #   'Protocol' to result in a OpenC3 Protocol class.
    # @param protocol_args [Array] Arguments to pass to the Protocol
    def initialize(write_port,
                   read_port,
                   write_timeout,
                   read_timeout,
                   protocol_type = nil,
                   *protocol_args)
      super(protocol_type, protocol_args)
      @write_port = ConfigParser.handle_nil(write_port)
      @write_port = Integer(write_port) if @write_port
      @read_port = ConfigParser.handle_nil(read_port)
      @read_port = Integer(read_port) if @read_port
      @write_timeout = ConfigParser.handle_nil(write_timeout)
      @write_timeout = @write_timeout.to_f if @write_timeout
      @read_timeout = ConfigParser.handle_nil(read_timeout)
      @read_timeout = @read_timeout.to_f if @read_timeout
      @listen_sockets = []
      @listen_pipes = []
      @listen_threads = []
      @read_threads = []
      @write_thread = nil
      @write_raw_thread = nil
      @write_interface_infos = []
      @read_interface_infos = []
      @write_queue = nil
      @write_queue = Queue.new if @write_port
      @write_raw_queue = nil
      @write_raw_queue = Queue.new if @write_port
      @read_queue = nil
      @read_queue = Queue.new if @read_port
      @write_condition_variable = nil
      @write_condition_variable = ConditionVariable.new if @write_port
      @write_raw_mutex = nil
      @write_raw_mutex = Mutex.new if @write_port
      @write_raw_condition_variable = nil
      @write_raw_condition_variable = ConditionVariable.new if @write_port
      @write_connection_callback = nil
      @read_connection_callback = nil
      @stream_log_pair = nil
      @raw_logging_enabled = false
      @connection_mutex = Mutex.new
      @listen_address = "0.0.0.0"

      @read_allowed = false unless ConfigParser.handle_nil(read_port)
      @write_allowed = false unless ConfigParser.handle_nil(write_port)
      @write_raw_allowed = false unless ConfigParser.handle_nil(write_port)

      @connected = false
    end

    def connection_string
      if @write_port == @read_port
        return "listening on #{@listen_address}:#{@write_port} (R/W)"
      end
      result = "listening on"
      result += " #{@listen_address}:#{@write_port} (write)" if @write_port
      result += " #{@listen_address}:#{@read_port} (read)" if @read_port
      return result
    end

    # Create the read and write port listen threads. Incoming connections will
    # spawn separate threads to process the reads and writes.
    def connect
      @cancel_threads = false
      @read_queue.clear if @read_queue
      if @write_port == @read_port # One socket
        start_listen_thread(@read_port, true, true)
      else
        start_listen_thread(@write_port, true, false) if @write_port
        start_listen_thread(@read_port, false, true) if @read_port
      end

      if @write_port
        @write_thread = Thread.new do
          loop do
            write_thread_body()
            break if @cancel_threads
          end
        rescue Exception => e
          shutdown_interfaces(@write_interface_infos)
          Logger.error("#{@name}: Tcpip server write thread unexpectedly died")
          Logger.error(e.formatted)
        end
        @write_raw_thread = Thread.new do
          loop do
            write_raw_thread_body()
            break if @cancel_threads
          end
        rescue Exception => e
          shutdown_interfaces(@write_interface_infos)
          Logger.error("#{@name}: Tcpip server write raw thread unexpectedly died")
          Logger.error(e.formatted)
        end
      else
        @write_thread = nil
        @write_raw_thread = nil
      end
      super()
      @connected = true
    end

    # @return [Boolean] Whether the server is listening for connections
    def connected?
      @connected
    end

    # Shutdowns the listener threads for both the read and write ports as well
    # as any client connections.
    def disconnect
      @cancel_threads = true
      @read_queue << nil if @read_queue
      @listen_pipes.each do |pipe|
        pipe.write('.')
      rescue Exception
        # Oh well
      end
      @listen_pipes.clear

      # Shutdown listen thread(s)
      @listen_threads.each { |listen_thread| OpenC3.kill_thread(self, listen_thread) }
      @listen_threads.clear

      # Shutdown listen socket(s)
      @listen_sockets.each do |listen_socket|
        OpenC3.close_socket(listen_socket)
      rescue IOError
        # Ok may have been closed by the thread
      end
      @listen_sockets.clear

      # This will unblock read threads
      shutdown_interfaces(@read_interface_infos)

      @read_threads.each { |thread| OpenC3.kill_thread(self, thread) }
      @read_threads.clear
      if @write_thread
        OpenC3.kill_thread(self, @write_thread)
        @write_thread = nil
      end
      if @write_raw_thread
        OpenC3.kill_thread(self, @write_raw_thread)
        @write_raw_thread = nil
      end

      shutdown_interfaces(@write_interface_infos)
      @connected = false
      super()
    end

    # Gracefully kill all the threads
    def graceful_kill
      # This method is just here to prevent warnings
    end

    # @return [Packet] Latest packet read from any of the connected clients.
    #   Note this method blocks until data is available.
    def read
      raise "Interface not connected for read: #{@name}" unless connected?
      raise "Interface not readable: #{@name}" unless read_allowed?

      packet = @read_queue.pop
      return nil unless packet

      @read_count += 1
      packet
    end

    # @param packet [Packet] Packet to write to all clients connected to the
    #   write port.
    def write(packet)
      raise "Interface not connected for write: #{@name}" unless connected?
      raise "Interface not writable: #{@name}" unless write_allowed?

      @write_count += 1
      @write_queue << packet.clone
      @write_condition_variable.broadcast
    end

    # @param data [String] Data to write to all clients connected to the
    #   write port.
    def write_raw(data)
      raise "Interface not connected for write_raw: #{@name}" unless connected?
      raise "Interface not write-rawable: #{@name}" unless write_raw_allowed?

      @write_raw_queue << data
      @write_raw_condition_variable.broadcast
      return data
    end

    # @return [Integer] The number of packets waiting on the read queue
    def read_queue_size
      @read_queue ? @read_queue.size : 0
    end

    # @return [Integer] The number of packets waiting on the write queue
    def write_queue_size
      @write_queue ? @write_queue.size : 0
    end

    # @return [Integer] The number of connected clients
    def num_clients
      interfaces = []
      @write_interface_infos.each { |wii| interfaces << wii.interface }
      @read_interface_infos.each { |rii| interfaces << rii.interface }
      interfaces.uniq.length
    end

    # Start raw logging for this interface
    def start_raw_logging
      @raw_logging_enabled = true
      change_raw_logging(:start)
    end

    # Stop raw logging for this interface
    def stop_raw_logging
      @raw_logging_enabled = false
      change_raw_logging(:stop)
    end

    # Supported Options
    # LISTEN_ADDRESS - Ip address of the interface to accept connections on - Default: 0.0.0.0
    # (see Interface#set_option)
    def set_option(option_name, option_values)
      super(option_name, option_values)
      if option_name.upcase == 'LISTEN_ADDRESS'
        @listen_address = option_values[0]
      end
    end

    # protected

    def shutdown_interfaces(interface_infos)
      @connection_mutex.synchronize do
        interface_infos.each do |interface_info|
          interface_info.interface.disconnect
          interface_info.interface.stream_log_pair.stop if interface_info.interface.stream_log_pair
        end
        interface_infos.clear
      end
    end

    def change_raw_logging(method)
      if @stream_log_pair
        @write_interface_infos.each do |interface_info|
          interface_info.interface.stream_log_pair.public_send(method) if interface_info.interface.stream_log_pair
        end
        @read_interface_infos.each do |interface_info|
          interface_info.interface.stream_log_pair.public_send(method) if interface_info.interface.stream_log_pair
        end
      end
    end

    def start_listen_thread(port, listen_write = false, listen_read = false)
      # Create a socket to accept connections from clients
      addr = Socket.pack_sockaddr_in(port, @listen_address)
      if RUBY_ENGINE == 'ruby'
        listen_socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
        listen_socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1) unless Kernel.is_windows?
        begin
          listen_socket.bind(addr)
        rescue Errno::EADDRINUSE
          raise "Error binding to port #{port}.\n" +
                "Either another application is using this port\n" +
                "or the operating system is being slow cleaning up.\n" +
                "Make sure all sockets/streams are closed in all applications,\n" +
                "wait 1 minute and try again."
        end

        listen_socket.listen(5)
      else
        listen_socket = ServerSocket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
        listen_socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1) unless Kernel.is_windows?
        begin
          listen_socket.bind(addr, 5)
        rescue Errno::EADDRINUSE
          raise "Error binding to port #{port}.\n" +
                "Either another application is using this port\n" +
                "or the operating system is being slow cleaning up.\n" +
                "Make sure all sockets/streams are closed in all applications,\n" +
                "wait 1 minute and try again."
        end
      end
      @listen_sockets << listen_socket
      @listen_threads << Thread.new do
        thread_reader, thread_writer = IO.pipe
        @listen_pipes << thread_writer
        loop do
          listen_thread_body(listen_socket, listen_write, listen_read, thread_reader)
          break if @cancel_threads
        end
      rescue => e
        Logger.error("#{@name}: Tcpip server listen thread unexpectedly died")
        Logger.error(e.formatted)
      end
    end

    def listen_thread_body(listen_socket, listen_write, listen_read, thread_reader)
      begin
        socket, address = listen_socket.accept_nonblock
      rescue Errno::EAGAIN, Errno::ECONNABORTED, Errno::EINTR, Errno::EWOULDBLOCK
        read_ready, _ = IO.select([listen_socket, thread_reader])
        if read_ready && read_ready.include?(thread_reader)
          return
        else
          retry
        end
      end

      port, host_ip = Socket.unpack_sockaddr_in(address)
      hostname = ''
      hostname = Socket.lookup_hostname_from_ip(host_ip)
      # if System.instance.acl
      #   addr = ["AF_INET", 10, "lc630", host_ip.to_s]
      #   if not System.instance.acl.allow_addr?(addr)
      #     # Reject connection
      #     OpenC3.close_socket(socket)
      #     Logger.info "#{@name}: Tcpip server rejected connection from #{hostname}(#{host_ip}):#{port}"
      #     return
      #   end
      # end

      # Configure TCP_NODELAY option
      socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

      # Accept Connection
      write_socket = nil
      read_socket = nil
      write_socket = socket if listen_write
      read_socket = socket if listen_read
      stream = TcpipSocketStream.new(write_socket, read_socket, @write_timeout, @read_timeout)

      # Pass down options to the stream
      @options.each do |option_name, option_values|
        stream.set_option(option_name, option_values)
      end

      interface = StreamInterface.new
      interface.target_names = @target_names
      interface.cmd_target_names = @cmd_target_names
      interface.tlm_target_names = @tlm_target_names
      if @stream_log_pair
        interface.stream_log_pair = @stream_log_pair.clone
        interface.stream_log_pair.start if @raw_logging_enabled
      end
      @protocol_info.each do |protocol_class, protocol_args, read_write|
        interface.add_protocol(protocol_class, protocol_args, read_write)
      end
      interface.stream = stream
      interface.connect

      if listen_write
        @write_connection_callback.call(interface) if @write_connection_callback
        @connection_mutex.synchronize do
          @write_interface_infos << InterfaceInfo.new(interface, hostname, host_ip, port)
        end
      end
      if listen_read
        @read_connection_callback.call(interface) if @read_connection_callback
        @connection_mutex.synchronize do
          @read_interface_infos << InterfaceInfo.new(interface, hostname, host_ip, port)
        end
        start_read_thread(@read_interface_infos[-1])
      end
      Logger.info "#{@name}: Tcpip server accepted connection from #{hostname}(#{host_ip}):#{port}"
    end

    def start_read_thread(interface_info)
      @read_threads << Thread.new do
        index_to_delete = nil
        begin
          begin
            read_thread_body(interface_info.interface)
          rescue Exception => e
            Logger.error "#{@name}: Tcpip server read thread unexpectedly died"
            Logger.error e.formatted
          end
          Logger.info "#{@name}: Tcpip server lost read connection to #{interface_info.hostname}(#{interface_info.host_ip}):#{interface_info.port}"
          @read_threads.delete(Thread.current)

          index_to_delete = nil
          @connection_mutex.synchronize do
            index = 0
            @read_interface_infos.each do |read_interface_info|
              if interface_info.interface == read_interface_info.interface
                index_to_delete = index
                read_interface_info.interface.disconnect
                read_interface_info.interface.stream_log_pair.stop if read_interface_info.interface.stream_log_pair
                break
              end
              index += 1
            end
          ensure
            if index_to_delete
              @read_interface_infos.delete_at(index_to_delete)
            end
          end
        rescue Exception => e
          Logger.error "#{@name}: Tcpip server read thread unexpectedly died"
          Logger.error e.formatted
        end
      end
    end

    def write_thread_body
      # Retrieve the next packet to be sent out to clients
      # Handles disconnected clients even when packets aren't flowing
      packet = nil

      loop do
        break if @cancel_threads

        begin
          packet = @write_queue.pop(true) # non_block to raise ThreadError
          break
        rescue ThreadError
          check_for_dead_clients()
        end
      end

      packet = write_thread_hook(packet)
      write_to_clients(:write, packet) if packet
    end

    def write_raw_thread_body
      # Retrieve the next data to be sent out to clients
      data = nil

      loop do
        break if @cancel_threads

        begin
          data = @write_raw_queue.pop(true) # non_block to raise ThreadError
          break
        rescue ThreadError
          # Sleep until we receive data or for 100ms
          @write_raw_mutex.synchronize do
            @write_raw_condition_variable.wait(@write_raw_mutex, 0.1)
          end
        end
      end

      data = write_raw_thread_hook(data)
      write_to_clients(:write_raw, data) if data
    end

    def write_thread_hook(packet)
      packet # By default just return the packet
    end

    def write_raw_thread_hook(data)
      data # By default just return the data
    end

    def read_thread_body(interface)
      thread_bytes_read = 0
      loop do
        packet = interface.read
        interface_bytes_read = interface.bytes_read
        if interface_bytes_read != thread_bytes_read
          diff = interface_bytes_read - thread_bytes_read
          @bytes_read += diff # This would be better if mutex protected, but not that important for telemetry
          thread_bytes_read = interface_bytes_read
        end
        return if !packet || @cancel_threads

        packet = read_thread_hook(packet) # Do work on received packet
        @read_raw_data_time = interface.read_raw_data_time
        @read_raw_data = interface.read_raw_data
        @read_queue << packet.clone
      end
    end

    # @return [Packet] Return the packet
    def read_thread_hook(packet)
      packet
    end

    def check_for_dead_clients
      indexes_to_delete = []
      index = 0

      @connection_mutex.synchronize do
        @write_interface_infos.each do |interface_info|
          if @write_port != @read_port
            # Socket should return EWOULDBLOCK if it is still cleanly connected
            interface_info.interface.stream.write_socket.recvfrom_nonblock(10)
          elsif !interface_info.interface.stream.write_socket.closed?
            # Let read thread detect disconnect
            next
          end
          # Client has disconnected (or is invalidly sending data on the socket)
          Logger.info "#{@name}: Tcpip server lost write connection to #{interface_info.hostname}(#{interface_info.host_ip}):#{interface_info.port}"
          interface_info.interface.disconnect
          interface_info.interface.stream_log_pair.stop if interface_info.interface.stream_log_pair
          indexes_to_delete.unshift(index) # Put later indexes at front of array
        rescue Errno::ECONNRESET, Errno::ECONNABORTED, IOError
          # Client has disconnected
          Logger.info "#{@name}: Tcpip server lost write connection to #{interface_info.hostname}(#{interface_info.host_ip}):#{interface_info.port}"
          interface_info.interface.disconnect
          interface_info.interface.stream_log_pair.stop if interface_info.interface.stream_log_pair
          indexes_to_delete.unshift(index) # Put later indexes at front of array
        rescue Errno::EWOULDBLOCK
          # Client is still cleanly connected as far as we can tell without writing to the socket
        ensure
          index += 1
        end

        # Delete any dead sockets
        indexes_to_delete.each do |index_to_delete|
          @write_interface_infos.delete_at(index_to_delete)
        end
      end # connection_mutex.synchronize

      # Sleep until we receive a packet or for 100ms
      @write_mutex.synchronize do
        @write_condition_variable.wait(@write_mutex, 0.1)
      end
    end

    def write_to_clients(method, packet_or_data)
      @connection_mutex.synchronize do
        # Send data to each client - On error drop the client
        indexes_to_delete = []
        index = 0
        @write_interface_infos.each do |interface_info|
          need_disconnect = false
          begin
            interface_bytes_written = interface_info.interface.bytes_written
            interface_info.interface.public_send(method, packet_or_data)
            diff = interface_info.interface.bytes_written - interface_bytes_written
            @written_raw_data_time = interface_info.interface.written_raw_data_time
            @written_raw_data = interface_info.interface.written_raw_data
            @bytes_written += diff
          rescue Errno::EPIPE, Errno::ECONNABORTED, IOError, Errno::ECONNRESET
            # Client has normally disconnected
            need_disconnect = true
          rescue Exception => e
            if e.message != "Stream not connected for write_raw"
              Logger.error "#{@name}: Error sending to client: #{e.class} #{e.message}"
            end
            need_disconnect = true
          end

          if need_disconnect
            Logger.info "#{@name}: Tcpip server lost write connection to #{interface_info.hostname}(#{interface_info.host_ip}):#{interface_info.port}"
            interface_info.interface.disconnect
            interface_info.interface.stream_log_pair.stop if interface_info.interface.stream_log_pair
            indexes_to_delete.unshift(index) # Put later indexes at front of array
          end
          index += 1
        end

        # Delete any dead sockets
        indexes_to_delete.each do |index_to_delete|
          @write_interface_infos.delete_at(index_to_delete)
        end
      end # connection_mutex.synchronize
    end

    def details
      result = super()
      result['write_port'] = @write_port
      result['read_port'] = @read_port
      result['write_timeout'] = @write_timeout
      result['read_timeout'] = @read_timeout
      result['listen_address'] = @listen_address
      return result
    end
  end
end
