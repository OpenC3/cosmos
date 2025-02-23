# Copyright 2025 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import queue
import select
import socket
import threading
import multiprocessing
from openc3.interfaces.stream_interface import StreamInterface
from openc3.streams.tcpip_socket_stream import TcpipSocketStream
from openc3.config.config_parser import ConfigParser
from openc3.utilities.logger import Logger
from openc3.top_level import kill_thread, close_socket


# Data class which stores the interface and associated information
class InterfaceInfo:
    # attr_reader :interface, :hostname, :host_ip, :port

    def __init__(self, interface, hostname, host_ip, port):
        self.interface = interface
        self.hostname = hostname
        self.host_ip = host_ip
        self.port = port


# TCP/IP Server which can both read and write on a single port or two
# independent ports. A listen thread is setup which waits for client
# connections. For each connection to the read port, a thread is spawned that
# calls the read method from the interface. This data is then
# available by calling the TcpipServer read method. For each connection to the
# write port, a thread is spawned that calls the write method from the
# interface when data is send to the TcpipServer via the write method.
class TcpipServerInterface(StreamInterface):
    # Callback method to call when a new client connects to the write port.
    # This method will be called with the Interface as the only argument.
    # attr_accessor :write_connection_callback
    # Callback method to call when a new client connects to the read port.
    # This method will be called with the Interface as the only argument.
    # attr_accessor :read_connection_callback
    # @return [StreamLogPair] StreamLogPair instance or nil
    # attr_accessor :stream_log_pair
    # @return [String] The ip address to bind to.  Default to ANY (0.0.0.0)
    # attr_accessor :listen_address

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
    def __init__(
        self,
        write_port,
        read_port,
        write_timeout,
        read_timeout,
        protocol_type=None,
        *protocol_args,
    ):
        super().__init__(protocol_type, protocol_args)
        self.write_port = ConfigParser.handle_none(write_port)
        if self.write_port is not None:
            self.write_port = int(self.write_port)
        self.read_port = ConfigParser.handle_none(read_port)
        if self.read_port is not None:
            self.read_port = int(self.read_port)
        self.write_timeout = ConfigParser.handle_none(write_timeout)
        if self.write_timeout is not None:
            self.write_timeout = float(self.write_timeout)
        self.read_timeout = ConfigParser.handle_none(read_timeout)
        if self.read_timeout is not None:
            self.read_timeout = float(self.read_timeout)
        self.listen_sockets = []
        self.listen_pipes = []
        self.listen_threads = []
        self.read_threads = []
        self.write_thread = None
        self.write_raw_thread = None
        self.write_interface_infos = []
        self.read_interface_infos = []
        self.write_queue = None
        if self.write_port:
            self.write_queue = queue.Queue()
        self.write_raw_queue = None
        if self.write_port:
            self.write_raw_queue = queue.Queue()
        self.read_queue = None
        if self.read_port:
            self.read_queue = queue.Queue()
        self.write_condition_variable = None
        if self.write_port:
            self.write_condition_variable = threading.Condition(self.write_mutex)
        self.write_raw_mutex = None
        if self.write_port:
            self.write_raw_mutex = threading.Lock()
        self.write_raw_condition_variable = None
        if self.write_port:
            self.write_raw_condition_variable = threading.Condition(self.write_raw_mutex)
        self.write_connection_callback = None
        self.read_connection_callback = None
        self.stream_log_pair = None
        self.raw_logging_enabled = False
        self.connection_mutex = threading.Lock()
        self.listen_address = "0.0.0.0"

        if not ConfigParser.handle_none(read_port):
            self.read_allowed = False
        if not ConfigParser.handle_none(write_port):
            self.write_allowed = False
        if not ConfigParser.handle_none(write_port):
            self.write_raw_allowed = False

        self._connected = False

    def connected(self):
        return self._connected

    def connection_string(self):
        if self.write_port == self.read_port:
            return f"listening on {self.listen_address}:{self.write_port} (R/W)"
        result = "listening on"
        if self.write_port:
            result += f" {self.listen_address}:{self.write_port} (write)"
        if self.read_port:
            result += f" {self.listen_address}:{self.read_port} (read)"
        return result

    # Create the read and write port listen threads. Incoming connections will
    # spawn separate threads to process the reads and writes.
    def connect(self):
        self.cancel_threads = False
        if self.read_queue:
            while not self.read_queue.empty():
                self.read_queue.get_nowait()
        if self.write_port == self.read_port:  # One socket
            self._start_listen_thread(self.read_port, True, True)
        else:
            if self.write_port:
                self._start_listen_thread(self.write_port, True, False)
            if self.read_port:
                self._start_listen_thread(self.read_port, False, True)

        if self.write_port:
            self.write_thread = threading.Thread(target=self._write_thread_body, daemon=True)
            self.write_thread.start()

            self.write_raw_thread = threading.Thread(target=self._write_raw_thread_body, daemon=True)
            self.write_raw_thread.start()
        else:
            self.write_thread = None
            self.write_raw_thread = None
        super().connect()
        self._connected = True

    # Shutdowns the listener threads for both the read and write ports as well
    # as any client connections.
    def disconnect(self):
        self.cancel_threads = True
        if self.read_queue:
            self.read_queue.put(None)
        for pipe in self.listen_pipes:
            pipe.send(".")
        self.listen_pipes = []

        # Shutdown listen thread(s)
        for listen_thread in self.listen_threads:
            kill_thread(self, listen_thread)
        self.listen_threads = []

        # Shutdown listen socket(s)
        for listen_socket in self.listen_sockets:
            close_socket(listen_socket)
        # Ok may have been closed by the thread
        self.listen_sockets = []

        # This will unblock read threads
        self._shutdown_interfaces(self.read_interface_infos)

        for thread in self.read_threads:
            kill_thread(self, thread)
        self.read_threads = []

        if self.write_thread:
            with self.write_condition_variable:
                self.write_condition_variable.notify_all()
            kill_thread(self, self.write_thread)
            self.write_thread = None
        if self.write_raw_thread:
            with self.write_raw_condition_variable:
                self.write_raw_condition_variable.notify_all()
            kill_thread(self, self.write_raw_thread)
            self.write_raw_thread = None

        self._shutdown_interfaces(self.write_interface_infos)
        self._connected = False
        super().disconnect()

    # Gracefully kill all the threads
    def graceful_kill(self):
        # This method is just here to prevent warnings
        pass

    # @return [Packet] Latest packet read from any of the connected clients.
    #   Note this method blocks until data is available.
    def read(self):
        if not self.connected():
            raise RuntimeError(f"Interface not connected for read: {self.name}")
        if not self.read_allowed:
            raise RuntimeError(f"Interface not readable: {self.name}")

        try:
            packet = self.read_queue.get(block=True)
        except queue.Empty:
            return None

        if packet is not None:
            self.read_count += 1
        return packet

    # @param packet [Packet] Packet to write to all clients connected to the
    #   write port.
    def write(self, packet):
        if not self.connected():
            raise RuntimeError(f"Interface not connected for write: {self.name}")
        if not self.write_allowed:
            raise RuntimeError(f"Interface not writeable: {self.name}")

        self.write_count += 1
        self.write_queue.put(packet.clone())
        try:
            self.write_condition_variable.notify_all()
        except RuntimeError as error:
            if "cannot notify on un-acquired lock" in repr(error):
                pass
            else:
                raise error

    # @param data [String] Data to write to all clients connected to the
    #   write port.
    def write_raw(self, data):
        if not self.connected():
            raise RuntimeError(f"Interface not connected for write_raw: {self.name}")
        if not self.write_raw_allowed:
            raise RuntimeError(f"Interface not write-rawable: {self.name}")

        self.write_raw_queue.put(data)
        try:
            self.write_raw_condition_variable.notify_all()
        except RuntimeError as error:
            if "cannot notify on un-acquired lock" in repr(error):
                return data
            else:
                raise error

    # @return [Integer] The number of packets waiting on the read queue
    def read_queue_size(self):
        if self.read_queue:
            return self.read_queue.qsize()
        else:
            return 0

    # @return [Integer] The number of packets waiting on the write queue
    def write_queue_size(self):
        if self.write_queue:
            return self.write_queue.qsize()
        else:
            return 0

    # @return [Integer] The number of connected clients
    def num_clients(self):
        interfaces = []
        for wii in self.write_interface_infos:
            interfaces.append(wii.interface)
        for rii in self.read_interface_infos:
            interfaces.append(rii.interface)
        return len(list(set(interfaces)))

    # Start raw logging for this interface
    def start_raw_logging(self):
        self.raw_logging_enabled = True
        self._change_raw_logging("start")

    # Stop raw logging for this interface
    def stop_raw_logging(self):
        self.raw_logging_enabled = False
        self._change_raw_logging("stop")

    # Supported Options
    # LISTEN_ADDRESS - Ip address of the interface to accept connections on - Default: 0.0.0.0
    # (see Interface#set_option)
    def set_option(self, option_name, option_values):
        super().set_option(option_name, option_values)
        match option_name.upper():
            case "LISTEN_ADDRESS":
                self.listen_address = option_values[0]

    def _shutdown_interfaces(self, interface_infos):
        with self.connection_mutex:
            for interface_info in interface_infos:
                interface_info.interface.disconnect()
                if interface_info.interface.stream_log_pair:
                    interface_info.interface.stream_log_pair.stop()
            interface_infos = []

    def _change_raw_logging(self, method):
        if self.stream_log_pair:
            for interface_info in self.write_interface_infos:
                if interface_info.interface.stream_log_pair:
                    getattr(interface_info.interface.stream_log_pair, method)
            for interface_info in self.read_interface_infos:
                if interface_info.interface.stream_log_pair:
                    getattr(interface_info.interface.stream_log_pair, method)

    def _start_listen_thread(self, port, listen_write=False, listen_read=False):
        listen_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0)
        listen_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            addr = (self.listen_address, port)
            listen_socket.bind(addr)
        except Exception:
            raise RuntimeError(
                f"Error binding to port {port}.\n"
                + "Either another application is using this port\n"
                + "or the operating system is being slow cleaning up.\n"
                + "Make sure all sockets/streams are closed in all applications,\n"
                + "wait 1 minute and try again."
            )

        listen_socket.setblocking(0)
        listen_socket.listen(5)
        self.listen_sockets.append(listen_socket)

        thread_reader, thread_writer = multiprocessing.Pipe()
        self.listen_pipes.append(thread_writer)
        thread = threading.Thread(
            target=self._listen_thread_body,
            args=[listen_socket, listen_write, listen_read, thread_reader],
            daemon=True,
        )
        thread.start()
        self.listen_threads.append(thread)

    def _listen_thread_body(self, listen_socket, listen_write, listen_read, thread_reader):
        while True:
            while True:
                try:
                    client_socket, address = listen_socket.accept()
                    break
                except (ConnectionAbortedError, BlockingIOError):
                    if self.cancel_threads:
                        break
                    # Wait for something to be readable
                    select.select([listen_socket, thread_reader], [], [])

            if self.cancel_threads:
                break
            host_ip, port = address
            try:
                hostname, _, _ = socket.gethostbyaddr(host_ip)
            except Exception:
                hostname = "UNKNOWN"

            # Configure TCP_NODELAY option
            client_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)

            # Accept Connection
            write_socket = None
            read_socket = None
            if listen_write:
                write_socket = client_socket
            if listen_read:
                read_socket = client_socket
            stream = TcpipSocketStream(write_socket, read_socket, self.write_timeout, self.read_timeout)

            interface = StreamInterface()
            interface.target_names = self.target_names
            interface.cmd_target_names = self.cmd_target_names
            interface.tlm_target_names = self.tlm_target_names
            if self.stream_log_pair:
                interface.stream_log_pair = self.stream_log_pair.clone()
                if self.raw_logging_enabled:
                    interface.stream_log_pair.start()
            for protocol_class, protocol_args, read_write in self.protocol_info:
                interface.add_protocol(protocol_class, protocol_args, read_write)
            interface.stream = stream
            interface.connect()

            if listen_write:
                if self.write_connection_callback:
                    self.write_connection_callback.call(interface)
                with self.connection_mutex:
                    self.write_interface_infos.append(InterfaceInfo(interface, hostname, host_ip, port))
            if listen_read:
                if self.read_connection_callback:
                    self.read_connection_callback.call(interface)
                with self.connection_mutex:
                    self.read_interface_infos.append(InterfaceInfo(interface, hostname, host_ip, port))
                thread = threading.Thread(
                    target=self._start_read_thread,
                    args=[self.read_interface_infos[-1]],
                    daemon=True,
                )
                self.read_threads.append(thread)
                thread.start()
            Logger.info(f"{self.name}: Tcpip server accepted connection from {hostname}({host_ip}):{port}")

    def _start_read_thread(self, interface_info):
        try:
            try:
                self._read_thread_body(interface_info.interface)
            except Exception as error:
                Logger.error(f"{self.name}: Tcpip server read thread unexpectedly died")
                Logger.error(repr(error))
            Logger.info(
                f"{self.name}: Tcpip server lost read connection to {interface_info.hostname}({interface_info.host_ip}):{interface_info.port}"
            )
            self.read_threads.remove(threading.current_thread())

            index_to_delete = None
            with self.connection_mutex:
                index = 0
                for read_interface_info in self.read_interface_infos:
                    if interface_info.interface == read_interface_info.interface:
                        index_to_delete = index
                        read_interface_info.interface.disconnect()
                        if read_interface_info.interface.stream_log_pair:
                            read_interface_info.interface.stream_log_pair.stop()
                        break
                    index += 1
            if index_to_delete:
                del self.read_interface_infos[index_to_delete]
        except Exception as error:
            Logger.error(f"{self.name}: Tcpip server read thread unexpectedly died")
            Logger.error(repr(error))

    def _write_thread_body(self):
        try:
            while True:
                if self.cancel_threads:
                    break

                # Retrieve the next packet to be sent out to clients
                # Handles disconnected clients even when packets aren't flowing
                packet = None

                while True:
                    if self.cancel_threads:
                        break

                    try:
                        packet = self.write_queue.get_nowait()
                        break
                    except queue.Empty:
                        if self.cancel_threads:
                            break
                        self._check_for_dead_clients()

                packet = self._write_thread_hook(packet)
                if packet:
                    self._write_to_clients("write", packet)

        except Exception as error:
            self._shutdown_interfaces(self.write_interface_infos)
            Logger.error(f"{self.name}: Tcpip server write thread unexpectedly died")
            Logger.error(repr(error))

    def _write_raw_thread_body(self):
        try:
            while True:
                if self.cancel_threads:
                    break

                # Retrieve the next data to be sent out to clients
                data = None

                while True:
                    if self.cancel_threads:
                        break

                    try:
                        data = self.write_raw_queue.get_nowait()
                        break
                    except queue.Empty:
                        # Sleep until we receive data or for 100ms
                        with self.write_raw_condition_variable:
                            self.write_raw_condition_variable.wait(0.1)

                data = self._write_raw_thread_hook(data)
                if data:
                    self._write_to_clients("write_raw", data)

        except Exception as error:
            self._shutdown_interfaces(self.write_interface_infos)
            Logger.error(f"{self.name}: Tcpip server write raw thread unexpectedly died")
            Logger.error(repr(error))

    def _write_thread_hook(self, packet):
        return packet  # By default just return the packet

    def _write_raw_thread_hook(self, data):
        return data  # By default just return the data

    def _read_thread_body(self, interface):
        thread_bytes_read = 0
        while True:
            packet = interface.read()
            interface_bytes_read = interface.bytes_read
            if interface_bytes_read != thread_bytes_read:
                diff = interface_bytes_read - thread_bytes_read
                self.bytes_read += diff
                thread_bytes_read = interface_bytes_read
            if not packet or self.cancel_threads:
                return

            packet = self._read_thread_hook(packet)  # Do work on received packet
            self.read_raw_data_time = interface.read_raw_data_time
            self.read_raw_data = interface.read_raw_data
            self.read_queue.put(packet.clone())

    # @return [Packet] Return the packet
    def _read_thread_hook(self, packet):
        return packet

    def _check_for_dead_clients(self):
        indexes_to_delete = []
        index = 0

        with self.connection_mutex:
            try:
                for interface_info in self.write_interface_infos:
                    if self.write_port != self.read_port:
                        # Socket should return EWOULDBLOCK if it is still cleanly connected
                        interface_info.interface.stream.write_socket.recv(10, socket.MSG_DONTWAIT)
                    elif interface_info.interface.stream.write_socket.fileno() != -1:
                        # Let read thread detect disconnect
                        continue
                    # Client has disconnected (or is invalidly sending data on the socket)
                    Logger.info(
                        f"{self.name}: Tcpip server lost write connection to {interface_info.hostname}({interface_info.host_ip}):{interface_info.port}"
                    )
                    interface_info.interface.disconnect()
                    if interface_info.interface.stream_log_pair:
                        interface_info.interface.stream_log_pair.stop()
                    indexes_to_delete.insert(0, index)  # Put later indexes at front of array
            except socket.error as error:
                if error.errno == socket.EAGAIN or error.errno == socket.EWOULDBLOCK:
                    # Client is still cleanly connected as far as we can tell without writing to the socket
                    pass
                else:
                    # Client has disconnected
                    Logger.info(
                        f"{self.name}: Tcpip server lost write connection to {interface_info.hostname}({interface_info.host_ip}):{interface_info.port}"
                    )
                    interface_info.interface.disconnect()
                    if interface_info.interface.stream_log_pair:
                        interface_info.interface.stream_log_pair.stop()
                    indexes_to_delete.insert(0, index)  # Put later indexes at front of array
            finally:
                index += 1

            # Delete any dead sockets
            for index_to_delete in indexes_to_delete:
                del self.write_interface_infos[index_to_delete]

        # Sleep until we receive a packet or for 100ms
        with self.write_condition_variable:
            self.write_condition_variable.wait(0.1)

    def _write_to_clients(self, method, packet_or_data):
        with self.connection_mutex:
            # Send data to each client - On error drop the client
            indexes_to_delete = []
            index = 0
            for interface_info in self.write_interface_infos:
                need_disconnect = False
                try:
                    interface_bytes_written = interface_info.interface.bytes_written
                    getattr(interface_info.interface, method)(packet_or_data)
                    diff = interface_info.interface.bytes_written - interface_bytes_written
                    self.written_raw_data_time = interface_info.interface.written_raw_data_time
                    self.written_raw_data = interface_info.interface.written_raw_data
                    self.bytes_written += diff
                except IOError:
                    # Client has normally disconnected
                    need_disconnect = True
                except Exception as error:
                    Logger.error(f"{self.name}: Error sending to client: {error.__class__.__name__} {repr(error)}")
                    need_disconnect = True

                if need_disconnect:
                    Logger.info(
                        f"{self.name}: Tcpip server lost write connection to {interface_info.hostname}({interface_info.host_ip}):{interface_info.port}"
                    )
                    interface_info.interface.disconnect
                    if interface_info.interface.stream_log_pair:
                        interface_info.interface.stream_log_pair.stop
                    indexes_to_delete.insert(0, index)  # Put later indexes at front of array
                index += 1

            # Delete any dead sockets
            for index_to_delete in indexes_to_delete:
                del self.write_interface_infos[index_to_delete]
