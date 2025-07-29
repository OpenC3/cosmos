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

import platform
from typing import Optional, Union

# Platform-specific imports
if platform.system() == 'Windows':
    from .win32_serial_driver import Win32SerialDriver
else:
    from .posix_serial_driver import PosixSerialDriver


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
                 data_bits: int = 8):
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
        """

        if parity not in self.VALID_PARITY:
            raise ValueError(f"Invalid parity: {parity}")
        
        if platform.system() == 'Windows':
            self.driver = Win32SerialDriver(
                port_name=port_name,
                baud_rate=baud_rate,
                parity=parity,
                stop_bits=stop_bits,
                write_timeout=write_timeout,
                read_timeout=read_timeout,
                read_polling_period=0.01,
                read_max_length=1000,
                flow_control=flow_control,
                data_bits=data_bits
            )
        else:
            # POSIX systems (Linux, macOS, etc.)
            self.driver = PosixSerialDriver(
                port_name=port_name,
                baud_rate=baud_rate,
                parity=parity,
                stop_bits=stop_bits,
                write_timeout=write_timeout,
                read_timeout=read_timeout,
                flow_control=flow_control,
                data_bits=data_bits
            )
    
    def close(self) -> None:
        """Disconnects the driver from the comm port"""
        self.driver.close()
    
    def closed(self) -> bool:
        """
        Returns:
            [Boolean] Whether the serial port has been closed
        """
        return self.driver.closed()

    def write(self, data: Union[str, bytes]) -> None:
        """
        Args:
            data: [String | bytes] Binary data to write to the serial port
        """
        self.driver.write(data)

    def read(self) -> bytes:
        """
        Returns:
            [bytes] Binary data read from the serial port
        """
        return self.driver.read()
    
    def read_nonblock(self) -> bytes:
        """
        Returns:
            [bytes] Binary data read from the serial port
        """
        return self.driver.read_nonblock()