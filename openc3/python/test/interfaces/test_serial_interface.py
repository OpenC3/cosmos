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

import sys
import math
from unittest.mock import Mock

# Mock dependencies before imports
sys.modules['serial'] = Mock()

from openc3.interfaces.serial_interface import SerialInterface


class TestSerialInterface:
    def test_initialize_initializes_the_instance_variables(self):
        """Test that initialize sets up instance variables correctly"""
        i = SerialInterface('COM1', 'COM1', 9600, 'NONE', 1, 0, 0, 'burst')
        assert i.name == "SerialInterface"

    def test_initialize_is_not_writeable_if_no_write_port_given(self):
        """Test that interface is not writeable when write port is None"""
        i = SerialInterface('NONE', 'COM1', 9600, 'NONE', 1, 0, 0, 'burst')
        assert not i.write_allowed
        assert not i.write_raw_allowed
        assert i.read_allowed

    def test_initialize_is_not_readable_if_no_read_port_given(self):
        """Test that interface is not readable when read port is None"""
        i = SerialInterface('COM1', 'NONE', 9600, 'NONE', 1, 0, 0, 'burst')
        assert i.write_allowed
        assert i.write_raw_allowed
        assert not i.read_allowed

    def test_connection_string_builds_a_human_readable_connection_string(self):
        """Test that connection_string returns proper description"""
        i = SerialInterface('COM1', 'COM1', 9600, 'NONE', 1, 0, 0)
        assert i.connection_string() == "COM1 (R/W) 9600 NONE 1"

        i = SerialInterface('NONE', 'COM1', 9600, 'NONE', 1, 0, 0)
        assert i.connection_string() == "COM1 (read only) 9600 NONE 1"

        i = SerialInterface('COM1', 'NONE', 9600, 'NONE', 1, 0, 0)
        assert i.connection_string() == "COM1 (write only) 9600 NONE 1"

    def test_details(self):
        """Test that details returns correct interface information"""
        i = SerialInterface('/dev/ttyUSB0', '/dev/ttyUSB1', 115200, 'EVEN', 2, 5.0, 10.0, 'burst')
        details = i.details()

        # Verify it returns a dictionary
        assert isinstance(details, dict)

        # Check that it includes the expected keys specific to SerialInterface
        assert 'write_port_name' in details
        assert 'read_port_name' in details
        assert 'baud_rate' in details
        assert 'parity' in details
        assert 'stop_bits' in details
        assert 'write_timeout' in details
        assert 'read_timeout' in details
        assert 'flow_control' in details
        assert 'data_bits' in details

        # Verify the specific values are correct
        assert details['write_port_name'] == "/dev/ttyUSB0"
        assert details['read_port_name'] == "/dev/ttyUSB1"
        assert details['baud_rate'] == 115200
        assert details['parity'] == "EVEN"
        assert details['stop_bits'] == 2
        assert math.isclose(details['write_timeout'],5.0)
        assert math.isclose(details['read_timeout'],10.0)
        assert details['flow_control'] == 'NONE'  # default value
        assert details['data_bits'] == 8  # default value

    def test_details_with_none_ports(self):
        """Test that details handles None port values correctly"""
        i = SerialInterface('NONE', '/dev/ttyUSB0', 9600, 'NONE', 1, None, 10.0, 'burst')
        details = i.details()

        # Verify it returns a dictionary
        assert isinstance(details, dict)

        # Check None values are preserved
        assert details['write_port_name'] is None
        assert details['read_port_name'] == "/dev/ttyUSB0"
        assert details['baud_rate'] == 9600
        assert details['parity'] == "NONE"
        assert details['stop_bits'] == 1
        assert details['write_timeout'] is None
        assert math.isclose(details['read_timeout'],10.0)

    def test_details_with_different_settings(self):
        """Test that details works with various parameter combinations"""
        i = SerialInterface('COM1', 'COM2', 38400, 'ODD', 2, 15.0, None, 'burst')
        details = i.details()

        # Verify it returns a dictionary
        assert isinstance(details, dict)

        # Check different parameter values
        assert details['write_port_name'] == "COM1"
        assert details['read_port_name'] == "COM2"
        assert details['baud_rate'] == 38400
        assert details['parity'] == "ODD"
        assert details['stop_bits'] == 2
        assert math.isclose(details['write_timeout'],15.0)
        assert details['read_timeout'] is None