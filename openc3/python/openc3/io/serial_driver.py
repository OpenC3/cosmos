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

import time
import threading
from typing import Optional, Union
import serial

class SerialDriver:
    """A platform independent serial driver"""
    
    # Parity constants
    EVEN = 'EVEN'
    ODD = 'ODD'
    NONE = 'NONE'
    VALID_PARITY = [EVEN, ODD, NONE]
    
    def __init__(self,
                 port_name: str,
                 baud_rate: int,
                 parity: str = 'NONE',
                 stop_bits: int = 1,
                 write_timeout: float = 10.0,
                 read_timeout: Optional[float] = None,
                 flow_control: str = 'NONE',
                 data_bits: int = 8,
                 read_polling_period: float = 0.01,
                 read_max_length: int = 1000):
        """
          port_name: [String] Name of the serial port
          baud_rate: [Integer] Serial port baud rate
          parity: [String] Must be one of 'EVEN', 'ODD' or 'NONE'
          stop_bits: [Integer] Number of stop bits
          write_timeout: [Float] Seconds to wait before aborting writes
          read_timeout: [Float | None] Seconds to wait before aborting reads.
                        Pass None to block until the read is complete.
          flow_control: [String] Currently supported 'NONE' and 'RTSCTS' (default 'NONE')
          data_bits: [Integer] Number of data bits (default 8)
          read_polling_period: [Float] Sleep time between read attempts (default 0.01)
          read_max_length: [Integer] Maximum bytes to read at once (default 1000)
        """

        if parity not in self.VALID_PARITY:
            raise ValueError(f"Invalid parity: {parity}")
        
        if data_bits not in [5, 6, 7, 8]:
            raise ValueError(f"Invalid data bits: {data_bits}")
        
        if stop_bits not in [1, 2]:
            raise ValueError(f"Invalid stop bits: {stop_bits}")
        
        # Convert parity to pyserial constants
        parity_map = {
            'ODD': serial.PARITY_ODD,
            'EVEN': serial.PARITY_EVEN,
            'NONE': serial.PARITY_NONE
        }
        serial_parity = parity_map[parity]
        
        # Convert stop bits to pyserial constants
        serial_stopbits = serial.STOPBITS_TWO if stop_bits == 2 else serial.STOPBITS_ONE
        
        # Configure flow control
        rtscts = (flow_control == 'RTSCTS')
        
        self.write_timeout = write_timeout
        self.read_timeout = read_timeout
        self.read_polling_period = read_polling_period
        self.read_max_length = read_max_length
        
        # Open the serial port using pyserial
        self.handle = serial.Serial(
            port=port_name,
            baudrate=baud_rate,
            bytesize=data_bits,
            parity=serial_parity,
            stopbits=serial_stopbits,
            timeout=None,  # We'll handle timeouts manually
            write_timeout=write_timeout,
            rtscts=rtscts
        )
        
        self.mutex = threading.Lock()
    
    def close(self) -> None:
        """Disconnects the driver from the comm port"""
        if hasattr(self, 'handle') and self.handle and self.handle.is_open:
            with self.mutex:
                self.handle.close()
                self.handle = None
    
    def closed(self) -> bool:
        """
        Returns:
            [Boolean] Whether the serial port has been closed
        """
        return not (hasattr(self, 'handle') and self.handle and self.handle.is_open)

    def write(self, data: Union[str, bytes]) -> None:
        """
        Args:
            data: [String | bytes] Binary data to write to the serial port
        """
        if isinstance(data, str):
            data = data.encode('latin-1')
        
        start_time = time.time()
        bytes_to_write = len(data)
        total_bytes_written = 0
        
        while total_bytes_written < bytes_to_write:
            bytes_written = self.handle.write(data[total_bytes_written:])
            if bytes_written <= 0:
                raise RuntimeError("Error writing to comm port")
            
            total_bytes_written += bytes_written
            
            # Check for write timeout
            if (self.write_timeout and 
                (time.time() - start_time > self.write_timeout) and 
                total_bytes_written < bytes_to_write):
                raise TimeoutError("Write Timeout")

    def read(self) -> bytes:
        """
        Returns:
            [bytes] Binary data read from the serial port
        """
        data = b''
        sleep_time = 0.0
        
        while True:
            # Inner loop to read available data
            while True:
                buffer = None
                with self.mutex:
                    if not self.handle or not self.handle.is_open:
                        break
                    
                    # Read available bytes
                    available = self.handle.in_waiting
                    if available > 0:
                        read_size = min(available, self.read_max_length - len(data))
                        if read_size > 0:
                            buffer = self.handle.read(read_size)
                
                if not buffer:
                    break
                
                data += buffer
                if (len(buffer) <= 0 or 
                    len(data) >= self.read_max_length or 
                    not self.handle or 
                    not self.handle.is_open):
                    break
            
            # Break if we have data or handle is closed
            if len(data) > 0 or not self.handle or not self.handle.is_open:
                break
            
            # Check for read timeout
            if self.read_timeout and sleep_time >= self.read_timeout:
                raise TimeoutError("Read Timeout")
            
            # Sleep and update sleep time
            time.sleep(self.read_polling_period)
            sleep_time += self.read_polling_period
        
        return data
    
    def read_nonblock(self) -> bytes:
        """
        Returns:
            [bytes] Binary data read from the serial port
        """
        data = b''
        
        while True:
            available = self.handle.in_waiting
            if available <= 0:
                break
                
            read_size = min(available, self.read_max_length - len(data))
            if read_size <= 0:
                break
                
            buffer = self.handle.read(read_size)
            data += buffer
            
            if len(buffer) <= 0 or len(data) >= self.read_max_length:
                break
        
        return data