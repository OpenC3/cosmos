# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import contextlib
import errno
import queue
import select
import socket
import threading
import time
import traceback

from openc3.config.config_parser import ConfigParser
from openc3.interfaces.stream_interface import StreamInterface
from openc3.streams.tcpip_socket_stream import TcpipSocketStream
from openc3.top_level import close_socket, kill_thread
from openc3.utilities.logger import Logger


# socket.MSG_DONTWAIT is Unix-only; on Windows we rely on setblocking(False).
_MSG_DONTWAIT = getattr(socket, "MSG_DONTWAIT", 0)


# Write timeout used when none is given, matching TcpipSocketStream
DEFAULT_WRITE_TIMEOUT = 10.0


# Interface for each client connection. Tracks the time spent writing to
# the socket so a client which can't keep up can be told apart from one
# whose protocols take a while (e.g. waiting for a command response).
class ClientInterface(StreamInterface):
    def __init__(self):
        super().__init__()
        # Total seconds spent in stream writes
        self.socket_write_time = 0.0

    def write_interface(self, data, extra=None):
        self.write_interface_base(data, extra)
        start = time.monotonic()
        try:
            self.stream.write(data)
        finally:
            self.socket_write_time += time.monotonic() - start
        return data, extra


# Data class which stores the interface and associated information
class InterfaceInfo:
    def __init__(self, interface, host_ip, port):
        self.interface = interface
        self.host_ip = host_ip
        self.port = port
        # Queue of (method, packet_or_data, socket_write_time) waiting to be written to the client
        self.write_queue = None
        # Thread which services the write_queue
        self.write_thread = None
        # Set once the client is being removed so nothing more is queued
        self.write_stopped = False

    def __str__(self):
        return f"{self.host_ip}:{self.port}"


# TCP/IP Server which can both read and write on a single port or two
# independent ports. A listen thread is setup which waits for client
# connections. For each connection to the read port, a thread is spawned that
# calls the read method from the interface. This data is then
# available by calling the TcpipServer read method. For each connection to the
# write port, a thread is spawned with its own queue which calls the write
# method from the interface when data is sent to the TcpipServer via the
# write method. Each client is written independently so a client which stops
# reading can't delay the other clients or accepting new connections.
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
        # Client write threads update the write statistics concurrently
        self.write_stats_mutex = threading.Lock()
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
            with contextlib.suppress(OSError):
                pipe.send(b".")
            close_socket(pipe)
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

        if self.write_thread and self.write_condition_variable:
            with self.write_condition_variable:
                self.write_condition_variable.notify_all()
            kill_thread(self, self.write_thread)
            self.write_thread = None
        if self.write_raw_thread and self.write_raw_condition_variable:
            with self.write_raw_condition_variable:
                self.write_raw_condition_variable.notify_all()
            kill_thread(self, self.write_raw_thread)
            self.write_raw_thread = None

        self._shutdown_write_clients()
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
        if not self.read_allowed or self.read_queue is None:
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
        if not self.write_allowed or self.write_queue is None or self.write_condition_variable is None:
            raise RuntimeError(f"Interface not writeable: {self.name}")

        self.write_count += 1
        self.write_queue.put(packet.clone())
        # The lock must be held to notify, otherwise notify_all raises and the
        # write thread only wakes up when its wait times out
        with self.write_condition_variable:
            self.write_condition_variable.notify_all()

    # @param data [String] Data to write to all clients connected to the
    #   write port.
    def write_raw(self, data, extra=None):
        if not self.connected():
            raise RuntimeError(f"Interface not connected for write_raw: {self.name}")
        if not self.write_raw_allowed or self.write_raw_queue is None or self.write_raw_condition_variable is None:
            raise RuntimeError(f"Interface not write-rawable: {self.name}")

        self.write_raw_queue.put(data)
        # The lock must be held to notify, otherwise notify_all raises and the
        # write raw thread only wakes up when its wait times out
        with self.write_raw_condition_variable:
            self.write_raw_condition_variable.notify_all()
        return data

    # @return [Integer] The number of packets waiting on the read queue
    def read_queue_size(self):
        if self.read_queue:
            return self.read_queue.qsize()
        else:
            return 0

    # @return [Integer] The number of bytes waiting on the read queues of the
    #   connected clients. The server itself has no stream so the raw reads are
    #   buffered by each client connection.
    def read_queue_bytes(self):
        with self.connection_mutex:
            return sum(rii.interface.read_queue_bytes() for rii in self.read_interface_infos)

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
                self._disconnect_client(interface_info)
            interface_infos.clear()

    # Stop every client write thread and disconnect the clients
    def _shutdown_write_clients(self):
        with self.connection_mutex:
            interface_infos = list(self.write_interface_infos)
            self.write_interface_infos.clear()
        # Stop and join outside the mutex because the client write threads
        # take it to remove themselves as they exit
        for interface_info in interface_infos:
            self._stop_client_write_queue(interface_info)
            self._disconnect_client(interface_info)
        for interface_info in interface_infos:
            thread = interface_info.write_thread
            if thread and thread != threading.current_thread():
                kill_thread(self, thread)

    def _disconnect_client(self, interface_info):
        interface_info.interface.disconnect()
        if interface_info.interface.stream_log_pair:
            interface_info.interface.stream_log_pair.stop()

    def _change_raw_logging(self, method):
        if self.stream_log_pair:
            for interface_info in self.write_interface_infos:
                if interface_info.interface.stream_log_pair:
                    getattr(interface_info.interface.stream_log_pair, method)()
            for interface_info in self.read_interface_infos:
                if interface_info.interface.stream_log_pair:
                    getattr(interface_info.interface.stream_log_pair, method)()

    def _start_listen_thread(self, port, listen_write=False, listen_read=False):
        listen_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0)
        listen_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            addr = (self.listen_address, port)
            listen_socket.bind(addr)
        except Exception as e:
            raise RuntimeError(
                f"Error binding to port {port}.\n"
                + "Either another application is using this port\n"
                + "or the operating system is being slow cleaning up.\n"
                + "Make sure all sockets/streams are closed in all applications,\n"
                + "wait 1 minute and try again."
            ) from e

        listen_socket.setblocking(False)
        listen_socket.listen(5)
        self.listen_sockets.append(listen_socket)

        # socket.socketpair (rather than multiprocessing.Pipe) so the
        # readable end can be passed to select.select on Windows, where
        # select only accepts sockets.
        thread_reader, thread_writer = socket.socketpair()
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
            # No reverse DNS lookup because it blocks accepting further connections
            host_ip, port = address

            # Configure TCP_NODELAY option
            client_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            client_socket.setblocking(False)

            # Accept Connection
            write_socket = None
            read_socket = None
            if listen_write:
                write_socket = client_socket
            if listen_read:
                read_socket = client_socket
            stream = TcpipSocketStream(write_socket, read_socket, self.write_timeout, self.read_timeout)

            interface = ClientInterface()
            # Only the read side of the connection needs a read thread
            interface.read_allowed = listen_read
            # Each connection buffers its own reads so give it the configured limit
            interface.read_queue_max_size = self.read_queue_max_size
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

            interface_info = InterfaceInfo(interface, host_ip, port)
            if listen_write:
                if self.write_connection_callback:
                    self.write_connection_callback.call(interface)
                self.add_write_client(interface_info)
            if listen_read:
                if self.read_connection_callback:
                    self.read_connection_callback.call(interface)
                with self.connection_mutex:
                    self.read_interface_infos.append(interface_info)
                thread = threading.Thread(
                    target=self._start_read_thread,
                    args=[interface_info],
                    daemon=True,
                )
                self.read_threads.append(thread)
                thread.start()
            Logger.info(f"{self.name}: Tcpip server accepted connection from {interface_info}")

    # Register a client connected to the write port and start the thread
    # which writes its queued packets
    def add_write_client(self, interface_info):
        interface_info.write_queue = queue.Queue()
        # Register before starting the thread so the thread can always remove it
        with self.connection_mutex:
            self.write_interface_infos.append(interface_info)
        interface_info.write_thread = threading.Thread(
            target=self._client_write_thread, args=[interface_info], daemon=True
        )
        interface_info.write_thread.start()

    def _client_write_thread(self, interface_info):
        try:
            self._client_write_thread_body(interface_info)
        except Exception:
            Logger.error(f"{self.name}: Tcpip server client write thread unexpectedly died")
            Logger.error(traceback.format_exc())
        finally:
            self._remove_write_client(interface_info)

    # Writes everything queued for one client until the client disconnects,
    # stops keeping up, or the queue is stopped
    def _client_write_thread_body(self, interface_info):
        interface = interface_info.interface
        write_queue = interface_info.write_queue
        max_lag = self.write_timeout if self.write_timeout is not None else DEFAULT_WRITE_TIMEOUT
        try:
            while True:
                try:
                    item = write_queue.get(timeout=0.1)
                except queue.Empty:
                    # Detect disconnected clients even when packets aren't flowing
                    if interface_info.write_stopped or not self._client_write_connected(interface_info):
                        return
                    continue
                # None is queued to stop the thread
                if item is None:
                    return

                method, packet_or_data, socket_write_time = item
                # A client which is reading too slowly to keep up would otherwise
                # queue data forever so drop it once it has spent more than
                # write_timeout blocked on the socket since this item was queued.
                # Only socket time counts, not time spent in protocols, so a
                # protocol waiting for a response doesn't get the client dropped.
                lag = interface.socket_write_time - socket_write_time
                if lag > max_lag:
                    Logger.error(
                        f"{self.name}: Tcpip server dropping client {interface_info} which spent {lag:.1f}s blocked writing since this data was queued (write timeout {max_lag}s)"
                    )
                    return

                interface_bytes_written = interface.bytes_written
                getattr(interface, method)(packet_or_data)
                diff = interface.bytes_written - interface_bytes_written
                with self.write_stats_mutex:
                    self.written_raw_data_time = interface.written_raw_data_time
                    self.written_raw_data = interface.written_raw_data
                    self.bytes_written += diff
        # TimeoutError is an OSError so it must come first
        except TimeoutError:
            Logger.error(
                f"{self.name}: Tcpip server dropping client {interface_info} which did not accept data within the write timeout"
            )
        except OSError:
            # Client has normally disconnected
            pass
        except Exception as error:
            Logger.error(
                f"{self.name}: Error sending to client {interface_info}: {error.__class__.__name__} {traceback.format_exc()}"
            )

    # @return [Boolean] Whether the client on the write port still appears connected
    def _client_write_connected(self, interface_info):
        write_socket = interface_info.interface.stream.write_socket
        if self.write_port == self.read_port:
            # The read thread detects the disconnect and closes the socket
            return write_socket.fileno() != -1
        try:
            # Socket should raise EWOULDBLOCK if it is still cleanly connected
            write_socket.recv(10, _MSG_DONTWAIT)
        except OSError as error:
            # Client is still cleanly connected as far as we can tell without writing to the socket
            return error.errno in (errno.EAGAIN, errno.EWOULDBLOCK)
        # Client has disconnected (or is invalidly sending data on the socket)
        return False

    # Called by the client write thread as it exits
    def _remove_write_client(self, interface_info):
        self._stop_client_write_queue(interface_info)
        with self.connection_mutex:
            try:
                self.write_interface_infos.remove(interface_info)
            except ValueError:
                # _shutdown_write_clients already removed it
                return
        Logger.info(f"{self.name}: Tcpip server lost write connection to {interface_info}")
        self._disconnect_client(interface_info)

    def _stop_client_write_queue(self, interface_info):
        interface_info.write_stopped = True
        write_queue = interface_info.write_queue
        if write_queue is None:
            return
        # Discard anything not yet written and wake the thread
        with contextlib.suppress(queue.Empty):
            while True:
                write_queue.get_nowait()
        write_queue.put(None)

    def _start_read_thread(self, interface_info):
        try:
            try:
                self._read_thread_body(interface_info.interface)
            except Exception:
                Logger.error(f"{self.name}: Tcpip server read thread unexpectedly died")
                Logger.error(traceback.format_exc())
            Logger.info(f"{self.name}: Tcpip server lost read connection to {interface_info}")
            self.read_threads.remove(threading.current_thread())

            with self.connection_mutex:
                if interface_info in self.read_interface_infos:
                    self.read_interface_infos.remove(interface_info)
                    self._disconnect_client(interface_info)
        except Exception:
            Logger.error(f"{self.name}: Tcpip server read thread unexpectedly died")
            Logger.error(traceback.format_exc())

    def _write_thread_body(self):
        write_queue = self.write_queue
        write_condition_variable = self.write_condition_variable
        if write_queue is None or write_condition_variable is None:  # No write port
            return
        try:
            while True:
                if self.cancel_threads:
                    break

                # Retrieve the next packet to be sent out to clients
                packet = None

                while True:
                    if self.cancel_threads:
                        break

                    try:
                        packet = write_queue.get_nowait()
                        break
                    except queue.Empty:
                        if self.cancel_threads:
                            break
                        # Sleep until we receive a packet or for 100ms
                        with write_condition_variable:
                            write_condition_variable.wait(0.1)

                packet = self._write_thread_hook(packet)
                if packet:
                    self._write_to_clients("write", packet)

        except Exception:
            self._shutdown_write_clients()
            Logger.error(f"{self.name}: Tcpip server write thread unexpectedly died")
            Logger.error(traceback.format_exc())

    def _write_raw_thread_body(self):
        write_raw_queue = self.write_raw_queue
        write_raw_condition_variable = self.write_raw_condition_variable
        if write_raw_queue is None or write_raw_condition_variable is None:  # No write port
            return
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
                        data = write_raw_queue.get_nowait()
                        break
                    except queue.Empty:
                        # Sleep until we receive data or for 100ms
                        with write_raw_condition_variable:
                            write_raw_condition_variable.wait(0.1)

                data = self._write_raw_thread_hook(data)
                if data:
                    self._write_to_clients("write_raw", data)

        except Exception:
            self._shutdown_write_clients()
            Logger.error(f"{self.name}: Tcpip server write raw thread unexpectedly died")
            Logger.error(traceback.format_exc())

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
            if not packet or self.cancel_threads or self.read_queue is None:
                return

            packet = self._read_thread_hook(packet)  # Do work on received packet
            self.read_raw_data_time = interface.read_raw_data_time
            self.read_raw_data = interface.read_raw_data
            self.read_queue.put(packet.clone())

    # @return [Packet] Return the packet
    def _read_thread_hook(self, packet):
        return packet

    # Queue the packet or data for every connected client. Never blocks on a
    # socket. The mutex is only held to copy the client list so a client which
    # stops reading can't delay the other clients or accepting new connections.
    def _write_to_clients(self, method, packet_or_data):
        with self.connection_mutex:
            interface_infos = list(self.write_interface_infos)
        last_index = len(interface_infos) - 1
        for index, interface_info in enumerate(interface_infos):
            if interface_info.write_stopped:
                continue
            item = packet_or_data
            # Each client's protocols run concurrently and may modify the packet
            # so every client but the last gets its own copy
            if method == "write" and index != last_index:
                item = packet_or_data.clone()
            interface_info.write_queue.put((method, item, interface_info.interface.socket_write_time))

    def details(self):
        result = super().details()
        result["write_port"] = self.write_port
        result["read_port"] = self.read_port
        result["write_timeout"] = self.write_timeout
        result["read_timeout"] = self.read_timeout
        result["listen_address"] = self.listen_address
        return result
