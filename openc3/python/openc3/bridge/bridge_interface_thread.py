# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.tools.cmd_tlm_server.interface_thread import InterfaceThread
from openc3.utilities.logger import Logger


class BridgeInterfaceThread(InterfaceThread):
    def _handle_packet(self, packet):
        for router in self.interface.routers:
            if router.connected:
                if router.write_allowed:
                    try:
                        router.write(packet)
                    except Exception as err:
                        Logger.error(
                            f"Error routing telemetry from {self.interface.name} to router {router.name}: {err}"
                        )
                else:
                    Logger.warn(f"Router {router.name} writing not allowed for packet from {self.interface.name}")
            else:
                Logger.error(
                    f"Attempted to route telemetry from {self.interface.name} to disconnected router {router.name}"
                )
