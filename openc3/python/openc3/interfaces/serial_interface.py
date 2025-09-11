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

from typing import Optional, List, Any

from openc3.interfaces.stream_interface import StreamInterface
from openc3.streams.serial_stream import SerialStream
from openc3.config.config_parser import ConfigParser


class SerialInterface(StreamInterface):
    """Provides a base class for interfaces that use serial ports"""
    
    
    def __init__(self,
                 write_port_name: Optional[str],
                 read_port_name: Optional[str],
                 baud_rate: int,
                 parity: str,
                 stop_bits: int,
                 write_timeout: Optional[float],
                 read_timeout: Optional[float],
                 protocol_type: Optional[str] = None,
                 *protocol_args):
        """
        Creates a serial interface which uses the specified stream protocol.
        
        Args:
            write_port_name: [String] The name of the serial port to write
            read_port_name: [String] The name of the serial port to read
            baud_rate: [Integer] The serial port baud rate
            parity: [String] The parity which is normally 'NONE'.
                Must be one of 'NONE', 'EVEN', or 'ODD'.
            stop_bits: [Integer] The number of stop bits which is normally 1.
            write_timeout: [Float] Seconds to wait before aborting writes
            read_timeout: [Float | None] Seconds to wait before aborting reads.
                Pass None to block until the read is complete.
            protocol_type: [String] Combined with 'Protocol' to resolve
                to a OpenC3 protocol class
            protocol_args: [List] Arguments to pass to the protocol constructor
        """
        super().__init__(protocol_type, list(protocol_args))
        
        self.write_port_name = ConfigParser.handle_none(write_port_name)
        self.read_port_name = ConfigParser.handle_none(read_port_name)
        self.baud_rate = baud_rate
        self.parity = parity
        self.stop_bits = stop_bits
        self.write_timeout = write_timeout
        self.read_timeout = read_timeout
        
        # Set interface capabilities based on port configuration
        if not self.write_port_name:
            self.write_allowed = False
            self.write_raw_allowed = False
        if not self.read_port_name:
            self.read_allowed = False
            
        # Default serial settings
        self.flow_control = 'NONE'
        self.data_bits = 8
    
    def connection_string(self) -> str:
        type_str = ''
        if self.write_port_name and self.read_port_name:
            port = self.write_port_name
            type_str = 'R/W'
        elif self.write_port_name:
            port = self.write_port_name
            type_str = 'write only'
        else:
            port = self.read_port_name
            type_str = 'read only'
        
        return f"{port} ({type_str}) {self.baud_rate} {self.parity} {self.stop_bits}"
    
    def connect(self):
        """Creates a new SerialStream using the parameters passed in the constructor"""
        self.stream = SerialStream(
            write_port_name=self.write_port_name,
            read_port_name=self.read_port_name,
            baud_rate=self.baud_rate,
            parity=self.parity,
            stop_bits=self.stop_bits,
            write_timeout=self.write_timeout,
            read_timeout=self.read_timeout,
            flow_control=self.flow_control,
            data_bits=self.data_bits
        )
        super().connect()
    
    def set_option(self, option_name: str, option_values: List[Any]):
        """
        Set interface options
        
        Supported Options:
        - FLOW_CONTROL: Flow control method NONE or RTSCTS. Defaults to NONE
        - DATA_BITS: Number of data bits 5, 6, 7, or 8. Defaults to 8
        
        Args:
            option_name: Name of the option to set
            option_values: List of values for the option
        """
        super().set_option(option_name, option_values)
        
        option_name_upper = option_name.upper()
        if option_name_upper == 'FLOW_CONTROL':
            self.flow_control = option_values[0]
        elif option_name_upper == 'DATA_BITS':
            self.data_bits = int(option_values[0])