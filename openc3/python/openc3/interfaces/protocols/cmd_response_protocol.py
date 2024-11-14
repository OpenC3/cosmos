# Copyright 2024 OpenC3, Inc.
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

from openc3.system.system import System
from openc3.config.config_parser import ConfigParser
from openc3.utilities.logger import Logger
from openc3.interfaces.protocols.protocol import Protocol
from queue import SimpleQueue, Empty
import time


# Protocol that waits for a response for any commands with a defined response packet.
# The response packet is identified but not defined by the protocol.
class CmdResponseProtocol(Protocol):
    # @param response_timeout [Float] Number of seconds to wait before timing out
    #   when waiting for a response
    # @param response_polling_period [Float] Number of seconds to wait between polling
    #   for a response
    # @param raise_exceptions [String] Whether to raise exceptions when errors
    #   occur in the protocol like unexpected responses or response timeouts.
    # @param allow_empty_data [true/false/nil] See Protocol#initialize
    def __init__(
        self, response_timeout=5.0, response_polling_period=0.02, raise_exceptions=False, allow_empty_data=None
    ):
        super().__init__(allow_empty_data)
        self.response_timeout = ConfigParser.handle_none(response_timeout)
        if self.response_timeout:
            self.response_timeout = float(response_timeout)
        self.response_polling_period = float(response_polling_period)
        self.raise_exceptions = ConfigParser.handle_true_false(raise_exceptions)
        self.write_block_queue = SimpleQueue()
        self.response_packet = None

    def connect_reset(self):
        super().connect_reset()
        try:
            while self.write_block_queue.qsize != 0:
                self.write_block_queue.get_nowait()
        except Empty:
            pass

    def disconnect_reset(self):
        super().disconnect_reset()
        self.write_block_queue.put(None)  # Unblock the write block queue

    def read_packet(self, packet):
        if self.response_packet is not None:
            # Grab the response packet specified in the command
            result_packet = System.telemetry.packet(self.response_packet[0], self.response_packet[1]).clone()
            result_packet.buffer = packet.buffer
            result_packet.received_time = None
            result_packet.stored = packet.stored
            result_packet.extra = packet.extra

            # Release the write
            self.write_block_queue.put(None)

            # This returns the fully identified and defined packet
            # Received time is handled by the interface microservice
            return result_packet
        else:
            return packet

    def write_packet(self, packet):
        # Setup the response packet (if there is one)
        # This primes waiting for the response in post_write_interface
        self.response_packet = packet.response

        return packet

    def post_write_interface(self, packet, data, extra=None):
        if self.response_packet is not None:
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
                    if self.interface is not None:
                        interface_name = self.interface.name
                    self.handle_error(f"{interface_name}: Timeout waiting for response")

            self.response_packet = None
        return super().post_write_interface(packet, data, extra)

    def handle_error(self, msg):
        Logger.error(msg)
        if self.raise_exceptions:
            raise RuntimeError(msg)
