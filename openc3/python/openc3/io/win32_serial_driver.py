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
import re
from typing import Optional, Union

try:
    import serial
    import serial.win32
except ImportError:
    raise ImportError("pyserial package is required for Win32 serial communication")


class Win32SerialDriver:
    """Serial driver for use on Windows serial ports"""
    
    # Win32 Constants
    NOPARITY = 0
    ODDPARITY = 1
    EVENPARITY = 2
    
    ONESTOPBIT = 0
    TWOSTOPBITS = 2
    
    BAUD_RATES = [
        110, 300, 600, 1200, 2400, 4800, 9600, 14400, 19200, 38400,
        56000, 57600, 115200, 128000, 256000, 230400, 460800, 500000,
        576000, 921600, 1000000, 1152000, 1500000, 2000000, 3000000,
        3500000, 4000000
    ]
    
    def __init__(self,
                 port_name: str = 'COM1',
                 baud_rate: int = 9600,
                 parity: str = 'NONE',
                 stop_bits: int = 1,
                 write_timeout: float = 10.0,
                 read_timeout: Optional[float] = None,
                 read_polling_period: float = 0.01,
                 read_max_length: int = 1000,
                 flow_control: str = 'NONE',
                 data_bits: int = 8):
        
        # Verify parameters
        if re.match(r'^COM[0-9]{2,3}$', port_name):
            port_name = f'\\\\.\\{port_name}'
        
        if baud_rate not in self.BAUD_RATES:
            raise ValueError(f"Invalid baud rate: {baud_rate}")
        
        if data_bits not in [5, 6, 7, 8]:
            raise ValueError(f"Invalid data bits: {data_bits}")
        
        valid_parity = ['EVEN', 'ODD', 'NONE']
        if parity and parity not in valid_parity:
            raise ValueError(f"Invalid parity: {parity}")
        
        # Convert parity to pyserial constants
        parity_map = {
            'ODD': serial.PARITY_ODD,
            'EVEN': serial.PARITY_EVEN,
            'NONE': serial.PARITY_NONE
        }
        serial_parity = parity_map[parity]
        
        if stop_bits not in [1, 2]:
            raise ValueError(f"Invalid stop bits: {stop_bits}")
        
        # Convert stop bits to pyserial constants
        serial_stopbits = serial.STOPBITS_TWO if stop_bits == 2 else serial.STOPBITS_ONE
        
        self.write_timeout = write_timeout
        self.read_timeout = read_timeout
        self.read_polling_period = read_polling_period
        self.read_max_length = read_max_length
        
        # Configure flow control
        rtscts = (flow_control == 'RTSCTS')
        
        # Open the serial port using pyserial
        try:
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
        except serial.SerialException as e:
            raise RuntimeError(f"Error opening serial port: {e}")
        
        self.mutex = threading.Lock()
    
    def close(self):
        """Close the serial port"""
        if hasattr(self, 'handle') and self.handle and self.handle.is_open:
            with self.mutex:
                self.handle.close()
                self.handle = None
    
    def closed(self) -> bool:
        """Check if the serial port is closed"""
        return not (hasattr(self, 'handle') and self.handle and self.handle.is_open)
    
    def write(self, data: Union[str, bytes]) -> None:
        """Write data to the serial port"""
        if isinstance(data, str):
            data = data.encode('latin-1')
        
        start_time = time.time()
        bytes_to_write = len(data)
        total_bytes_written = 0
        
        while total_bytes_written < bytes_to_write:
            try:
                bytes_written = self.handle.write(data[total_bytes_written:])
                if bytes_written <= 0:
                    raise RuntimeError("Error writing to comm port")
                
                total_bytes_written += bytes_written
                
                # Check for write timeout
                if (self.write_timeout and 
                    (time.time() - start_time > self.write_timeout) and 
                    total_bytes_written < bytes_to_write):
                    raise TimeoutError("Write Timeout")
                    
            except serial.SerialTimeoutException:
                raise TimeoutError("Write Timeout")
    
    def read(self) -> bytes:
        """Read data from the serial port"""
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
        """Read data from the serial port without blocking"""
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