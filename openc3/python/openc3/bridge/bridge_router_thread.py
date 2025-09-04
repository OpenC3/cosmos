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

from openc3.tools.cmd_tlm_server.interface_thread import InterfaceThread
from openc3.utilities.logger import Logger


class BridgeRouterThread(InterfaceThread):
    def _handle_packet(self, packet):
        for interface in self.interface.interfaces:
            if interface.connected:
                if interface.write_allowed:
                    try:
                        interface.write(packet)
                    except Exception as err:
                        Logger.error(f"Error routing command from {self.interface.name} to interface {interface.name}: {err}")
                else:
                    Logger.warn(f"Interface {interface.name} writing not allowed for packet from {self.interface.name}")
            else:
                Logger.error(f"Attempted to route command from {self.interface.name} to disconnected interface {interface.name}")
