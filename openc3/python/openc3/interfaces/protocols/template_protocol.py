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

import re
import time
from queue import SimpleQueue, Empty
from openc3.config.config_parser import ConfigParser
from openc3.system.system import System
from openc3.packets.packet import Packet
from openc3.utilities.logger import Logger
from openc3.interfaces.protocols.terminated_protocol import TerminatedProtocol


# Protocol which delineates packets using delimiter characters. Designed for
# text based protocols which expect a command and send a response. The
# protocol handles sending the command and capturing the response.
class TemplateProtocol(TerminatedProtocol):
    # @param write_termination_characters (see TerminatedProtocol#initialize)
    # @param read_termination_characters (see TerminatedProtocol#initialize)
    # @param ignore_lines [Integer] Number of newline terminated reads to
    #   ignore when processing the response
    # @param initial_read_delay [Integer] Initial delay when connecting before
    #   trying to read
    # @param response_lines [Integer] Number of newline terminated lines which
    #   comprise the response
    # @param strip_read_termination (see TerminatedProtocol#initialize)
    # @param discard_leading_bytes (see TerminatedProtocol#initialize)
    # @param sync_pattern (see TerminatedProtocol#initialize)
    # @param fill_fields (see TerminatedProtocol#initialize)
    # @param response_timeout [Float] Number of seconds to wait before timing out
    #   when waiting for a response
    # @param response_polling_period [Float] Number of seconds to wait between polling
    #   for a response
    # @param raise_exceptions [String] Whether to raise exceptions when errors
    #   occur in the protocol like unexpected responses or response timeouts.
    # @param allow_empty_data [true/false/nil] See Protocol#initialize
    def __init__(
        self,
        write_termination_characters,
        read_termination_characters,
        ignore_lines=0,
        initial_read_delay=None,
        response_lines=1,
        strip_read_termination=True,
        discard_leading_bytes=0,
        sync_pattern=None,
        fill_fields=False,
        response_timeout=5.0,
        response_polling_period=0.02,
        raise_exceptions=False,
        allow_empty_data=None,
    ):
        super().__init__(
            write_termination_characters,
            read_termination_characters,
            strip_read_termination,
            discard_leading_bytes,
            sync_pattern,
            fill_fields,
            allow_empty_data,
        )
        self.response_template = None
        self.response_packet = None
        self.response_target_name = None
        self.response_packets = []
        self.write_block_queue = SimpleQueue()
        self.ignore_lines = int(ignore_lines)
        self.response_lines = int(response_lines)
        self.initial_read_delay = ConfigParser.handle_none(initial_read_delay)
        if self.initial_read_delay is not None:
            self.initial_read_delay = float(initial_read_delay)
        self.response_timeout = ConfigParser.handle_none(response_timeout)
        if self.response_timeout is not None:
            self.response_timeout = float(response_timeout)
        if response_polling_period is not None:
            self.response_polling_period = float(response_polling_period)
        else:
            self.response_polling_period = 0.0
        self.connect_complete_time = None
        self.raise_exceptions = ConfigParser.handle_true_false(raise_exceptions)

    def reset(self):
        super().reset()
        self.initial_read_delay_needed = True

    def connect_reset(self):
        super().connect_reset()
        try:
            while self.write_block_queue.qsize != 0:
                self.write_block_queue.get_nowait()
        except Empty:
            pass

        if self.initial_read_delay:
            self.connect_complete_time = time.time() + self.initial_read_delay

    def disconnect_reset(self):
        super().disconnect_reset()
        self.write_block_queue.put(None)  # Unblock the write block queue

    def read_data(self, data, extra=None):
        if len(data) <= 0:
            return super().read_data(data, extra)

        # Drop all data until the initial_read_delay is complete.
        # This gets rid of unused welcome messages,
        # prompts, and other junk on initial connections
        if self.initial_read_delay and self.initial_read_delay_needed and self.connect_complete_time:
            if time.time() < self.connect_complete_time:
                return ("STOP", extra)
            self.initial_read_delay_needed = False
        return super().read_data(data, extra)

    def read_packet(self, packet):
        if self.response_template and self.response_packet:
            # If lines make it this far they are part of a response
            self.response_packets.append(packet)
            if len(self.response_packets) < (self.ignore_lines + self.response_lines):
                return "STOP"

            for _ in range(0, self.ignore_lines):
                self.response_packets.pop(0)
            response_string = b""
            for _ in range(0, self.response_lines):
                response = self.response_packets.pop(0)
                response_string += response.buffer

            # Grab the response packet specified in the command
            result_packet = System.telemetry.packet(self.response_target_name, self.response_packet).clone()
            result_packet.received_time = None
            if result_packet.id_items:
                for item in result_packet.id_items:
                    result_packet.write_item(item, item.id_value, "RAW")

            # Convert the response template into a Regexp
            response_item_names = []
            response_template = self.response_template
            response_template_items = re.findall(r"<.*?>", self.response_template)

            for item in response_template_items:
                response_item_names.append(item[1:-1])
                response_template = response_template.replace(item, r"(.*)")

            # Scan the response for the variables in brackets <VARIABLE>
            # Write the packet value with each of the values received
            response_values = re.findall(response_template, response_string.decode())
            response_values = [x for x in response_values if len(x) > 0]
            if len(response_values) != len(response_item_names):
                interface_name = ""
                if self.interface:
                    interface_name = self.interface.name
                self.handle_error(f"{interface_name}: Unexpected response: {response_string}")
            else:
                try:
                    for i, value in enumerate(response_values):
                        result_packet.write(response_item_names[i], value)
                except (ValueError, RuntimeError) as error:
                    interface_name = ""
                    if self.interface:
                        interface_name = self.interface.name
                    self.handle_error(f"{interface_name}: Could not write value {value} due to {repr(error)}")

            self.response_packets = []

            # Release the write
            if self.response_template and self.response_packet:
                self.write_block_queue.put(None)

            return result_packet
        else:
            return packet

    def write_packet(self, packet):
        # Make sure we are past the initial data dropping period
        if (
            self.initial_read_delay
            and self.initial_read_delay_needed
            and self.connect_complete_time
            and time.time() < self.connect_complete_time
        ):
            delay_needed = self.connect_complete_time - time.time()
            if delay_needed > 0:
                time.sleep(delay_needed)

        # First grab the response template and response packet (if there is one)
        try:
            self.response_template = packet.read("RSP_TEMPLATE").strip()
            self.response_packet = packet.read("RSP_PACKET").strip()
            self.response_target_name = packet.target_name
            # If the template or packet are empty set them to nil. This allows for
            # the user to remove the RSP_TEMPLATE and RSP_PACKET values and avoid
            # any response timeouts
            if len(self.response_template) == 0 or len(self.response_packet) == 0:
                self.response_template = None
                self.response_packet = None
                self.response_target_name = None
        except Exception:
            # If there is no response template we set to nil
            self.response_template = None
            self.response_packet = None
            self.response_target_name = None

        # Grab the command template because that is all we eventually send
        self.template = packet.read("CMD_TEMPLATE")
        # Create a new packet to populate with the template
        raw_packet = Packet(None, None)
        raw_packet.buffer = bytes(self.template, "ascii")
        raw_packet = super().write_packet(raw_packet)
        if isinstance(raw_packet, str):
            return raw_packet

        data = raw_packet.buffer
        # Scan the template for variables in brackets <VARIABLE>
        # Read these values from the packet and substitute them in the template
        # and in the @response_packet name
        for variable in re.findall(r"<(.*?)>", self.template):
            value = packet.read(variable, "RAW")
            data = data.replace(bytes(f"<{variable}>", "ascii"), bytes(f"{value}", "ascii"))
            if self.response_packet:
                self.response_packet = self.response_packet.replace((f"<{variable}>"), f"{value}")
            raw_packet.buffer = data

        return raw_packet

    def post_write_interface(self, packet, data, extra=None):
        if self.response_template and self.response_packet:
            if self.response_timeout:
                response_timeout_time = time.time() + self.response_timeout
            else:
                response_timeout_time = None

            # Block the write until the response is received
            while True:
                try:
                    self.write_block_queue.get_nowait()
                    break
                except Empty:
                    time.sleep(self.response_polling_period)
                    if response_timeout_time is None:
                        continue
                    if response_timeout_time and time.time() < response_timeout_time:
                        continue
                    interface_name = ""
                    if self.interface:
                        interface_name = self.interface.name
                    self.handle_error(f"{interface_name}: Timeout waiting for response")
                    break

            self.response_template = None
            self.response_packet = None
            self.response_target_name = None
            self.response_packets.clear
        return super().post_write_interface(packet, data, extra)

    def handle_error(self, msg):
        Logger.error(msg)
        if self.raise_exceptions:
            raise RuntimeError(msg)
