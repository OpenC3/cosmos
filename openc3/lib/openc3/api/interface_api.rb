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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/interface_model'
require 'openc3/models/interface_status_model'
require 'openc3/topics/interface_topic'

module OpenC3
  module Api
    WHITELIST ||= []
    WHITELIST.concat([
                       'get_interface',
                       'get_interface_names',
                       'connect_interface',
                       'disconnect_interface',
                       'start_raw_logging_interface',
                       'stop_raw_logging_interface',
                       'get_all_interface_info',
                       'map_target_to_interface',
                       'unmap_target_from_interface',
                       'interface_cmd',
                       'interface_protocol_cmd',
                       'interface_target_enable',
                       'interface_target_disable',
                       'interface_details'
                     ])

    # Get information about an interface
    #
    # @since 5.0.0
    # @param interface_name [String] Interface name
    # @return [Hash] Hash of all the interface information
    def get_interface(interface_name, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', interface_name: interface_name, manual: manual, scope: scope, token: token)
      interface = InterfaceModel.get(name: interface_name, scope: scope)
      raise "Interface '#{interface_name}' does not exist" unless interface

      interface.merge(InterfaceStatusModel.get(name: interface_name, scope: scope))
    end

    # @return [Array<String>] All the interface names
    def get_interface_names(manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', manual: manual, scope: scope, token: token)
      InterfaceModel.names(scope: scope)
    end

    # Connects an interface and starts its telemetry gathering thread
    #
    # @param interface_name [String] The name of the interface
    # @param interface_params [Array] Optional parameters to pass to the interface
    def connect_interface(interface_name, *interface_params, manual: false, scope: $openc3_scope, token: $openc3_token)
      # TODO: Check if they have command authority for the targets mapped to this interface
      authorize(permission: 'system_set', interface_name: interface_name, manual: manual, scope: scope, token: token)
      InterfaceTopic.connect_interface(interface_name, *interface_params, scope: scope)
    end

    # Disconnects from an interface and kills its telemetry gathering thread
    #
    # @param interface_name [String] The name of the interface
    def disconnect_interface(interface_name, manual: false, scope: $openc3_scope, token: $openc3_token)
      # TODO: Check if they have command authority for the targets mapped to this interface
      authorize(permission: 'system_set', interface_name: interface_name, manual: manual, scope: scope, token: token)
      InterfaceTopic.disconnect_interface(interface_name, scope: scope)
    end

    # Starts raw logging for an interface
    #
    # @param interface_name [String] The name of the interface
    def start_raw_logging_interface(interface_name = 'ALL', manual: false, scope: $openc3_scope, token: $openc3_token)
      # TODO: Check if they have command authority for the targets mapped to this interface
      authorize(permission: 'system_set', interface_name: interface_name, manual: manual, scope: scope, token: token)
      if interface_name == 'ALL'
        get_interface_names().each do |interface_name|
          InterfaceTopic.start_raw_logging(interface_name, scope: scope)
        end
      else
        InterfaceTopic.start_raw_logging(interface_name, scope: scope)
      end
    end

    # Stop raw logging for an interface
    #
    # @param interface_name [String] The name of the interface
    def stop_raw_logging_interface(interface_name = 'ALL', manual: false, scope: $openc3_scope, token: $openc3_token)
      # TODO: Check if they have command authority for the targets mapped to this interface
      authorize(permission: 'system_set', interface_name: interface_name, manual: manual, scope: scope, token: token)
      if interface_name == 'ALL'
        get_interface_names().each do |interface_name|
          InterfaceTopic.stop_raw_logging(interface_name, scope: scope)
        end
      else
        InterfaceTopic.stop_raw_logging(interface_name, scope: scope)
      end
    end

    # Get information about all interfaces
    #
    # @return [Array<Array<String, Numeric, Numeric, Numeric, Numeric, Numeric,
    #   Numeric, Numeric, Boolean>>] Array of Arrays containing \[name, state, num clients,
    #   TX queue size, RX queue size, TX bytes, RX bytes, Command count,
    #   Telemetry count, disable_disconnect] for all interfaces
    def get_all_interface_info(manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', manual: manual, scope: scope, token: token)
      info = []
      InterfaceStatusModel.all(scope: scope).each do |int_name, int|
        # Get the interface configuration to access disable_disconnect
        interface_model = InterfaceModel.get(name: int_name, scope: scope)
        disable_disconnect = interface_model && interface_model['disable_disconnect'] ? true : false

        info << [int['name'], int['state'], int['clients'], int['txsize'], int['rxsize'],
                 int['txbytes'], int['rxbytes'], int['txcnt'], int['rxcnt'], disable_disconnect]
      end
      info.sort! { |a, b| a[0] <=> b[0] }
      info
    end

    # Associates a target and all its commands and telemetry with a particular
    # interface. All the commands will go out over and telemetry be received
    # from that interface.
    #
    # @param target_name [String/Array] The name of the target(s)
    # @param interface_name (see #connect_interface)
    def map_target_to_interface(target_name, interface_name, cmd_only: false, tlm_only: false, unmap_old: true, manual: false, scope: $openc3_scope, token: $openc3_token)
      # TODO: Check if they have command authority for the targets mapped to this interface
      authorize(permission: 'system_set', interface_name: interface_name, manual: manual, scope: scope, token: token)
      interface = InterfaceModel.get_model(name: interface_name, scope: scope)
      if Array === target_name
        target_names = target_name
      else
        target_names = [target_name]
      end
      target_names.each do |name|
        interface.map_target(name, cmd_only: cmd_only, tlm_only: tlm_only, unmap_old: unmap_old)
        Logger.info("Target #{name} mapped to Interface #{interface_name}", scope: scope)
      end
      nil
    end

    # Removes association of a target and all its commands and telemetry with a particular
    # interface. No commands will go out over and no telemetry be received
    # from that interface for the target.
    #
    # @param target_name [String/Array] The name of the target(s)
    # @param interface_name (see #connect_interface)
    def unmap_target_from_interface(target_name, interface_name, cmd_only: false, tlm_only: false, manual: false, scope: $openc3_scope, token: $openc3_token)
      # TODO: Check if they have command authority for the targets mapped to this interface
      authorize(permission: 'system_set', interface_name: interface_name, manual: manual, scope: scope, token: token)
      interface = InterfaceModel.get_model(name: interface_name, scope: scope)
      if Array === target_name
        target_names = target_name
      else
        target_names = [target_name]
      end
      target_names.each do |name|
        interface.unmap_target(name, cmd_only: cmd_only, tlm_only: tlm_only)
        Logger.info("Target #{name} unmapped from Interface #{interface_name}", scope: scope)
      end
      nil
    end

    def interface_cmd(interface_name, cmd_name, *cmd_params, manual: false, scope: $openc3_scope, token: $openc3_token)
      # TODO: Check if they have command authority for the targets mapped to this interface
      authorize(permission: 'system_set', interface_name: interface_name, manual: manual, scope: scope, token: token)
      InterfaceTopic.interface_cmd(interface_name, cmd_name, *cmd_params, scope: scope)
    end

    def interface_protocol_cmd(interface_name, cmd_name, *cmd_params, read_write: :READ_WRITE, index: -1, manual: false, scope: $openc3_scope, token: $openc3_token)
      # TODO: Check if they have command authority for the targets mapped to this interface
      authorize(permission: 'system_set', interface_name: interface_name, manual: manual, scope: scope, token: token)
      InterfaceTopic.protocol_cmd(interface_name, cmd_name, *cmd_params, read_write: read_write, index: index, scope: scope)
    end

    def interface_target_enable(interface_name, target_name, cmd_only: false, tlm_only: false, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system_set', interface_name: interface_name, manual: manual, scope: scope, token: token)
      interface = InterfaceModel.get_model(name: interface_name, scope: scope)
      if cmd_only and tlm_only
        cmd_only = false
        tlm_only = false
      end
      if not tlm_only
        interface.cmd_target_enabled[target_name.upcase] = true
      end
      if not cmd_only
        interface.tlm_target_enabled[target_name.upcase] = true
      end
      interface.update
      InterfaceTopic.interface_target_enable(interface_name, target_name, cmd_only: cmd_only, tlm_only: tlm_only, scope: scope)
    end

    def interface_target_disable(interface_name, target_name, cmd_only: false, tlm_only: false, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system_set', interface_name: interface_name, manual: manual, scope: scope, token: token)
      interface = InterfaceModel.get_model(name: interface_name, scope: scope)
      if cmd_only and tlm_only
        cmd_only = false
        tlm_only = false
      end
      if not tlm_only
        interface.cmd_target_enabled[target_name.upcase] = false
      end
      if not cmd_only
        interface.tlm_target_enabled[target_name.upcase] = false
      end
      interface.update
      InterfaceTopic.interface_target_disable(interface_name, target_name, cmd_only: cmd_only, tlm_only: tlm_only, scope: scope)
    end

    def interface_details(interface_name, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', interface_name: interface_name, manual: manual, scope: scope, token: token)
      InterfaceTopic.interface_details(interface_name, scope: scope)
    end
  end
end
