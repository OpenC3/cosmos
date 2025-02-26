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

require 'openc3/microservices/interface_microservice'

module OpenC3
  class RouterMicroservice < InterfaceMicroservice
    def handle_packet(packet)
      RouterStatusModel.set(@interface.as_json(:allow_nan => true), scope: @scope)
      if !packet.identified?
        # Need to identify so we can find the target
        identified_packet = System.commands.identify(packet.buffer(false), @interface.cmd_target_names)
        packet = identified_packet if identified_packet
      end

      unless packet.defined?
        if packet.target_name and packet.packet_name
          begin
            defined_packet = System.commands.packet(packet.target_name, packet.packet_name)
            defined_packet.received_time = packet.received_time
            defined_packet.stored = packet.stored
            defined_packet.buffer = packet.buffer
            packet = defined_packet
          rescue => err
            @logger.warn "Error defining packet of #{packet.length} bytes"
          end
        end
      end

      target_name = packet.target_name
      target_name = 'UNKNOWN' unless target_name
      target = System.targets[target_name]

      begin
        begin
          log_message = true # Default is true
          # If the packet has the DISABLE_MESSAGES keyword then no messages by default
          log_message = false if packet.messages_disabled
          # Check if any of the parameters have DISABLE_MESSAGES
          packet.sorted_items.each do |item|
            if item.states and item.messages_disabled
              value = packet.read_item(item)
              if item.messages_disabled[value]
                log_message = false
                break
              end
            end
          end

          if log_message
            if target and target_name != 'UNKNOWN'
              @logger.info System.commands.format(packet, target.ignored_parameters)
            else
              @logger.warn "Unidentified packet of #{packet.length} bytes being routed to target #{@interface.cmd_target_names[0]}"
            end
          end
        rescue => err
          @logger.error "Problem formatting command from router:\n#{err.formatted}"
        end

        RouterTopic.route_command(packet, @interface.cmd_target_names, scope: @scope)
      rescue Exception => err
        @error = err
        @logger.error "Error routing command from #{@interface.name}\n#{err.formatted}"
      end
    end
  end
end

if __FILE__ == $0
  OpenC3::RouterMicroservice.run
  ThreadManager.instance.shutdown
  ThreadManager.instance.join
end