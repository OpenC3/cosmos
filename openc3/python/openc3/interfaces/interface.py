# Copyright 2023 OpenC3, Inc.
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


import threading
from contextlib import contextmanager
from datetime import datetime, timezone
from openc3.api import *
from openc3.utilities.logger import Logger
from openc3.logs.stream_log_pair import StreamLogPair

# require 'openc3/api/api'
# require 'openc3/utilities/secrets'


class WriteRejectError(RuntimeError):
    """Define a class to allow interfaces and protocols to reject commands without disconnecting the interface"""

    pass


class Interface:
    """Defines all the attributes and methods common to all interface classes used by OpenC3."""

    # Initialize default attribute values
    def __init__(self):
        self.state = "DISCONNECTED"
        self.target_names = []
        self.cmd_target_names = []
        self.tlm_target_names = []
        self.connect_on_startup = True
        self.auto_reconnect = True
        self.reconnect_delay = 5.0
        self.disable_disconnect = False
        self.packet_log_writer_pairs = []
        self.stored_packet_log_writer_pairs = []
        self.routers = []
        self.cmd_routers = []
        self.read_count = 0
        self.write_count = 0
        self.bytes_read = 0
        self.bytes_written = 0
        self.num_clients = 0
        self.read_queue_size = 0
        self.write_queue_size = 0
        self.write_mutex = threading.RLock()
        self.read_allowed = True
        self.write_allowed = True
        self.write_raw_allowed = True
        self.options = {}
        self.read_protocols = []
        self.write_protocols = []
        self.protocol_info = []
        self.read_raw_data = ""
        self.written_raw_data = ""
        self.read_raw_data_time = None
        self.written_raw_data_time = None
        self.config_params = []
        self.interfaces = []
        self.stream_log_pair = None
        # self.secrets = Secrets.getClient
        self.name = self.__class__.__name__

    # Connects the interface to its target(s). Must be implemented by a
    # subclass.
    def connect(self):
        for protocol in self.read_protocols + self.write_protocols:
            protocol.connect_reset()

    # Indicates if the interface is connected to its target(s) or not. Must be:
    # implemented by a subclass.
    def connected(self):
        raise RuntimeError("connected not defined by Interface")

    # Disconnects the interface from its target(s). Must be implemented by a
    # subclass.
    def disconnect(self):
        for protocol in self.read_protocols + self.write_protocols:
            protocol.disconnect_reset()

    def read_interface(self):
        raise RuntimeError("read_interface not defined by Interface")

    def write_interface(self, data):
        raise RuntimeError("write_interface not defined by Interface")

    # Retrieves the next packet from the interface.
    # self.return [Packet] Packet constructed from the data. Packet will be
    #   unidentified (None target and packet names)
    def read(self):
        if not self.connected():
            raise RuntimeError(f"Interface not connected for read {self.name}")
        if not self.read_allowed:
            raise RuntimeError(f"Interface not readable {self.name}")

        try:
            first = True
            while True:
                # Protocols may have cached data for a packet, so initially just inject a blank string
                # Otherwise we can hold off outputing other packets where all the data has already
                # been received
                if not first or len(self.read_protocols) <= 0:
                    # Read data for a packet
                    data = self.read_interface()
                    if not data:
                        Logger.info(f"{self.name}: read_interface requested disconnect")
                        return None
                else:
                    data = ""
                    first = False

                for protocol in self.read_protocols:
                    data = protocol.read_data(data)
                    if data == "DISCONNECT":
                        Logger.info(
                            f"{self.name}: Protocol {protocol.__class__.__name__} read_data requested disconnect"
                        )
                        return None
                    if data == "STOP":
                        break
                if data == "STOP":
                    continue

                packet = self.convert_data_to_packet(data)

                # Potentially modify packet
                for protocol in self.read_protocols:
                    packet = protocol.read_packet(packet)
                    if packet == "DISCONNECT":
                        Logger.info(
                            f"{self.name}: Protocol {protocol.__class__.__name__} read_packet requested disconnect"
                        )
                        return None
                    if packet == "STOP":
                        break
                if packet == "STOP":
                    continue

                # Return packet
                self.read_count += 1
                if not packet:
                    Logger.warn(
                        f"{self.name}: Interface unexpectedly requested disconnect"
                    )
                return packet
        except RuntimeError as error:
            Logger.error(f"{self.name}: Error reading from interface")
            self.disconnect()
            raise error

    # Method to send a packet on the interface.
    # self.param packet [Packet] The Packet to send out the interface
    def write(self, packet):
        if not self.connected():
            raise RuntimeError(f"Interface not connected for write {self.name}")
        if not self.write_allowed:
            raise RuntimeError(f"Interface not writable {self.name}")

        with self._write():
            self.write_count += 1

            # Potentially modify packet
            for protocol in self.write_protocols:
                packet = protocol.write_packet(packet)
                if packet == "DISCONNECT":
                    Logger.info(
                        f"{self.name}: Protocol {protocol.__class__.__name__} write_packet requested disconnect"
                    )
                    self.disconnect()
                    return
                if packet == "STOP":
                    return

            data = self.convert_packet_to_data(packet)

            # Potentially modify packet data
            for protocol in self.write_protocols:
                data = protocol.write_data(data)
                if data == "DISCONNECT":
                    Logger.info(
                        f"{self.name}: Protocol {protocol.__class__.__name__} write_data requested disconnect"
                    )
                    self.disconnect()
                    return
                if data == "STOP":
                    return

            # Actually write out data if not handled by protocol:
            self.write_interface(data)

            # Potentially block and wait for response
            for protocol in self.write_protocols:
                packet, data = protocol.post_write_interface(packet, data)
                if packet == "DISCONNECT":
                    Logger.info(
                        f"{self.name}: Protocol {protocol.__class__.__name__} post_write_packet requested disconnect"
                    )
                    self.disconnect()
                    return
                if packet == "STOP":
                    return
        return None

    # Writes preformatted data onto the interface. Malformed data may cause
    # problems.
    # self.param data [String] The raw data to send out the interface
    def write_raw(self, data):
        if not self.connected():
            raise RuntimeError(f"Interface not connected for write_raw {self.name}")
        if not self.write_raw_allowed:
            raise RuntimeError(f"Interface not raw writable {self.name}")

        with self._write():
            self.write_interface(data)

    # Wrap all writes in a mutex and handle errors
    @contextmanager
    def _write(self):
        self.write_mutex.acquire()
        try:
            yield
        except WriteRejectError as error:
            Logger.error(f"{self.name}: Write rejected by interface {error.message}")
            raise error
        except RuntimeError as error:
            Logger.error(f"{self.name}: Error writing to interface")
            self.disconnect()
            raise error
        finally:
            self.write_mutex.release()

    def as_json(self):
        config = {}
        config["name"] = self.name
        config["state"] = self.state
        config["clients"] = self.num_clients
        config["txsize"] = self.write_queue_size
        config["rxsize"] = self.read_queue_size
        config["txbytes"] = self.bytes_written
        config["rxbytes"] = self.bytes_read
        config["txcnt"] = self.write_count
        config["rxcnt"] = self.read_count
        return config

    # Start raw logging for this interface
    def start_raw_logging(self):
        if not self.stream_log_pair:
            self.stream_log_pair = StreamLogPair(self.name)
        self.stream_log_pair.start()

    # Stop raw logging for this interface
    def stop_raw_logging(self):
        if self.stream_log_pair:
            self.stream_log_pair.stop()

    @property
    def name(self):
        return self.__name

    @name.setter
    def name(self, name):
        self.__name = name
        if self.stream_log_pair:
            self.stream_log_pair.name = name

    # Copy settings from this interface to another interface. All instance
    # variables are copied except for num_clients, read_queue_size,
    # and write_queue_size since these are all specific to the operation of the
    # interface rather than its instantiation.
    #
    # self.param other_interface [Interface] The other interface to copy to
    def copy_to(self, other_interface):
        other_interface.name = self.name
        other_interface.target_names = self.target_names[:]
        other_interface.cmd_target_names = self.cmd_target_names[:]
        other_interface.tlm_target_names = self.tlm_target_names[:]
        other_interface.connect_on_startup = self.connect_on_startup
        other_interface.auto_reconnect = self.auto_reconnect
        other_interface.reconnect_delay = self.reconnect_delay
        other_interface.disable_disconnect = self.disable_disconnect
        other_interface.packet_log_writer_pairs = self.packet_log_writer_pairs[:]
        other_interface.routers = self.routers[:]
        other_interface.cmd_routers = self.cmd_routers[:]
        other_interface.read_count = self.read_count
        other_interface.write_count = self.write_count
        other_interface.bytes_read = self.bytes_read
        other_interface.bytes_written = self.bytes_written
        if self.stream_log_pair:
            other_interface.stream_log_pair = self.stream_log_pair[:]
        # num_clients is per interface so don't copy
        # read_queue_size is the number of packets in the queue so don't copy
        # write_queue_size is the number of packets in the queue so don't copy
        for option_name, option_values in self.options.items():
            other_interface.set_option(option_name, option_values)
        other_interface.protocol_info = []
        for protocol_class, protocol_args, read_write in self.protocol_info:
            if not read_write == "PARAMS":
                other_interface.add_protocol(protocol_class, protocol_args, read_write)

    # Set an interface or router specific option
    # self.param option_name name of the option
    # self.param option_values array of option values
    def set_option(self, option_name, option_values):
        self.options[option_name.upper()] = option_values[:]

    # Called to convert the read data into a OpenC3 Packet object
    #
    # self.param data [String] Raw packet data
    # self.return [Packet] OpenC3 Packet with buffer filled with data
    def convert_data_to_packet(self, data):
        return Packet(None, None, "BIG_ENDIAN", None, data)

    # Called to convert a packet into the data to send
    #
    # self.param packet [Packet] Packet to extract data from
    # self.return data
    def convert_packet_to_data(self, packet):
        return packet.buffer  # Copy buffer so logged command isn't modified

    # Called to read data and manipulate it until enough data is
    # returned. The definition of 'enough data' changes depending on the
    # protocol used which is why this method exists. This method is also used
    # to perform operations on the data before it can be interpreted as packet
    # data such as decryption. After this method is called the post_read_data
    # method is called. Subclasses must implement this method.
    #
    # self.return [String] Raw packet data
    def read_interface_base(self, data):
        self.read_raw_data_time = datetime.now(timezone.utc)
        self.read_raw_data = data
        self.bytes_read += len(data)
        if self.stream_log_pair:
            self.stream_log_pair.read_log.write(data)

    # Called to write data to the underlying interface. Subclasses must
    # implement this method and call super to count the raw bytes and allow raw
    # logging.
    #
    # self.param data [String] Raw packet data
    # self.return [String] The exact data written
    def write_interface_base(self, data):
        self.written_raw_data_time = datetime.now(timezone.utc)
        self.written_raw_data = data
        self.bytes_written += len(data)
        if self.stream_log_pair:
            self.stream_log_pair.write_log.write(data)

    def add_protocol(self, protocol_class, protocol_args, read_write):
        protocol_args = protocol_args[:]
        protocol = protocol_class(*protocol_args)
        match read_write:
            case "READ":
                self.read_protocols.append(protocol)
            case "WRITE":
                self.write_protocols.insert(0, protocol)
            case "READ_WRITE" | "PARAMS":
                self.read_protocols.append(protocol)
                self.write_protocols.insert(0, protocol)
            case _:
                raise RuntimeError(
                    f"Unknown protocol descriptor {read_write}. Must be 'READ', 'WRITE', or 'READ_WRITE'."
                )
        self.protocol_info.append([protocol_class, protocol_args, read_write])
        protocol.interface = self
        return protocol

    def interface_cmd(self, cmd_name, *cmd_args):
        # Default do nothing - Implemented by subclasses
        return False

    def protocol_cmd(self, cmd_name, *cmd_args, read_write="READ_WRITE", index=-1):
        read_write = str(read_write).upper()
        if read_write not in ["READ", "WRITE", "READ_WRITE"]:
            raise RuntimeError(
                f"Unknown protocol descriptor {read_write}. Must be 'READ', 'WRITE', or 'READ_WRITE'."
            )
        handled = False

        if index >= 0 or read_write == "READ_WRITE":
            # Reconstruct full list of protocols in correct order
            protocols = []
            read_protocols = self.read_protocols
            write_protocols = self.write_protocols[:]
            write_protocols.reverse()
            read_index = 0
            write_index = 0
            for (
                _,
                _,
                protocol_read_write,
            ) in self.protocol_info:
                match protocol_read_write:
                    case "READ":
                        protocols.append(read_protocols[read_index])
                        read_index += 1
                    case "WRITE":
                        protocols.append(write_protocols[write_index])
                        write_index += 1
                    case "READ_WRITE" | "PARAMS":
                        protocols.append(read_protocols[read_index])
                        read_index += 1
                        write_index += 1

            for protocol_index, protocol in enumerate(protocols):
                result = None
                # If index is given that is all that matters
                if index == protocol_index or index == -1:
                    result = protocol.protocol_cmd(cmd_name, *cmd_args)
                if result:
                    handled = True
        elif read_write == "READ":  # and index == -1
            for protocol in self.read_protocols:
                result = protocol.protocol_cmd(cmd_name, *cmd_args)
                if result:
                    handled = True
        else:  # read_write == 'WRITE' and index == -1
            for protocol in self.write_protocols:
                result = protocol.protocol_cmd(cmd_name, *cmd_args)
                if result:
                    handled = True
        return handled