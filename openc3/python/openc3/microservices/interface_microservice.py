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
import re
import sys
import time
import json
import threading
from datetime import datetime, timezone
from openc3.microservices.microservice import Microservice
from openc3.microservices.interface_decom_common import handle_inject_tlm
from openc3.system.system import System
from openc3.models.interface_model import InterfaceModel
from openc3.models.interface_status_model import InterfaceStatusModel
from openc3.models.router_model import RouterModel
from openc3.models.router_status_model import RouterStatusModel
from openc3.models.cvt_model import CvtModel
from openc3.topics.topic import Topic
from openc3.topics.interface_topic import InterfaceTopic
from openc3.topics.router_topic import RouterTopic
from openc3.topics.command_topic import CommandTopic
from openc3.topics.command_decom_topic import CommandDecomTopic
from openc3.topics.telemetry_topic import TelemetryTopic
from openc3.config.config_parser import ConfigParser
from openc3.interfaces.interface import WriteRejectError
from openc3.utilities.logger import Logger
from openc3.utilities.sleeper import Sleeper
from openc3.utilities.time import from_nsec_from_epoch
from openc3.utilities.json import JsonDecoder
from openc3.top_level import kill_thread


class InterfaceCmdHandlerThread:
    def __init__(self, interface, tlm, logger=None, metric=None, scope=None):
        self.interface = interface
        self.tlm = tlm
        self.scope = scope
        self.logger = logger
        if not self.logger:
            self.logger = Logger()
        self.metric = metric
        self.count = 0
        self.directive_count = 0
        if self.metric is not None:
            self.metric.set(
                name="interface_directive_total",
                value=self.directive_count,
                type="counter",
            )
            self.metric.set(
                name="interface_cmd_total", value=self.count, type="counter"
            )

    def start(self):
        self.thread = threading.Thread(target=self.run)
        self.thread.start()
        return self.thread

    def stop(self):
        kill_thread(self, self.thread)

    def graceful_kill(self):
        InterfaceTopic.shutdown(self.interface, scope=self.scope)

    def run(self):
        # receive_commands does a while True and does not return
        InterfaceTopic.receive_commands(self.process_cmd, self.interface, self.scope)

    def process_cmd(self, topic, msg_id, msg_hash, redis):
        # OpenC3.with_context(msg_hash) do
        if msg_hash.get(b"shutdown"):
            return "Shutdown"

        msgid_seconds_from_epoch = int(msg_id.split("-")[0]) / 1000.0
        delta = time.time() - msgid_seconds_from_epoch
        if self.metric is not None:
            self.metric.set(
                name="interface_topic_delta_seconds",
                value=delta,
                type="gauge",
                unit="seconds",
                help="Delta time between data written to stream and interface cmd start",
            )

        # Check for a raw write to the interface
        if re.match(r"CMD}INTERFACE", topic):
            self.directive_count += 1
            if self.metric is not None:
                self.metric.set(
                    name="interface_directive_total",
                    value=self.directive_count,
                    type="counter",
                )
            if msg_hash[b"shutdown"]:
                self.logger.info(f"{self.interface.name}: Shutdown requested")
                return "SHUTDOWN"
            if msg_hash[b"connect"]:
                self.logger.info(f"{self.interface.name}: Connect requested")
                params = []
                if msg_hash[b"params"]:
                    params = json.loads(msg_hash[b"params"])
                self.interface = self.tlm.attempting(*params)
                return "SUCCESS"
            if msg_hash[b"disconnect"]:
                self.logger.info(f"{self.interface.name}: Disconnect requested")
                self.tlm.disconnect(False)
                return "SUCCESS"
            if msg_hash[b"raw"]:
                if self.interface.connected():
                    self.logger.info(f"{self.interface.name}: Write raw")
                    # A raw interface write results in an UNKNOWN packet
                    command = System.commands.packet("UNKNOWN", "UNKNOWN")
                    command.received_count += 1
                    command = command.clone
                    command.buffer = msg_hash[b"raw"]
                    command.received_time = datetime.now(timezone.utc)
                    CommandTopic.write_packet(command, scope=self.scope)
                    self.interface.write_raw(msg_hash[b"raw"])
                    return "SUCCESS"
                else:
                    return f"Interface not connected: {self.interface.name}"
            if msg_hash.key(b"log_stream"):
                if msg_hash[b"log_stream"].decode() == "True":
                    self.logger.info(f"{self.interface.name}: Enable stream logging")
                    self.interface.start_raw_logging
                else:
                    self.logger.info(f"{self.interface.name}: Disable stream logging")
                    self.interface.stop_raw_logging
                return "SUCCESS"
            if msg_hash.key(b"interface_cmd"):
                params = json.loads(
                    msg_hash[b"interface_cmd"], allow_nan=True, create_additions=True
                )
                try:
                    self.logger.info(
                        f"{self.interface.name}: interface_cmd= {params['cmd_name']} {' '.join(params['cmd_params'])}"
                    )
                    self.interface.interface_cmd(
                        params["cmd_name"], *params["cmd_params"]
                    )
                except RuntimeError as error:
                    self.logger.error(
                        f"{self.interface.name}: interface_cmd: {repr(error)}"
                    )
                    return error.message
                return "SUCCESS"
            if msg_hash.key(b"protocol_cmd"):
                params = json.loads(
                    msg_hash[b"protocol_cmd"], allow_nan=True, create_additions=True
                )
                try:
                    self.logger.info(
                        f"{self.interface.name}: protocol_cmd: {params['cmd_name']} {' '.join(params['cmd_params'])} read_write: {params['read_write']} index: {params['index']}"
                    )
                    self.interface.protocol_cmd(
                        params["cmd_name"],
                        *params["cmd_params"],
                        read_write=params["read_write"],
                        index=params["index"],
                    )
                except RuntimeError as error:
                    self.logger.error(
                        f"{self.interface.name}: protocol_cmd:{repr(error)}"
                    )
                    return error.message
                return "SUCCESS"
            if msg_hash.key(b"inject_tlm"):
                handle_inject_tlm(msg_hash[b"inject_tlm"], self.scope)
                return "SUCCESS"

        target_name = msg_hash[b"target_name"].decode()
        cmd_name = msg_hash[b"cmd_name"].decode()
        cmd_params = None
        cmd_buffer = None
        hazardous_check = None
        if msg_hash[b"cmd_params"] is not None:
            cmd_params = json.loads(msg_hash[b"cmd_params"], cls=JsonDecoder)
            range_check = ConfigParser.handle_true_false(
                msg_hash[b"range_check"].decode()
            )
            raw = ConfigParser.handle_true_false(msg_hash[b"raw"].decode())
            hazardous_check = ConfigParser.handle_true_false(
                msg_hash[b"hazardous_check"].decode()
            )
        elif msg_hash[b"cmd_buffer"] is not None:
            cmd_buffer = msg_hash[b"cmd_buffer"]

        try:
            try:
                if cmd_params is not None:
                    command = System.commands.build_cmd(
                        target_name, cmd_name, cmd_params, range_check, raw
                    )
                elif cmd_buffer is not None:
                    if target_name:
                        command = System.commands.identify(cmd_buffer, [target_name])
                    else:
                        command = System.commands.identify(
                            cmd_buffer, self.interface.cmd_target_names
                        )
                    if not command:
                        command = System.commands.packet("UNKNOWN", "UNKNOWN")
                        command.received_count += 1
                        command = command.clone()
                        command.buffer = cmd_buffer
                else:
                    raise RuntimeError(f"Invalid command received:\n{msg_hash}")
                command.received_time = datetime.now(timezone.utc)
            except RuntimeError as error:
                self.logger.error(f"{self.interface.name}: {msg_hash}")
                self.logger.error(f"{self.interface.name}: {repr(error)}")
                return repr(error)

            if hazardous_check:
                hazardous, hazardous_description = System.commands.cmd_pkt_hazardous(
                    command
                )
                # Return back the error, description, and the formatted command
                # This allows the error handler to simply re-send the command
                if hazardous:
                    return f"HazardousError\n{hazardous_description}\n{System.commands.format(command)}"

            try:
                if self.interface.connected():
                    self.count += 1
                    if self.metric is not None:
                        self.metric.set(
                            name="interface_cmd_total", value=self.count, type="counter"
                        )

                    self.interface.write(command)
                    CommandTopic.write_packet(command, scope=self.scope)
                    CommandDecomTopic.write_packet(command, scope=self.scope)
                    InterfaceStatusModel.set(self.interface.as_json(), scope=self.scope)
                    return "SUCCESS"
                else:
                    return f"Interface not connected: {self.interface.name}"
            except WriteRejectError as error:
                return error.message
        except RuntimeError as error:
            self.logger.error(f"{self.interface.name}: {repr(error)}")
            return repr(error)


class RouterTlmHandlerThread:
    def __init__(self, router, tlm, logger=None, metric=None, scope=None):
        self.router = router
        self.tlm = tlm
        self.scope = scope
        self.logger = logger
        if not self.logger:
            self.logger = Logger
        self.metric = metric
        self.count = 0
        self.directive_count = 0
        if self.metric is not None:
            self.metric.set(
                name="router_directive_total",
                value=self.directive_count,
                type="counter",
            )
        if self.metric is not None:
            self.metric.set(name="router_tlm_total", value=self.count, type="counter")

    def start(self):
        self.thread = threading.Thread(target=self.run)
        self.thread.start()
        return self.thread

    def stop(self):
        kill_thread(self, self.thread)

    def graceful_kill(self):
        RouterTopic.shutdown(self.router, scope=self.scope)

    def run(self):
        for topic, msg_id, msg_hash, redis in RouterTopic.receive_telemetry(
            self.router, scope=self.scope
        ):
            msgid_seconds_from_epoch = int(msg_id.split("-")[0]) / 1000.0
            delta = time.time() - msgid_seconds_from_epoch
            if self.metric is not None:
                self.metric.set(
                    name="router_topic_delta_seconds",
                    value=delta,
                    type="gauge",
                    unit="seconds",
                    help="Delta time between data written to stream and router tlm start",
                )

            # Check for commands to the router itself
            if re.match(r"CMD}ROUTER", topic):
                self.directive_count += 1
                if self.metric is not None:
                    self.metric.set(
                        name="router_directive_total",
                        value=self.directive_count,
                        type="counter",
                    )

                if msg_hash[b"shutdown"]:
                    self.logger.info(f"{self.router.name}: Shutdown requested")
                    return
                if msg_hash[b"connect"]:
                    self.logger.info(f"{self.router.name}: Connect requested")
                    params = []
                    if msg_hash[b"params"]:
                        params = json.loads(msg_hash[b"params"])
                    self.router = self.tlm.attempting(*params)
                if msg_hash[b"disconnect"]:
                    self.logger.info(f"{self.router.name}: Disconnect requested")
                    self.tlm.disconnect(False)
                if msg_hash.key(b"log_stream"):
                    if msg_hash[b"log_stream"].decode() == "True":
                        self.logger.info(f"{self.router.name}: Enable stream logging")
                        self.router.start_raw_logging
                    else:
                        self.logger.info(f"{self.router.name}: Disable stream logging")
                        self.router.stop_raw_logging
                if msg_hash.key(b"router_cmd"):
                    params = json.loads(
                        msg_hash[b"router_cmd"], allow_nan=True, create_additions=True
                    )
                    try:
                        self.logger.info(
                            f"{self.router.name}: router_cmd: {params['cmd_name']} {' '.join(params['cmd_params'])}"
                        )
                        self.router.interface_cmd(
                            params["cmd_name"], *params["cmd_params"]
                        )
                    except RuntimeError as error:
                        self.logger.error(
                            f"{self.router.name}: router_cmd: {repr(error)}"
                        )
                        return error.message
                    return "SUCCESS"
                if msg_hash.key(b"protocol_cmd"):
                    params = json.loads(
                        msg_hash[b"protocol_cmd"], allow_nan=True, create_additions=True
                    )
                    try:
                        self.logger.info(
                            f"{self.router.name}: protocol_cmd: {params['cmd_name']} {' '.join(params['cmd_params'])} read_write: {params['read_write']} index: {params['index']}"
                        )
                        self.router.protocol_cmd(
                            params["cmd_name"],
                            *params["cmd_params"],
                            read_write=params["read_write"],
                            index=params["index"],
                        )
                    except RuntimeError as error:
                        self.logger.error(
                            f"{self.router.name}: protoco_cmd: {repr(error)}"
                        )
                        return error.message
                    return "SUCCESS"
                return "SUCCESS"

            if self.router.connected():
                self.count += 1
                if self.metric is not None:
                    self.metric.set(
                        name="router_tlm_total", value=self.count, type="counter"
                    )

                target_name = msg_hash[b"target_name"].decode()
                packet_name = msg_hash[b"packet_name"].decode()

                packet = System.telemetry.packet(target_name, packet_name)
                packet.stored = ConfigParser.handle_true_false(
                    msg_hash[b"stored"].decode()
                )
                packet.received_time = from_nsec_from_epoch(int(msg_hash[b"time"]))
                packet.received_count = int(msg_hash[b"received_count"])
                packet.buffer = msg_hash[b"buffer"]

                try:
                    self.router.write(packet)
                    RouterStatusModel.set(self.router.as_json(), scope=self.scope)
                    return "SUCCESS"
                except RuntimeError as error:
                    self.logger.error(f"{self.router.name}: {repr(error)}")
                    return error.message


class InterfaceMicroservice(Microservice):
    UNKNOWN_BYTES_TO_PRINT = 16

    def __init__(self, name):
        self.mutex = threading.Lock()
        super().__init__(name)
        self.interface_or_router = self.__class__.__name__.split("Microservice")[
            0
        ].upper()
        if self.interface_or_router == "INTERFACE":
            self.metric.set(
                name="interface_tlm_total", value=self.count, type="counter"
            )
        else:
            self.metric.set(name="router_cmd_total", value=self.count, type="counter")

        self.scope = name.split("__")[0]
        interface_name = name.split("__")[2]
        if self.interface_or_router == "INTERFACE":
            self.interface = InterfaceModel.get_model(
                name=interface_name, scope=self.scope
            ).build()
        else:
            self.interface = RouterModel.get_model(
                name=interface_name, scope=self.scope
            ).build()
        self.interface.name = interface_name
        # Map the interface to the interface's targets
        for target_name in self.interface.target_names:
            target = System.targets[target_name]
            target.interface = self.interface
        for target_name in self.interface.tlm_target_names:
            # Initialize the target's packet counters based on the Topic stream
            # Prevents packet count resetting to 0 when interface restarts
            try:
                for packet_name, packet in System.telemetry.packets(
                    target_name
                ).items():
                    topic = f"{self.scope}__TELEMETRY__{{target_name}}__{packet_name}"
                    msg_id, msg_hash = Topic.get_newest_message(topic)
                    if msg_id:
                        packet.received_count = int(msg_hash[b"received_count"])
                    else:
                        packet.received_count = 0
            except RuntimeError:
                pass  # Handle targets without telemetry
        if self.interface.connect_on_startup:
            self.interface.state = "ATTEMPTING"
        else:
            self.interface.state = "DISCONNECTED"
        if self.interface_or_router == "INTERFACE":
            InterfaceStatusModel.set(self.interface.as_json(), scope=self.scope)
        else:
            RouterStatusModel.set(self.interface.as_json(), scope=self.scope)

        self.interface_thread_sleeper = Sleeper()
        self.cancel_thread = False
        self.connection_failed_messages = []
        self.connection_lost_messages = []
        if self.interface_or_router == "INTERFACE":
            self.handler_thread = InterfaceCmdHandlerThread(
                self.interface,
                self,
                logger=self.logger,
                metric=self.metric,
                scope=self.scope,
            )
        else:
            self.handler_thread = RouterTlmHandlerThread(
                self.interface,
                self,
                logger=self.logger,
                metric=self.metric,
                scope=self.scope,
            )
        self.handler_thread.start()

    # Called to connect the interface/router. It takes optional parameters to
    # rebuilt the interface/router. Once we set the state to 'ATTEMPTING' the
    # run method handles the actual connection.
    def attempting(self, *params):
        try:
            if len(params) != 0:
                self.interface.disconnect()
                # Build New Interface, this can fail if passed bad parameters
                new_interface = self.interface.__class__.__name__(*params)
                self.interface.copy_to(new_interface)

                # Replace interface for targets
                for target_name in self.interface.target_names:
                    target = System.targets[target_name]
                    target.interface = new_interface
                self.interface = new_interface

            self.interface.state = "ATTEMPTING"
            if self.interface_or_router == "INTERFACE":
                InterfaceStatusModel.set(self.interface.as_json(), scope=self.scope)
            else:
                RouterStatusModel.set(self.interface.as_json(), scope=self.scope)
            return (
                self.interface
            )  # Return the interface/router since we may have recreated it
        # Need to rescue Exception so we cover LoadError
        except RuntimeError as error:
            self.logger.error(
                f"Attempting connection failed with params {params} due to {error.message}"
            )
            # if SignalException === error:
            #   self.logger.info(f"{self.interface.name}: Closing from signal")
            #   self.cancel_thread = True
            return (
                self.interface
            )  # Return the original interface/router in match of error:

    def run(self):
        try:
            if self.interface.read_allowed:
                self.logger.info(f"{self.interface.name}: Starting packet reading")
            else:
                self.logger.info(
                    f"{self.interface.name}: Starting connection maintenance"
                )
            while True:
                if self.cancel_thread:
                    break

                match self.interface.state:
                    case "DISCONNECTED":
                        # Just wait to see if we should connect later
                        self.interface_thread_sleeper.sleep(1)
                    case "ATTEMPTING":
                        try:
                            with self.mutex:
                                # We need to make sure connect is not called after stop() has been called
                                if not self.cancel_thread:
                                    self.connect()
                        except (RuntimeError, OSError) as error:
                            self.handle_connection_failed(error)
                            if self.cancel_thread:
                                break
                    case "CONNECTED":
                        if self.interface.read_allowed:
                            try:
                                packet = self.interface.read()
                                if packet:
                                    self.handle_packet(packet)
                                    self.count += 1
                                    if self.interface_or_router == "INTERFACE":
                                        self.metric.set(
                                            name="interface_tlm_total",
                                            value=self.count,
                                            type="counter",
                                        )
                                    else:
                                        self.metric.set(
                                            name="router_cmd_total",
                                            value=self.count,
                                            type="counter",
                                        )
                                else:
                                    self.logger.info(
                                        f"{self.interface.name}: Internal disconnect requested (returned None)"
                                    )
                                    self.handle_connection_lost()
                                    if self.cancel_thread:
                                        break
                            except RuntimeError as error:
                                self.handle_connection_lost(error)
                                if self.cancel_thread:
                                    break
                    case _:
                        self.interface_thread_sleeper.sleep(1)
                        if self.interface.connected() is False:
                            self.handle_connection_lost()
        except RuntimeError as error:
            if type(error) != SystemExit:  # or signal exception
                self.logger.error(
                    f"{self.interface.name}: Packet reading thread died: {repr(error)}"
                )
                # handle_fatal_exception(error)
            # Try to do clean disconnect because we're going down
            self.disconnect(False)
        if self.interface_or_router == "INTERFACE":
            InterfaceStatusModel.set(self.interface.as_json(), scope=self.scope)
        else:
            RouterStatusModel.set(self.interface.as_json(), scope=self.scope)
        self.logger.info(f"{self.interface.name}: Stopped packet reading")

    def handle_packet(self, packet):
        InterfaceStatusModel.set(self.interface.as_json(), scope=self.scope)
        if packet.received_time is None:
            packet.received_time = datetime.now(timezone.utc)

        if packet.stored:
            # Stored telemetry does not update the current value table
            identified_packet = System.telemetry.identify_and_define_packet(
                packet, self.interface.tlm_target_names
            )
        else:
            # Identify and update packet
            if packet.identified():
                try:
                    # Preidentifed packet - place it into the current value table
                    identified_packet = System.telemetry.update(
                        packet.target_name, packet.packet_name, packet.buffer
                    )
                except RuntimeError:
                    # Packet identified but we don't know about it
                    # Clear packet_name and target_name and try to identify
                    self.logger.warn(
                        f"{self.interface.name}: Received unknown identified telemetry: {packet.target_name} {packet.packet_name}"
                    )
                    packet.target_name = None
                    packet.packet_name = None
                    identified_packet = System.telemetry.identify(
                        packet.buffer, self.interface.tlm_target_names
                    )
            else:
                # Packet needs to be identified
                identified_packet = System.telemetry.identify(
                    packet.buffer, self.interface.tlm_target_names
                )

        if identified_packet:
            identified_packet.received_time = packet.received_time
            identified_packet.stored = packet.stored
            identified_packet.extra = packet.extra
            packet = identified_packet
        else:
            unknown_packet = System.telemetry.update(
                "UNKNOWN", "UNKNOWN", packet.buffer
            )
            unknown_packet.received_time = packet.received_time
            unknown_packet.stored = packet.stored
            unknown_packet.extra = packet.extra
            packet = unknown_packet
            json_hash = CvtModel.build_json_from_packet(packet)
            CvtModel.set(
                json_hash,
                target_name=packet.target_name,
                packet_name=packet.packet_name,
                scope=self.scope,
            )
            num_bytes_to_print = min(
                InterfaceMicroservice.UNKNOWN_BYTES_TO_PRINT, len(packet.buffer)
            )
            data = packet.buffer_no_copy()[0:(num_bytes_to_print)]
            prefix = "".join([format(x, "02x") for x in data])
            self.logger.warn(
                f"{self.interface.name} {packet.target_name} packet length: {len(packet.buffer)} starting with: {prefix}"
            )

        # Write to stream
        packet.received_count += 1
        TelemetryTopic.write_packet(packet, self.scope)

    def handle_connection_failed(self, connect_error):
        self.error = connect_error
        self.logger.error(
            f"{self.interface.name}: Connection Failed: {repr(connect_error)}"
        )
        # match connect_error:
        #   case OSError:
        #     self.logger.info(f"{self.interface.name}: Closing from signal")
        #     self.cancel_thread = True
        # case Errno='ECONNREFUSED', Errno='ECONNRESET', Errno='ETIMEDOUT', Errno='ENOTSOCK', Errno='EHOSTUNREACH', IOError:
        #   # Do not write an exception file for these extremely common cases
        # else _:
        if connect_error is RuntimeError and (
            "canceled" in connect_error.message or "timeout" in connect_error.message
        ):
            pass  # Do not write an exception file for these extremely common cases
        else:
            self.logger.error(f"{self.interface.name}: {str(connect_error)}")
            if str(connect_error) not in self.connection_failed_messages:
                # OpenC3.write_exception_file(connect_error)
                self.connection_failed_messages.append(str(connect_error))
        self.disconnect()  # Ensure we do a clean disconnect

    def handle_connection_lost(self, error=None, reconnect=True):
        if error:
            self.error = error
            self.logger.info(f"{self.interface.name}: Connection Lost: {repr(error)}")
            # match err:
            #   case SignalException:
            #     self.logger.info(f"{self.interface.name}: Closing from signal")
            #     self.cancel_thread = True
            #   # case Errno='ECONNABORTED', Errno='ECONNRESET', Errno='ETIMEDOUT', Errno='EBADF', Errno='ENOTSOCK', IOError:
            #     # Do not write an exception file for these extremely common cases
            #   else _:
            self.logger.error(f"{self.interface.name}: {str(error)}")
            if str(error) not in self.connection_lost_messages:
                # OpenC3.write_exception_file(err)
                self.connection_lost_messages.append(str(error))
        else:
            self.logger.info(f"{self.interface.name}: Connection Lost")
        self.disconnect(reconnect)  # Ensure we do a clean disconnect

    def connect(self):
        self.logger.info(f"{self.interface.name}: Connecting :")
        self.interface.connect()
        self.interface.state = "CONNECTED"
        if self.interface_or_router == "INTERFACE":
            InterfaceStatusModel.set(self.interface.as_json(), scope=self.scope)
        else:
            RouterStatusModel.set(self.interface.as_json(), scope=self.scope)
        self.logger.info(f"{self.interface.name}: Connection Success")

    def disconnect(self, allow_reconnect=True):
        if (
            self.interface.state == "DISCONNECTED"
            and self.interface.connected() is False
        ):
            return

        # Synchronize the calls to @interface.disconnect since it takes an unknown
        # amount of time. If two calls to disconnect stack up, the if statement
        # should avoid multiple calls to disconnect.
        with self.mutex:
            try:
                if self.interface.connected():
                    self.interface.disconnect()
            except RuntimeError as error:
                self.logger.error(f"Disconnect: {self.interface.name}: {repr(error)}")

        # If the interface is set to auto_reconnect then delay so the thread
        # can come back around and allow the interface a chance to reconnect.
        if (
            allow_reconnect
            and self.interface.auto_reconnect
            and self.interface.state != "DISCONNECTED"
        ):
            self.attempting()
            if self.cancel_thread is not None:
                self.interface_thread_sleeper.sleep(self.interface.reconnect_delay)
        else:
            self.interface.state = "DISCONNECTED"
            if self.interface_or_router == "INTERFACE":
                InterfaceStatusModel.set(self.interface.as_json(), scope=self.scope)
            else:
                RouterStatusModel.set(self.interface.as_json(), scope=self.scope)

    # Disconnect from the interface and stop the thread
    def stop(self):
        name = self.name
        if self.interface:
            name = self.interface.name
        self.logger.info(f"{name}: stop requested")
        with self.mutex:
            # Need to make sure that @cancel_thread is set and the interface disconnected within
            # mutex to ensure that connect() is not called when we want to stop()
            self.cancel_thread = True
            if self.handler_thread:
                self.handler_thread.stop()
            if self.interface_thread_sleeper:
                self.interface_thread_sleeper.cancel()
            if self.interface:
                self.interface.disconnect()
                if self.interface_or_router == "INTERFACE":
                    valid_interface = InterfaceStatusModel.get_model(
                        name=self.interface.name, scope=self.scope
                    )
                else:
                    valid_interface = RouterStatusModel.get_model(
                        name=self.interface.name, scope=self.scope
                    )
                if valid_interface:
                    valid_interface.destroy()

    def shutdown(self, sig=None):
        if self.shutdown_complete:
            return  # Nothing more to do
        name = self.name
        if hasattr(self, "interface"):
            name = self.interface.name
        self.logger.info(f"{name}: shutdown requested")
        self.stop()
        super().shutdown()

    def graceful_kill(self):
        pass  # Just to avoid warning


if os.path.basename(__file__) == os.path.basename(sys.argv[0]):
    InterfaceMicroservice.class_run()
