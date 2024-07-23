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

require 'openc3/models/target_model'

module OpenC3
  module Api
    WHITELIST ||= []
    WHITELIST.concat([
      'get_target_names',
      'get_target_list', # DEPRECATED
      'get_target',
      'get_target_interfaces',
      'get_all_target_info', # DEPRECATED
    ])

    # Returns the list of all target names
    #
    # @return [Array<String>] All target names
    def get_target_names(scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', scope: scope, token: token)
      TargetModel.names(scope: scope)
    end
    # get_target_list is DEPRECATED
    alias get_target_list get_target_names

    # Gets the full target hash
    #
    # @since 5.0.0
    # @param target_name [String] Target name
    # @return [Hash] Hash of all the target properties
    def get_target(target_name, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', target_name: target_name, scope: scope, token: token)
      TargetModel.get(name: target_name, scope: scope)
    end

    # Get all targets and their interfaces
    #
    # @return [Array<Array<String, String] Array of Arrays \[name, interfaces]
    def get_target_interfaces(scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', scope: scope, token: token)
      info = []
      interfaces = InterfaceModel.all(scope: scope)
      get_target_names(scope: scope, token: token).each do |target_name|
        interface_names = []
        interfaces.each do |name, interface|
          if interface['target_names'].include? target_name
            interface_names << interface['name']
          end
        end
        info << [target_name, interface_names.join(",")]
      end
      info
    end

    # DEPRECATED: Get information about all targets
    # Warning this call can take a long time with many defined packets
    #
    # @return [Array<Array<String, String, Numeric, Numeric>] Array of Arrays \[name, interface, cmd_cnt, tlm_cnt]
    def get_all_target_info(scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', scope: scope, token: token)
      info = []
      get_target_names(scope: scope, token: token).each do |target_name|
        cmd_cnt = 0
        packets = TargetModel.packets(target_name, type: :CMD, scope: scope)
        packets.each do |packet|
          cmd_cnt += Topic.get_cnt("#{scope}__COMMAND__{#{target_name}}__#{packet['packet_name']}")
        end
        tlm_cnt = 0
        packets = TargetModel.packets(target_name, type: :TLM, scope: scope)
        packets.each do |packet|
          tlm_cnt += Topic.get_cnt("#{scope}__TELEMETRY__{#{target_name}}__#{packet['packet_name']}")
        end
        interface_names = []
        InterfaceModel.all(scope: scope).each do |name, interface|
          if interface['target_names'].include? target_name
            interface_names << interface['name']
          end
        end
        info << [target_name, interface_names.join(","), cmd_cnt, tlm_cnt]
      end
      info
    end
  end
end
