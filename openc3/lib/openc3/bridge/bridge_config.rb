# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/utilities/logger'
require 'openc3/config/config_parser'

module OpenC3
  class BridgeConfig
    # @return [Hash<String, Interface>] Interfaces hash
    attr_accessor :interfaces
    # @return [Hash<String, Interface>] Routers hash
    attr_accessor :routers

    def initialize(filename, existing_variables = {})
      @interfaces = {}
      @routers = {}
      process_file(filename, existing_variables)
    end

    def self.generate_default(filename)
      default_config = <<~EOF
        # Write serial port name
        VARIABLE write_port_name COM1
        #{'        '}
        # Read serial port name
        VARIABLE read_port_name COM1
        #{'        '}
        # Baud Rate
        VARIABLE baud_rate 115200
        #{'        '}
        # Parity - NONE, ODD, or EVEN
        VARIABLE parity NONE
        #{'        '}
        # Stop bits - 0, 1, or 2
        VARIABLE stop_bits 1
        #{'        '}
        # Write Timeout
        VARIABLE write_timeout 10.0
        #{'        '}
        # Read Timeout
        VARIABLE read_timeout nil
        #{'        '}
        # Flow Control - NONE, or RTSCTS
        VARIABLE flow_control NONE
        #{'        '}
        # Data bits per word - Typically 8
        VARIABLE data_bits 8
        #{'        '}
        # Port to listen for connections from COSMOS - Plugin must match
        VARIABLE router_port 2950
        #{'        '}
        # Port to listen on for connections from COSMOS. Defaults to localhost for security. Will need to be opened
        # if COSMOS is on another machine.
        VARIABLE router_listen_address 127.0.0.1
        #{'        '}
        INTERFACE SERIAL_INT serial_interface.rb <%= write_port_name %> <%= read_port_name %> <%= baud_rate %> <%= parity %> <%= stop_bits %> <%= write_timeout %> <%= read_timeout %>
          OPTION FLOW_CONTROL <%= flow_control %>
          OPTION DATA_BITS <%= data_bits %>
        #{'        '}
        ROUTER SERIAL_ROUTER tcpip_server_interface.rb <%= router_port %> <%= router_port %> 10.0 nil BURST
          ROUTE SERIAL_INT
          OPTION LISTEN_ADDRESS <%= router_listen_address %>
        #{'        '}
      EOF

      Logger.info "Writing #{filename}"
      File.open(filename, 'w') do |file|
        file.write(default_config)
      end
    end

    protected

    # Processes a file and adds in the configuration defined in the file
    #
    # @param filename [String] The name of the configuration file to parse
    def process_file(filename, existing_variables = {})
      current_interface_or_router = nil
      current_type = nil
      current_interface_log_added = false

      Logger.info "Processing Bridge configuration in file: #{File.expand_path(filename)}"

      variables = {}
      parser = ConfigParser.new
      parser.parse_file(filename,
                        false,
                        true,
                        false) do |keyword, params|
        case keyword
        when 'VARIABLE'
          usage = "#{keyword} <Variable Name> <Default Value>"
          parser.verify_num_parameters(2, nil, usage)
          variable_name = params[0]
          value = params[1..-1].join(" ")
          variables[variable_name] = value
          if existing_variables && existing_variables.key?(variable_name)
            variables[variable_name] = existing_variables[variable_name]
          end
          # Ignore everything else during phase 1
        end
      end

      parser = ConfigParser.new
      parser.parse_file(filename, false, true, true, variables) do |keyword, params|
        case keyword

        when 'VARIABLE'
          # Ignore during this pass

        when 'INTERFACE'
          usage = "INTERFACE <Name> <Filename> <Specific Parameters>"
          parser.verify_num_parameters(2, nil, usage)
          interface_name = params[0].upcase
          raise parser.error("Interface '#{interface_name}' defined twice") if @interfaces[interface_name]

          interface_class = OpenC3.require_class(params[1])
          if params[2]
            current_interface_or_router = interface_class.new(*params[2..-1])
          else
            current_interface_or_router = interface_class.new
          end
          current_type = :INTERFACE
          current_interface_or_router.name = interface_name
          current_interface_or_router.config_params = params[1..-1]
          @interfaces[interface_name] = current_interface_or_router

        when 'RECONNECT_DELAY', 'LOG_STREAM', 'LOG_RAW', 'OPTION', 'PROTOCOL'
          raise parser.error("No current interface or router for #{keyword}") unless current_interface_or_router

          case keyword

          when 'RECONNECT_DELAY'
            parser.verify_num_parameters(1, 1, "#{keyword} <Delay in Seconds>")
            current_interface_or_router.reconnect_delay = Float(params[0])

          when 'LOG_STREAM', 'LOG_RAW'
            parser.verify_num_parameters(0, nil, "#{keyword} <Log Stream Class File (optional)> <Log Stream Parameters (optional)>")
            current_interface_or_router.raw_logger_pair = RawLoggerPair.new(current_interface_or_router.name, params)
            current_interface_or_router.start_raw_logging

          when 'OPTION'
            parser.verify_num_parameters(2, nil, "#{keyword} <Option Name> <Option Value 1> <Option Value 2 (optional)> <etc>")
            current_interface_or_router.set_option(params[0], params[1..-1])

          when 'PROTOCOL'
            usage = "#{keyword} <READ WRITE READ_WRITE> <protocol filename or classname> <Protocol specific parameters>"
            parser.verify_num_parameters(2, nil, usage)
            unless %w(READ WRITE READ_WRITE).include? params[0].upcase
              raise parser.error("Invalid protocol type: #{params[0]}", usage)
            end

            begin
              klass = OpenC3.require_class(params[1])
              current_interface_or_router.add_protocol(klass, params[2..-1], params[0].upcase.intern)
            rescue LoadError, StandardError => error
              raise parser.error(error.message, usage)
            end

          end # end case keyword for all keywords that require a current interface or router

        when 'ROUTER'
          usage = "ROUTER <Name> <Filename> <Specific Parameters>"
          parser.verify_num_parameters(2, nil, usage)
          router_name = params[0].upcase
          raise parser.error("Router '#{router_name}' defined twice") if @routers[router_name]

          router_class = OpenC3.require_class(params[1])
          if params[2]
            current_interface_or_router = router_class.new(*params[2..-1])
          else
            current_interface_or_router = router_class.new
          end
          current_type = :ROUTER
          current_interface_or_router.name = router_name
          @routers[router_name] = current_interface_or_router

        when 'ROUTE'
          raise parser.error("No current router for #{keyword}") unless current_interface_or_router and current_type == :ROUTER

          usage = "ROUTE <Interface Name>"
          parser.verify_num_parameters(1, 1, usage)
          interface_name = params[0].upcase
          interface = @interfaces[interface_name]
          raise parser.error("Unknown interface #{interface_name} mapped to router #{current_interface_or_router.name}") unless interface

          unless current_interface_or_router.interfaces.include? interface
            current_interface_or_router.interfaces << interface
            interface.routers << current_interface_or_router
          end

        else
          # blank lines will have a nil keyword and should not raise an exception
          raise parser.error("Unknown keyword: #{keyword}") unless keyword.nil?
        end # case
      end  # loop
    end
  end
end
