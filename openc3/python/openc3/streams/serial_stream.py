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

import threading
import logging
from typing import Optional, Union

from .stream import Stream
from ..io.serial_driver import SerialDriver
from ..config.config_parser import ConfigParser


class SerialStream(Stream):
    """Stream that reads and writes to serial ports by using SerialDriver."""
    
    def __init__(self,
                 write_port_name: Optional[str],
                 read_port_name: Optional[str],
                 baud_rate: int,
                 parity: str,
                 stop_bits: int,
                 write_timeout: Optional[float],
                 read_timeout: Optional[float],
                 flow_control: str = 'NONE',
                 data_bits: int = 8):
        """
        Initialize the serial stream
        
        Args:
            write_port_name: The name of the serial port to write.
                Pass None if the stream is to be read only. On Windows the port name
                is typically 'COMX' where X can be any port number. On UNIX the port
                name is typically a device such as '/dev/ttyS0'.
            read_port_name: The name of the serial port to read.
                Pass None if the stream is to be read only. On Windows the port name
                is typically 'COMX' where X can be any port number. On UNIX the port
                name is typically a device such as '/dev/ttyS0'.
            baud_rate: The serial port baud rate
            parity: Must be 'NONE', 'EVEN', or 'ODD'
            stop_bits: Stop bits. Must be 1 or 2.
            write_timeout: Seconds to wait for the write to complete.
                The SerialDriver will continuously try to send the data until
                it has been sent or an error occurs.
            read_timeout: Seconds to wait for the read to complete.
                Pass None to block until the read is complete. The SerialDriver will
                continuously try to read data until it has received data or an error occurs.
            flow_control: Currently supported 'NONE' and 'RTSCTS' (default 'NONE')
            data_bits: Number of data bits (default 8)
        """
        super().__init__()
        
        # The SerialDriver class will validate the parameters
        self.write_port_name = ConfigParser.handle_none(write_port_name)
        self.read_port_name = ConfigParser.handle_none(read_port_name)
        self.baud_rate = int(baud_rate)
        self.parity = parity
        self.stop_bits = int(stop_bits)
        
        self.write_timeout = ConfigParser.handle_none(write_timeout)
        if self.write_timeout is not None:
            self.write_timeout = float(self.write_timeout)
        else:
            logging.warning("Warning: To avoid interface lock, write_timeout can not be None. Setting to 10 seconds.")
            self.write_timeout = 10.0
            
        self.read_timeout = ConfigParser.handle_none(read_timeout)
        if self.read_timeout is not None:
            self.read_timeout = float(self.read_timeout)
            
        self.flow_control = flow_control
        self.data_bits = int(data_bits)
        
        # Create write serial port if specified
        if self.write_port_name:
            self.write_serial_port = SerialDriver(
                port_name=self.write_port_name,
                baud_rate=self.baud_rate,
                parity=self.parity,
                stop_bits=self.stop_bits,
                write_timeout=self.write_timeout,
                read_timeout=self.read_timeout,
                flow_control=self.flow_control,
                data_bits=self.data_bits
            )
        else:
            self.write_serial_port = None
            
        # Create read serial port if specified
        if self.read_port_name:
            if self.read_port_name == self.write_port_name:
                # Use the same serial port for both read and write
                self.read_serial_port = self.write_serial_port
            else:
                # Create separate serial port for reading
                self.read_serial_port = SerialDriver(
                    port_name=self.read_port_name,
                    baud_rate=self.baud_rate,
                    parity=self.parity,
                    stop_bits=self.stop_bits,
                    write_timeout=self.write_timeout,
                    read_timeout=self.read_timeout,
                    flow_control=self.flow_control,
                    data_bits=self.data_bits
                )
        else:
            self.read_serial_port = None
            
        if self.read_serial_port is None and self.write_serial_port is None:
            raise ValueError("Either a write port or read port must be given")
        
        # We 'connect' when we create the stream
        self._connected = True
        
        # Mutex on write is needed to protect from commands coming in from more
        # than one tool
        self._write_mutex = threading.Lock()
    
    def connect(self):
        """Connect the stream"""
        # N/A - Serial streams 'connect' on creation
        pass
    
    def connected(self) -> bool:
        """
        Returns:
            Whether the serial stream is connected to the serial port
        """
        return self._connected
    
    def disconnect(self):
        """Disconnect by closing the serial ports"""
        if self._connected:
            try:
                if self.write_serial_port and not self.write_serial_port.closed():
                    self.write_serial_port.close()
            except IOError:
                # Ignore
                pass
            
            try:
                if (self.read_serial_port and 
                    self.read_serial_port != self.write_serial_port and
                    not self.read_serial_port.closed()):
                    self.read_serial_port.close()
            except IOError:
                # Ignore
                pass
                
            self._connected = False
    
    def read(self) -> bytes:
        """
        Returns:
            Binary data from the serial port
        """
        if not self.read_serial_port:
            raise RuntimeError("Attempt to read from write only stream")
        
        # No read mutex is needed because reads happen serially
        return self.read_serial_port.read()
    
    def read_nonblock(self) -> bytes:
        """
        Returns:
            Binary data from the serial port without blocking
        """
        if not self.read_serial_port:
            raise RuntimeError("Attempt to read from write only stream")
        
        # No read mutex is needed because reads happen serially
        return self.read_serial_port.read_nonblock()
    
    def write(self, data: Union[str, bytes]) -> None:
        """
        Write data to the serial port
        
        Args:
            data: Binary data to write to the serial port
        """
        if not self.write_serial_port:
            raise RuntimeError("Attempt to write to read only stream")
        
        with self._write_mutex:
            self.write_serial_port.write(data)