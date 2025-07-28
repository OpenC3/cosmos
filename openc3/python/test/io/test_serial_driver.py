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
from unittest.mock import Mock, patch

from openc3.io.serial_driver import SerialDriver
from openc3.io.posix_serial_driver import PosixSerialDriver


class TestSerialDriver:
    def test_instance_enforces_parity_to_known_value(self):
        """Test that invalid parity values raise ArgumentError"""
        with pytest.raises(ValueError, match="Invalid parity: BLAH"):
            SerialDriver('COM1', 9600, 'BLAH')

    def test_close_closed_write_read_defers_to_posix_serial_driver_on_nix(self):
        """Test that methods defer to the posix serial driver on nix"""
        with patch('platform.system', return_value='Linux'):
            driver_mock = Mock()
            driver_mock.close = Mock()
            driver_mock.closed = Mock()
            driver_mock.write = Mock()
            driver_mock.read = Mock()
            
            with patch.object(PosixSerialDriver, '__new__', return_value=driver_mock):
                driver = SerialDriver('COM1', 9600)
                driver.close()
                driver.closed()
                driver.write("hi")
                driver.read()
                
                driver_mock.close.assert_called_once()
                driver_mock.closed.assert_called_once()
                driver_mock.write.assert_called_once_with("hi")
                driver_mock.read.assert_called_once()