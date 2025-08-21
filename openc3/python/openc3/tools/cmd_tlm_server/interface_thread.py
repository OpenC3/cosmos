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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import threading
import socket
from datetime import datetime, timezone
from openc3.utilities.logger import Logger
from openc3.utilities.sleeper import Sleeper
from openc3.utilities.thread_manager import ThreadManager
from openc3.top_level import kill_thread
from openc3.system.system import System


class InterfaceThread:
    """Encapsulates an {Interface} in a Python thread. When the thread is started by
    the start() method, it loops trying to connect. It then continuously reads
    from the interface while handling the packets it receives.
    """
    
    # The number of bytes to print when an UNKNOWN packet is received
    UNKNOWN_BYTES_TO_PRINT = 36

    def __init__(self, interface):
        """Initialize the interface thread
        
        Args:
            interface: The interface to create a thread for
        """
        self.interface = interface
        self.connection_success_callback = None
        self.connection_failed_callback = None
        self.connection_lost_callback = None
        self.identified_packet_callback = None
        self.fatal_exception_callback = None
        self.thread = None
        self.thread_sleeper = Sleeper()
        self.connection_failed_messages = []
        self.connection_lost_messages = []
        self.mutex = threading.RLock()
        self.cancel_thread = False

    def start(self):
        """Create and start the Python thread that will encapsulate the interface.
        Creates a while loop that waits for Interface.connect() to succeed. Then
        calls Interface.read() and handles all the incoming packets.
        """
        self.thread_sleeper = Sleeper()
        self.cancel_thread = False
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()
        ThreadManager.instance().register(self.thread, stop_object=self)
        return self.thread

    def stop(self):
        """Disconnect from the interface and stop the thread"""
        with self.mutex:
            # Need to make sure that cancel_thread is set and the interface disconnected within
            # mutex to ensure that connect() is not called when we want to stop()
            self.cancel_thread = True
            self.thread_sleeper.cancel()
            self.interface.disconnect()
        
        if self.thread and self.thread != threading.current_thread():
            kill_thread(self, self.thread)

    def graceful_kill(self):
        """Just to avoid warning"""
        pass

    def _run(self):
        """Main thread loop that handles interface connection and packet processing"""
        try:
            if self.interface.read_allowed:
                Logger.info(f"Starting packet reading for {self.interface.name}")
            else:
                Logger.info(f"Starting connection maintenance for {self.interface.name}")
                
            while True:
                if self.cancel_thread:
                    break

                # Handle connection
                if not self.interface.connected():
                    try:
                        with self.mutex:
                            # Make sure connect is not called after stop() has been called
                            if not self.cancel_thread:
                                self._connect()
                        if self.cancel_thread:
                            break
                    except Exception as e:
                        self._handle_connection_failed(e)
                        if self.cancel_thread:
                            break
                        else:
                            continue

                # Read and process packets
                if self.interface.read_allowed:
                    try:
                        packet = self.interface.read()
                        if packet is None:
                            Logger.info(f"Clean disconnect from {self.interface.name} (returned None)")
                            self._handle_connection_lost(None)
                            if self.cancel_thread:
                                break
                            else:
                                continue
                        
                        # Set received time if not already set
                        if not packet.received_time:
                            packet.received_time = datetime.now(timezone.utc)
                            
                    except Exception as e:
                        self._handle_connection_lost(e)
                        if self.cancel_thread:
                            break
                        else:
                            continue
                    
                    self._handle_packet(packet)
                else:
                    # Just sleep if we're not reading
                    self.thread_sleeper.sleep(1)
                    if not self.interface.connected:
                        self._handle_connection_lost(None)
                        
        except Exception as e:
            if self.fatal_exception_callback:
                self.fatal_exception_callback(e)
            else:
                Logger.error(f"Packet reading thread unexpectedly died for {self.interface.name}")
                # In Python we'll just log the exception rather than handle_fatal_exception
                Logger.error(f"Fatal exception: {e}")
        finally:
            Logger.info(f"Stopped packet reading for {self.interface.name}")

    def _handle_packet(self, packet):
        try:
            if packet.stored:
                # Stored telemetry does not update the current value table
                identified_packet = System.telemetry.identify_and_define_packet(
                    packet, self.interface.tlm_target_names)
            else:
                # Identify and update packet
                if packet.identified:
                    try:
                        # Preidentified packet - place it into the current value table
                        identified_packet = System.telemetry.update(
                            packet.target_name, packet.packet_name, packet.buffer)
                    except RuntimeError:
                        # Packet identified but we don't know about it
                        # Clear packet_name and target_name and try to identify
                        Logger.warn(f"Received unknown identified telemetry: {packet.target_name} {packet.packet_name}")
                        packet.target_name = None
                        packet.packet_name = None
                        identified_packet = System.telemetry.identify(
                            packet.buffer, self.interface.tlm_target_names)
                else:
                    # Packet needs to be identified
                    identified_packet = System.telemetry.identify(
                        packet.buffer, self.interface.tlm_target_names)

            if identified_packet:
                identified_packet.received_time = packet.received_time
                identified_packet.stored = packet.stored
                identified_packet.extra = packet.extra
                packet = identified_packet
            else:
                # Create unknown packet
                unknown_packet = System.telemetry.update('UNKNOWN', 'UNKNOWN', packet.buffer)
                unknown_packet.received_time = packet.received_time
                unknown_packet.stored = packet.stored
                unknown_packet.extra = packet.extra
                packet = unknown_packet
                
                # Log unknown packet
                data_length = packet.length
                string = f"{self.interface.name} - Unknown {data_length} byte packet starting: "
                num_bytes_to_print = min(self.UNKNOWN_BYTES_TO_PRINT, data_length)
                data_to_print = packet.buffer[:num_bytes_to_print]
                for byte in data_to_print:
                    string += f"{byte:02X}"
                Logger.error(string)

            # Update target telemetry count
            target = System.targets.get(packet.target_name)
            if target:
                target.tlm_cnt += 1
            packet.received_count += 1
            
            # Call identified packet callback
            if self.identified_packet_callback:
                self.identified_packet_callback(packet)

            # Write to routers
            for router in self.interface.routers:
                try:
                    if router.write_allowed and router.connected:
                        router.write(packet)
                except Exception as e:
                    Logger.error(f"Problem writing to router {router.name} - {type(e).__name__}:{e}")

            # Write to packet log writers
            if packet.stored and self.interface.stored_packet_log_writer_pairs:
                for packet_log_writer_pair in self.interface.stored_packet_log_writer_pairs:
                    packet_log_writer_pair.tlm_log_writer.write(packet)
            else:
                for packet_log_writer_pair in self.interface.packet_log_writer_pairs:
                    # Write errors are handled by the log writer
                    packet_log_writer_pair.tlm_log_writer.write(packet)
                    
        except Exception as e:
            Logger.error(f"Error handling packet in {self.interface.name}: {e}")

    def _handle_connection_failed(self, connect_error):
        if self.connection_failed_callback:
            self.connection_failed_callback(connect_error)
        else:
            Logger.error(f"{self.interface.name} Connection Failed: {connect_error}")
            
            # Check for common connection errors that don't need exception files
            common_errors = (
                ConnectionRefusedError, ConnectionResetError, TimeoutError,
                socket.error, OSError, IOError
            )
            
            if isinstance(connect_error, common_errors):
                # Do not write an exception file for these extremely common cases
                pass
            elif isinstance(connect_error, RuntimeError) and (
                'canceled' in str(connect_error) or 'timeout' in str(connect_error)
            ):
                # Do not write an exception file for these extremely common cases
                pass
            else:
                Logger.error(f"Connection error details: {connect_error}")
                if str(connect_error) not in self.connection_failed_messages:
                    # In Python we'll just log rather than write exception file
                    self.connection_failed_messages.append(str(connect_error))

        self._disconnect()

    def _handle_connection_lost(self, err):
        if self.connection_lost_callback:
            self.connection_lost_callback(err)
        else:
            if err:
                Logger.info(f"Connection Lost for {self.interface.name}: {err}")
                
                # Check for common connection errors
                common_errors = (
                    ConnectionAbortedError, ConnectionResetError, TimeoutError,
                    BrokenPipeError, socket.error, OSError, IOError
                )
                
                if not isinstance(err, common_errors):
                    Logger.error(f"Connection lost details: {err}")
                    if str(err) not in self.connection_lost_messages:
                        # In Python we'll just log rather than write exception file
                        self.connection_lost_messages.append(str(err))
            else:
                Logger.info(f"Connection Lost for {self.interface.name}")
                
        self._disconnect()

    def _connect(self):
        """Connect to the interface"""
        Logger.info(f"Connecting to {self.interface.name}...")
        self.interface.connect()
        
        if self.connection_success_callback:
            self.connection_success_callback()
        else:
            Logger.info(f"{self.interface.name} Connection Success")

    def _disconnect(self):
        """Disconnect from the interface and handle reconnection logic"""
        self.interface.disconnect()

        # If the interface is set to auto_reconnect then delay so the thread
        # can come back around and allow the interface a chance to reconnect.
        if self.interface.auto_reconnect:
            if not self.cancel_thread:
                self.thread_sleeper.sleep(self.interface.reconnect_delay)
        else:
            self.stop()

    @property
    def alive(self):
        """Check if the thread is alive"""
        return self.thread and self.thread.is_alive()

    def join(self, timeout=None):
        """Wait for the thread to finish"""
        if self.thread:
            self.thread.join(timeout)
