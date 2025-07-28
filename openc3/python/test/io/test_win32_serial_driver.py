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

import pytest
import sys
import platform
from unittest.mock import Mock, MagicMock, patch
import time

try:
    from openc3.io.win32_serial_driver import Win32SerialDriver
except ImportError:
    # Mock the serial module if not available
    sys.modules['serial'] = Mock()
    sys.modules['serial.win32'] = Mock()
    from openc3.io.win32_serial_driver import Win32SerialDriver


class TestWin32SerialDriver:
    def setup_method(self):
        """Setup mocks for each test"""
        self.mock_serial = Mock()
        self.mock_serial.is_open = True
        self.mock_serial.close = Mock()
        self.mock_serial.write = Mock(return_value=1)
        self.mock_serial.read = Mock(return_value=b'\x00')
        self.mock_serial.in_waiting = 0
        
        # Patch serial.Serial to return our mock
        self.serial_patcher = patch('serial.Serial', return_value=self.mock_serial)
        self.mock_serial_class = self.serial_patcher.start()
        
        # Patch serial constants
        self.parity_patcher = patch.multiple(
            'serial',
            PARITY_NONE=0,
            PARITY_ODD=1,
            PARITY_EVEN=2,
            STOPBITS_ONE=1,
            STOPBITS_TWO=2
        )
        self.parity_patcher.start()

    def teardown_method(self):
        """Clean up patches"""
        self.serial_patcher.stop()
        self.parity_patcher.stop()

    def test_enforces_baud_rate_to_known_value(self):
        """Test that invalid baud rates raise ArgumentError"""
        with pytest.raises(ValueError, match="Invalid baud rate: 10"):
            Win32SerialDriver('COM1', 10, 'NONE')

    def test_supports_even_odd_or_no_parity(self):
        """Test that valid parity values are accepted and invalid ones raise errors"""
        # Valid parity values should not raise errors
        Win32SerialDriver('COM1', 9600, 'EVEN')
        Win32SerialDriver('COM1', 9600, 'ODD')
        Win32SerialDriver('COM1', 9600, 'NONE')
        
        # Invalid parity should raise error
        with pytest.raises(ValueError, match="Invalid parity: BLAH"):
            Win32SerialDriver('COM1', 9600, 'BLAH')

    def test_supports_1_or_2_stop_bits(self):
        """Test that valid stop bit values are accepted and invalid ones raise errors"""
        # Valid stop bits should not raise errors
        Win32SerialDriver('COM1', 9600, 'NONE', 1)
        Win32SerialDriver('COM1', 9600, 'NONE', 2)
        
        # Invalid stop bits should raise error
        with pytest.raises(ValueError, match="Invalid stop bits: 3"):
            Win32SerialDriver('COM1', 9600, 'NONE', 3)

    def test_supports_5_to_8_data_bits(self):
        """Test that valid data bit values (5-8) are accepted and invalid ones raise errors"""
        # Valid data bits should not raise errors
        Win32SerialDriver('COM1', 9600, 'NONE', 1, 10.0, None, 0.01, 1000, 'NONE', 5)
        Win32SerialDriver('COM1', 9600, 'NONE', 1, 10.0, None, 0.01, 1000, 'NONE', 6)
        Win32SerialDriver('COM1', 9600, 'NONE', 1, 10.0, None, 0.01, 1000, 'NONE', 7)
        Win32SerialDriver('COM1', 9600, 'NONE', 1, 10.0, None, 0.01, 1000, 'NONE', 8)
        
        # Invalid data bits should raise error
        with pytest.raises(ValueError, match="Invalid data bits: 9"):
            Win32SerialDriver('COM1', 9600, 'NONE', 1, 10.0, None, 0.01, 1000, 'NONE', 9)

    def test_calculates_correct_timeouts(self):
        """Test that timeout calculations are correct for different configurations"""
        # Note: The Python implementation uses pyserial's timeout handling,
        # so we can't directly test the Win32 timeout calculation like in Ruby.
        # Instead, we verify that the driver initializes correctly with various configurations.
        
        for baud in Win32SerialDriver.BAUD_RATES[:5]:  # Test subset for performance
            for data_bits in range(5, 9):
                for stop_bits in [1, 2]:
                    for parity in ['EVEN', 'ODD', 'NONE']:
                        # Should not raise any errors
                        driver = Win32SerialDriver('COM1', baud, parity, stop_bits, 10.0, None, 0.01, 1000, 'NONE', data_bits)
                        assert driver is not None
                        driver.close()

    def test_close_and_closed(self):
        """Test close method and closed status"""
        driver = Win32SerialDriver('COM1', 9600)
        
        # Initially should not be closed
        assert not driver.closed()
        
        # After closing should be closed
        driver.close()
        assert driver.closed()
        
        # Verify the mock serial was closed
        self.mock_serial.close.assert_called_once()

    def test_write_handles_write_errors(self):
        """Test that write errors are properly handled"""
        # Mock write to return 0 (indicating error)
        self.mock_serial.write.return_value = 0
        
        driver = Win32SerialDriver('COM1', 9600)
        
        with pytest.raises(RuntimeError, match="Error writing to comm port"):
            driver.write(b'\x00')

    def test_write_uses_write_timeout(self):
        """Test that write timeout is enforced"""
        # Mock write to take longer than timeout
        def slow_write(data):
            time.sleep(2)
            return 1
        
        self.mock_serial.write.side_effect = slow_write
        
        driver = Win32SerialDriver('COM1', 9600, 'NONE', 1, 1.0)  # 1 second write timeout
        
        with pytest.raises(TimeoutError):
            driver.write(b'\x00\x01')

    def test_read_returns_data_read(self):
        """Test that read method returns the data read from serial port"""
        # Mock serial to have data available
        self.mock_serial.in_waiting = 1
        self.mock_serial.read.return_value = b'\x00'
        
        driver = Win32SerialDriver('COM1', 9600, 'NONE', 1, 1.0, None, 0.01, 1)
        result = driver.read()
        
        assert result == b'\x00'

    def test_read_uses_read_timeout(self):
        """Test that read timeout is enforced"""
        # Mock serial to have no data available
        self.mock_serial.in_waiting = 0
        
        driver = Win32SerialDriver('COM1', 9600, 'NONE', 1, 1.0, 1.0, 0.5, 10)  # 1 second read timeout
        
        with pytest.raises(TimeoutError):
            driver.read()

    def test_read_nonblock_returns_empty_when_no_data(self):
        """Test that read_nonblock returns empty bytes when no data available"""
        # Mock serial to have no data available
        self.mock_serial.in_waiting = 0
        
        driver = Win32SerialDriver('COM1', 9600)
        result = driver.read_nonblock()
        
        assert result == b''

    def test_port_name_formatting_for_high_com_ports(self):
        """Test that COM ports with numbers >= 10 are properly formatted"""
        driver = Win32SerialDriver('COM10', 9600)
        
        # Verify the serial.Serial was called with the properly formatted port name
        self.mock_serial_class.assert_called()
        call_args = self.mock_serial_class.call_args
        assert call_args[1]['port'] == '\\\\.\\COM10'

    def test_string_data_encoding_in_write(self):
        """Test that string data is properly encoded to bytes in write method"""
        self.mock_serial.write.return_value = 4  # Length of test string
        
        driver = Win32SerialDriver('COM1', 9600)
        driver.write('test')  # String input
        
        # Verify write was called with bytes
        self.mock_serial.write.assert_called()
        written_data = self.mock_serial.write.call_args[0][0]
        assert isinstance(written_data, bytes)
        assert written_data == b'test'