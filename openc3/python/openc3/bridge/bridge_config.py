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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os
import importlib
from openc3.utilities.logger import Logger
from openc3.config.config_parser import ConfigParser
from openc3.top_level import get_class_from_module
from openc3.logs.stream_log_pair import StreamLogPair
from openc3.utilities.string import (
    filename_to_module,
    filename_to_class_name,
    class_name_to_filename,
)


class BridgeConfig:
    def __init__(self, filename, existing_variables=None):
        if existing_variables is None:
            existing_variables = {}
        self.interfaces = {}
        self.routers = {}
        self.process_file(filename, existing_variables)

    @staticmethod
    def generate_default(filename):
        default_config = """# Write serial port name
VARIABLE write_port_name COM1
        
# Read serial port name
VARIABLE read_port_name COM1
        
# Baud Rate
VARIABLE baud_rate 115200
        
# Parity - NONE, ODD, or EVEN
VARIABLE parity NONE
        
# Stop bits - 0, 1, or 2
VARIABLE stop_bits 1
        
# Write Timeout
VARIABLE write_timeout 10.0
        
# Read Timeout
VARIABLE read_timeout nil
        
# Flow Control - NONE, or RTSCTS
VARIABLE flow_control NONE
        
# Data bits per word - Typically 8
VARIABLE data_bits 8
        
# Port to listen for connections from COSMOS - Plugin must match
VARIABLE router_port 2950
        
# Port to listen on for connections from COSMOS. Defaults to localhost for security. Will need to be opened
# if COSMOS is on another machine.
VARIABLE router_listen_address 127.0.0.1
        
INTERFACE SERIAL_INT openc3/interfaces/serial_interface.py <%= write_port_name %> <%= read_port_name %> <%= baud_rate %> <%= parity %> <%= stop_bits %> <%= write_timeout %> <%= read_timeout %>
  OPTION FLOW_CONTROL <%= flow_control %>
  OPTION DATA_BITS <%= data_bits %>
        
ROUTER SERIAL_ROUTER openc3/interfaces/tcpip_server_interface.py <%= router_port %> <%= router_port %> 10.0 nil BURST
  ROUTE SERIAL_INT
  OPTION LISTEN_ADDRESS <%= router_listen_address %>
        
"""

        Logger.info(f"Writing {filename}")
        with open(filename, 'w') as file:
            file.write(default_config)

    def process_file(self, filename, existing_variables=None):
        """Processes a file and adds in the configuration defined in the file
        
        Args:
            filename: The name of the configuration file to parse
            existing_variables: Dictionary of existing variables
        """
        if existing_variables is None:
            existing_variables = {}
            
        current_interface_or_router = None
        current_type = None

        Logger.info(f"Processing Bridge configuration in file: {os.path.abspath(filename)}")

        variables = {}
        parser = ConfigParser()
        for keyword, params in parser.parse_file(filename, False, True, False):
            if keyword == 'VARIABLE':
                usage = f"{keyword} <Variable Name> <Default Value>"
                parser.verify_num_parameters(2, None, usage)
                variable_name = params[0]
                value = ' '.join(params[1:])
                variables[variable_name] = value
                if existing_variables and variable_name in existing_variables:
                    variables[variable_name] = existing_variables[variable_name]


        parser = ConfigParser()
        for keyword, params in parser.parse_file(filename, False, True, True):
            match keyword:
                case 'VARIABLE':
                    # Ignore during this pass, below is to make CodeScanner pass (pass was not accepted)
                    ...
                case 'INTERFACE':
                    usage = "INTERFACE <Name> <Filename> <Specific Parameters>"
                    parser.verify_num_parameters(2, None, usage)
                    interface_name = params[0].upper()
                    if interface_name in self.interfaces:
                        raise parser.error(f"Interface '{interface_name}' defined twice")

                    interface_class = get_class_from_module(filename_to_module(params[1]), filename_to_class_name(params[1]))
                    if params[2]:
                        current_interface_or_router = interface_class(*params[2:])
                    else:
                        current_interface_or_router = interface_class()
                        
                    current_type = 'INTERFACE'
                    current_interface_or_router.name = interface_name
                    current_interface_or_router.config_params = params[1:]
                    self.interfaces[interface_name] = current_interface_or_router

                case 'RECONNECT_DELAY' | 'LOG_STREAM' | 'LOG_RAW' | 'OPTION' | 'PROTOCOL':
                    if current_interface_or_router is None:
                        raise parser.error(f"No current interface or router for {keyword}")

                    match keyword:

                        case 'RECONNECT_DELAY':
                            parser.verify_num_parameters(1, 1, f"{keyword} <Delay in Seconds>")
                            current_interface_or_router.reconnect_delay = float(params[0])

                        case 'LOG_STREAM' | 'LOG_RAW':
                            parser.verify_num_parameters(0, None, f"{keyword} <Log Stream Class File (optional)> <Log Stream Parameters (optional)>")
                            current_interface_or_router.stream_log_pair = StreamLogPair(current_interface_or_router.name, params)
                            current_interface_or_router.start_raw_logging()

                        case 'OPTION':
                            parser.verify_num_parameters(2, None, f"{keyword} <Option Name> <Option Value 1> <Option Value 2 (optional)> <etc>")
                            current_interface_or_router.set_option(params[0], params[1:])

                        case 'PROTOCOL':
                            usage = f"{keyword} <READ WRITE READ_WRITE> <protocol filename or classname> <Protocol specific parameters>"
                            parser.verify_num_parameters(2, None, usage)
                            if params[0].upper() not in ['READ', 'WRITE', 'READ_WRITE']:
                                raise parser.error(f"Invalid protocol type: {params[0]}", usage)

                            try:
                                protocol_class = get_class_from_module(filename_to_module(params[1]), filename_to_class_name(params[1]))
                                current_interface_or_router.add_protocol(protocol_class, params[2:], params[0].upper())
                            except Exception as error:
                                raise parser.error(str(error), usage) 

                case 'ROUTER':
                    usage = "ROUTER <Name> <Filename> <Specific Parameters>"
                    parser.verify_num_parameters(2, None, usage)
                    router_name = params[0].upper()
                    if router_name in self.routers:
                        raise parser.error(f"Router '{router_name}' defined twice")

                    router_class = get_class_from_module(filename_to_module(params[1]), filename_to_class_name(params[1]))
                    if len(params) > 2:
                        current_interface_or_router = router_class(*params[2:])
                    else:
                        current_interface_or_router = router_class()
                        
                    current_type = 'ROUTER'
                    current_interface_or_router.name = router_name
                    self.routers[router_name] = current_interface_or_router

                case 'ROUTE':
                    if current_interface_or_router is None or current_type != 'ROUTER':
                        raise parser.error(f"No current router for {keyword}")

                    usage = "ROUTE <Interface Name>"
                    parser.verify_num_parameters(1, 1, usage)
                    interface_name = params[0].upper()
                    interface = self.interfaces.get(interface_name)
                    if interface is None:
                        raise parser.error(f"Unknown interface {interface_name} mapped to router {current_interface_or_router.name}")

                    if interface not in current_interface_or_router.interfaces:
                        current_interface_or_router.interfaces.append(interface)
                        interface.routers.append(current_interface_or_router)

                case _:
                    raise parser.error(f"Unknown keyword: {keyword}")