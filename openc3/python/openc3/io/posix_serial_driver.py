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

import os
import fcntl
import termios
import select
import time
from typing import Optional, Union


class PosixSerialDriver:
    """Serial driver for use on Posix serial ports found on UNIX based systems"""
    
    def __init__(self, 
                 port_name: str = '/dev/ttyS0',
                 baud_rate: int = 9600,
                 parity: str = 'NONE',
                 stop_bits: int = 1,
                 write_timeout: float = 10.0,
                 read_timeout: Optional[float] = None,
                 flow_control: str = 'NONE',
                 data_bits: int = 8):
        
        # Convert baud rate to termios constant
        baud_constant = getattr(termios, f'B{baud_rate}', None)
        if baud_constant is None:
            raise ValueError(f"Invalid Baud Rate, Not Defined by termios: {baud_rate}")
        
        # Verify parameters
        if data_bits not in [5, 6, 7, 8]:
            raise ValueError(f"Invalid Data Bits: {data_bits}")
        
        valid_parity = ['EVEN', 'ODD', 'NONE']
        if parity and parity not in valid_parity:
            raise ValueError(f"Invalid parity: {parity}")
        
        if stop_bits not in [1, 2]:
            raise ValueError(f"Invalid Stop Bits: {stop_bits}")
        
        self.write_timeout = write_timeout
        self.read_timeout = read_timeout
        
        parity = None if parity == 'NONE' else parity
        
        # Open the serial port
        self.handle = os.open(port_name, os.O_RDWR | os.O_NONBLOCK)
        flags = fcntl.fcntl(self.handle, fcntl.F_GETFL)
        fcntl.fcntl(self.handle, fcntl.F_SETFL, flags & ~os.O_NONBLOCK)
        
        # Configure the serial port
        tio = termios.tcgetattr(self.handle)
        
        # Input flags
        iflags = 0
        if not parity:
            iflags |= termios.IGNPAR
        
        # Control flags
        cflags = 0
        cflags |= termios.CREAD  # Enable receiver
        
        # Data bits
        data_bits_map = {5: termios.CS5, 6: termios.CS6, 7: termios.CS7, 8: termios.CS8}
        cflags |= data_bits_map[data_bits]
        
        cflags |= termios.CLOCAL  # Ignore modem control lines
        
        if stop_bits == 2:
            cflags |= termios.CSTOPB
        
        if parity:
            cflags |= termios.PARENB
            if parity == 'ODD':
                cflags |= termios.PARODD
        
        if flow_control == 'RTSCTS':
            cflags |= termios.CRTSCTS
        
        # Set termios attributes
        tio[0] = iflags        # iflag
        tio[1] = 0             # oflag
        tio[2] = cflags        # cflag
        tio[3] = 0             # lflag
        tio[4] = baud_constant # ispeed
        tio[5] = baud_constant # ospeed
        
        # Control characters
        tio[6][termios.VTIME] = 0
        tio[6][termios.VMIN] = 1
        
        # Flush and apply settings
        termios.tcflush(self.handle, termios.TCIOFLUSH)
        termios.tcsetattr(self.handle, termios.TCSANOW, tio)
        
        # Create pipe for interrupting reads
        self.pipe_reader, self.pipe_writer = os.pipe()
        self.readers = [self.handle, self.pipe_reader]
    
    def close(self):
        """Close the serial port"""
        if hasattr(self, 'handle') and self.handle is not None:
            # Signal the pipe to interrupt any pending reads
            os.write(self.pipe_writer, b'.')
            os.close(self.pipe_writer)
            os.close(self.handle)
            os.close(self.pipe_reader)
            self.handle = None
    
    def closed(self) -> bool:
        """Check if the serial port is closed"""
        return self.handle is None
    
    def write(self, data: Union[str, bytes]) -> None:
        """Write data to the serial port"""
        if isinstance(data, str):
            data = data.encode('latin-1')
        
        num_bytes_to_send = len(data)
        total_bytes_sent = 0
        
        while total_bytes_sent < num_bytes_to_send:
            try:
                bytes_sent = os.write(self.handle, data[total_bytes_sent:])
                total_bytes_sent += bytes_sent
            except (BlockingIOError, OSError):
                # Wait for write readiness
                ready = select.select([], [self.handle], [], self.write_timeout)
                if not ready[1]:
                    raise TimeoutError("Write Timeout")
    
    def read(self) -> bytes:
        """Read data from the serial port"""
        try:
            data = os.read(self.handle, 65535)
            return data
        except (BlockingIOError, OSError):
            try:
                read_ready, _, _ = select.select(self.readers, [], [], self.read_timeout)
            except OSError:
                if not os.get_inheritable(self.pipe_reader):
                    return b""
                raise
            
            if read_ready:
                if self.pipe_reader in read_ready:
                    return b""
                else:
                    # Recursive call to actually read the data
                    return self.read()
            else:
                raise TimeoutError("Read Timeout")
    
    def read_nonblock(self) -> bytes:
        """Read data from the serial port without blocking"""
        try:
            data = os.read(self.handle, 65535)
            return data
        except (BlockingIOError, OSError):
            return b""