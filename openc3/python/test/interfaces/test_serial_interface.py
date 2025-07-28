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
import os
import platform
from unittest.mock import Mock, patch

# Mock dependencies before imports
sys.modules['serial'] = Mock()
sys.modules['serial.win32'] = Mock()
sys.modules['termios'] = Mock()
sys.modules['fcntl'] = Mock()

from openc3.interfaces.serial_interface import SerialInterface


class TestSerialInterface:
    def test_initialize_initializes_the_instance_variables(self):
        """Test that initialize sets up instance variables correctly"""
        i = SerialInterface('COM1', 'COM1', 9600, 'NONE', 1, 0, 0, 'burst')
        assert i.name == "SerialInterface"

    def test_initialize_is_not_writeable_if_no_write_port_given(self):
        """Test that interface is not writeable when write port is nil"""
        i = SerialInterface('nil', 'COM1', 9600, 'NONE', 1, 0, 0, 'burst')
        assert i.write_allowed == False
        assert i.write_raw_allowed == False
        assert i.read_allowed == True

    def test_initialize_is_not_readable_if_no_read_port_given(self):
        """Test that interface is not readable when read port is nil"""
        i = SerialInterface('COM1', 'nil', 9600, 'NONE', 1, 0, 0, 'burst')
        assert i.write_allowed == True
        assert i.write_raw_allowed == True
        assert i.read_allowed == False

    def test_connection_string_builds_a_human_readable_connection_string(self):
        """Test that connection_string returns proper description"""
        i = SerialInterface('COM1', 'COM1', 9600, 'NONE', 1, 0, 0)
        assert i.connection_string() == "COM1 (R/W) 9600 NONE 1"

        i = SerialInterface('nil', 'COM1', 9600, 'NONE', 1, 0, 0)
        assert i.connection_string() == "COM1 (read only) 9600 NONE 1"

        i = SerialInterface('COM1', 'nil', 9600, 'NONE', 1, 0, 0)
        assert i.connection_string() == "COM1 (write only) 9600 NONE 1"