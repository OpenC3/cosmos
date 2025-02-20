# Copyright 2023 OpenC3, Inc.
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

import os
import sys
from openc3.microservices.interface_microservice import InterfaceMicroservice
from openc3.system.system import System
from openc3.models.router_status_model import RouterStatusModel
from openc3.topics.router_topic import RouterTopic
from openc3.utilities.thread_manager import ThreadManager

class RouterMicroservice(InterfaceMicroservice):
    def handle_packet(self, packet):
        RouterStatusModel.set(self.interface.as_json(), scope=self.scope)
        if not packet.identified():
            # Need to identify so we can find the target
            identified_packet = System.commands.identify(packet.buffer_no_copy(), self.interface.cmd_target_names)
            if identified_packet:
                packet = identified_packet

        if not packet.defined():
            if packet.target_name and packet.packet_name:
                try:
                    defined_packet = System.commands.packet(packet.target_name, packet.packet_name)
                    defined_packet.received_time = packet.received_time
                    defined_packet.stored = packet.stored
                    defined_packet.buffer = packet.buffer
                    packet = defined_packet
                except RuntimeError:
                    self.logger.warn(f"Error defining packet of {len(packet)} bytes")

        target_name = packet.target_name
        if not target_name:
            target_name = "UNKNOWN"
        target = System.targets.get(target_name)

        try:
            try:
                log_message = True  # Default is True
                # If the packet has the DISABLE_MESSAGES keyword then no messages by default
                if packet.messages_disabled:
                    log_message = False
                # Check if any of the parameters have DISABLE_MESSAGES
                for item in packet.sorted_items:
                    if item.states and item.messages_disabled:
                        value = packet.read_item(item)
                        if item.messages_disabled[value]:
                            log_message = False
                            break

                if log_message:
                    if target and target_name != "UNKNOWN":
                        self.logger.info(System.commands.format(packet, target.ignored_parameters))
                    else:
                        self.logger.warn(
                            f"Unidentified packet of {len(packet.buffer_no_copy())} bytes being routed to target {self.interface.cmd_target_names[0]}"
                        )
            except RuntimeError as error:
                self.logger.error(f"Problem formatting command from router=\n{repr(error)}")

            RouterTopic.route_command(packet, self.interface.cmd_target_names, scope=self.scope)
        except RuntimeError as error:
            self.error = error
            self.logger.error(f"Error routing command from {self.interface.name}\n{repr(error)}")


if os.path.basename(__file__) == os.path.basename(sys.argv[0]):
    RouterMicroservice.class_run()
    ThreadManager.instance().shutdown()
    ThreadManager.instance().join()