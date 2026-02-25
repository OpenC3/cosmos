# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/tools/cmd_tlm_server/interface_thread'

module OpenC3
  class BridgeRouterThread < InterfaceThread
    protected

    def handle_packet(packet)
      @interface.interfaces.each do |interface|
        if interface.connected?
          if interface.write_allowed?
            begin
              interface.write(packet)
            rescue Exception => err
              Logger.error "Error routing command from #{@interface.name} to interface #{interface.name}\n#{err.formatted}"
            end
          end
        else
          Logger.error "Attempted to route command from #{@interface.name} to disconnected interface #{interface.name}"
        end
      end
    end
  end # class BridgeRouterThread
end
