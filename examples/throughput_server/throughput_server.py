#!/usr/bin/env python3
# Copyright 2026 OpenC3, Inc.
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

"""
COSMOS Throughput Testing Server

A standalone TCP/IP server for measuring COSMOS command and telemetry throughput.
Supports dual-port operation for INST (Ruby) and INST2 (Python) targets.

Usage:
    python throughput_server.py [--inst-port PORT] [--inst2-port PORT]
"""

import argparse
import asyncio
import logging
import signal
import struct
import sys
import time
from typing import Dict

from ccsds import (
    parse_ccsds_command,
    read_packet_from_stream,
)
from config import (
    CMD_GET_STATS,
    CMD_GET_STATS_NO_MSG,
    CMD_RESET_STATS,
    CMD_START_STREAM,
    CMD_STOP_STREAM,
    DEFAULT_STREAM_RATE,
    INST2_PORT,
    INST_PORT,
    MAX_STREAM_RATE,
)
from metrics import StreamState, ThroughputMetrics, ThroughputStatusPacket

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)


class ClientHandler:
    """Handle a single client connection."""

    def __init__(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        port: int,
        port_name: str,
    ):
        self.reader = reader
        self.writer = writer
        self.port = port
        self.port_name = port_name
        self.metrics = ThroughputMetrics()
        self.stream_state = StreamState()
        self.status_builder = ThroughputStatusPacket()
        self.running = True
        self._buffer = b""
        self._tlm_sequence = 0

        # Get client info
        peername = writer.get_extra_info("peername")
        self.client_addr = f"{peername[0]}:{peername[1]}" if peername else "unknown"

    async def handle(self) -> None:
        """Main handler loop for this client."""
        logger.info(f"[{self.port_name}] Client connected: {self.client_addr}")

        # Send initial status packet so COSMOS has data immediately
        await self._send_status_packet()

        # Start background tasks
        rate_update_task = asyncio.create_task(self._rate_update_loop())
        stream_task = asyncio.create_task(self._stream_loop())

        try:
            while self.running:
                try:
                    data = await asyncio.wait_for(self.reader.read(65536), timeout=0.1)
                    if not data:
                        logger.info(
                            f"[{self.port_name}] Client disconnected: {self.client_addr}"
                        )
                        break

                    logger.debug(
                        f"[{self.port_name}] Received {len(data)} bytes: {data[:32].hex()}..."
                    )
                    self._buffer += data
                    await self._process_buffer()

                except asyncio.TimeoutError:
                    # No data, continue loop (allows checking self.running)
                    continue
                except ConnectionResetError:
                    logger.info(
                        f"[{self.port_name}] Connection reset: {self.client_addr}"
                    )
                    break

        finally:
            self.running = False
            rate_update_task.cancel()
            stream_task.cancel()

            try:
                await rate_update_task
            except asyncio.CancelledError:
                pass

            try:
                await stream_task
            except asyncio.CancelledError:
                pass

            self.writer.close()
            try:
                await self.writer.wait_closed()
            except Exception:
                pass

            logger.info(
                f"[{self.port_name}] Session stats for {self.client_addr}: "
                f"cmds={self.metrics.cmd_recv_count}, "
                f"tlm={self.metrics.tlm_sent_count}, "
                f"bytes_in={self.metrics.bytes_recv}, "
                f"bytes_out={self.metrics.bytes_sent}"
            )

    async def _process_buffer(self) -> None:
        """Process complete packets from the buffer."""
        while True:
            if len(self._buffer) < 6:
                break

            # Parse CCSDS primary header fields for validation
            word0 = struct.unpack(">H", self._buffer[0:2])[0]
            version = (word0 >> 13) & 0x07
            packet_type = (word0 >> 12) & 0x01

            ccsds_len = struct.unpack(">H", self._buffer[4:6])[0]
            expected_total = ccsds_len + 7

            # Validate CCSDS command header
            # version should be 0, packet_type should be 1 (command)
            # CCSDSLENGTH should be reasonable (< 1000 bytes)
            valid_header = version == 0 and packet_type == 1 and ccsds_len < 1000

            if not valid_header:
                # Invalid header - try to resync by discarding 1 byte
                logger.debug(
                    f"[{self.port_name}] Invalid header: ver={version} type={packet_type} "
                    f"len={ccsds_len}, buffer[0:8]={self._buffer[0:8].hex()}"
                )
                self._buffer = self._buffer[1:]
                continue

            packet, remaining = read_packet_from_stream(self._buffer)
            if not packet:
                break

            self._buffer = remaining
            await self._handle_packet(packet)

    async def _handle_packet(self, packet: bytes) -> None:
        """Handle a complete CCSDS command packet."""
        try:
            cmd = parse_ccsds_command(packet)
            self.metrics.record_command(len(packet))

            # Dispatch based on PKTID
            if cmd.pktid == CMD_START_STREAM:
                await self._handle_start_stream(cmd.payload)
            elif cmd.pktid == CMD_STOP_STREAM:
                await self._handle_stop_stream()
            elif cmd.pktid == CMD_GET_STATS:
                await self._handle_get_stats()
            elif cmd.pktid == CMD_GET_STATS_NO_MSG:
                await self._handle_get_stats()
            elif cmd.pktid == CMD_RESET_STATS:
                await self._handle_reset_stats()
            else:
                logger.warning(f"[{self.port_name}] Unknown command PKTID: {cmd.pktid}")

        except Exception as e:
            logger.error(f"[{self.port_name}] Error handling packet: {e}")

    async def _handle_start_stream(self, payload: bytes) -> None:
        """Handle START_STREAM command.

        Payload: RATE (32 UINT), PACKET_TYPES (32 UINT)
        """
        if len(payload) >= 8:
            rate, packet_types = struct.unpack(">II", payload[:8])
        elif len(payload) >= 4:
            rate = struct.unpack(">I", payload[:4])[0]
            packet_types = 0x01
        else:
            rate = DEFAULT_STREAM_RATE
            packet_types = 0x01

        # Clamp rate to valid range
        rate = max(1, min(rate, MAX_STREAM_RATE))

        self.stream_state.start(rate, packet_types)
        self.metrics.target_rate = rate

        logger.info(
            f"[{self.port_name}] Started streaming at {rate} Hz "
            f"(packet_types=0x{packet_types:08X}, interval={self.stream_state.send_interval:.6f}s)"
        )

    async def _handle_stop_stream(self) -> None:
        """Handle STOP_STREAM command."""
        self.stream_state.stop()
        self.metrics.target_rate = 0
        logger.info(f"[{self.port_name}] Stopped streaming")

    async def _handle_get_stats(self) -> None:
        """Handle GET_STATS command - send THROUGHPUT_STATUS packet."""
        await self._send_status_packet()

    async def _handle_reset_stats(self) -> None:
        """Handle RESET_STATS command."""
        self.metrics.reset()
        self.status_builder.reset_sequence()
        logger.info(f"[{self.port_name}] Reset statistics")

    async def _send_status_packet(self) -> None:
        """Send a THROUGHPUT_STATUS telemetry packet (non-streaming path)."""
        packet = self.status_builder.build(self.metrics)
        await self._send_packet(packet)

    async def _send_packet(self, packet: bytes) -> None:
        """Send a packet to the client (non-streaming path)."""
        try:
            self.writer.write(packet)
            await self.writer.drain()
            self.metrics.record_telemetry(len(packet))
        except Exception as e:
            logger.error(f"[{self.port_name}] Error sending packet: {e}")
            self.running = False

    async def _rate_update_loop(self) -> None:
        """Background task to update rate calculations."""
        while self.running:
            await asyncio.sleep(1.0)
            self.metrics.update_rates()

    async def _stream_loop(self) -> None:
        """Background task to send telemetry at configured rate.

        Uses time-compensated streaming to maintain accurate rates despite
        asyncio.sleep() imprecision. Tracks elapsed time and sends packets
        to catch up to where we should be.
        """
        BATCH_INTERVAL = 0.05  # Check every 50ms

        while self.running:
            if self.stream_state.streaming and self.stream_state.rate > 0:
                try:
                    rate = self.stream_state.rate
                    stream_start = time.time()
                    packets_sent = 0

                    while self.stream_state.streaming and self.running:
                        elapsed = time.time() - stream_start

                        # How many packets should have been sent by now?
                        expected_packets = int(elapsed * rate)
                        packets_to_send = expected_packets - packets_sent

                        # Only send if we're behind schedule
                        if packets_to_send > 0:
                            for _ in range(packets_to_send):
                                self.status_builder.update(self.metrics)
                                # Must copy buffer - write() may not copy immediately
                                self.writer.write(
                                    bytes(self.status_builder.get_buffer())
                                )
                                self.metrics.record_telemetry(
                                    self.status_builder.PACKET_SIZE
                                )
                            packets_sent += packets_to_send
                            await self.writer.drain()

                        await asyncio.sleep(BATCH_INTERVAL)

                except Exception as e:
                    logger.error(f"[{self.port_name}] Stream error: {e}")
                    self.running = False
                    break
            else:
                # Not streaming - ensure buffer is flushed, then wait
                try:
                    await self.writer.drain()
                except Exception:
                    pass
                await asyncio.sleep(0.1)


class ThroughputServer:
    """Multi-port throughput testing server."""

    def __init__(self, inst_port: int = INST_PORT, inst2_port: int = INST2_PORT):
        self.inst_port = inst_port
        self.inst2_port = inst2_port
        self.servers: Dict[int, asyncio.Server] = {}
        self.clients: Dict[str, ClientHandler] = {}
        self.running = False

    async def start(self) -> None:
        """Start the server on all configured ports."""
        self.running = True

        # Start INST port server
        inst_server = await asyncio.start_server(
            lambda r, w: self._handle_client(r, w, self.inst_port, "INST"),
            "0.0.0.0",
            self.inst_port,
        )
        self.servers[self.inst_port] = inst_server
        logger.info(f"INST server listening on port {self.inst_port}")

        # Start INST2 port server
        inst2_server = await asyncio.start_server(
            lambda r, w: self._handle_client(r, w, self.inst2_port, "INST2"),
            "0.0.0.0",
            self.inst2_port,
        )
        self.servers[self.inst2_port] = inst2_server
        logger.info(f"INST2 server listening on port {self.inst2_port}")

        logger.info("Throughput server started. Press Ctrl+C to stop.")

    async def _handle_client(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        port: int,
        port_name: str,
    ) -> None:
        """Handle a new client connection."""
        handler = ClientHandler(reader, writer, port, port_name)
        client_key = f"{port_name}:{handler.client_addr}"
        self.clients[client_key] = handler

        try:
            await handler.handle()
        finally:
            del self.clients[client_key]

    async def stop(self) -> None:
        """Stop all servers and disconnect clients."""
        self.running = False

        # Stop all client handlers
        for handler in list(self.clients.values()):
            handler.running = False

        # Close servers
        for port, server in self.servers.items():
            server.close()
            await server.wait_closed()
            logger.info(f"Server on port {port} stopped")

        logger.info("Throughput server stopped")

    async def run_forever(self) -> None:
        """Run the server until interrupted."""
        await self.start()

        # Wait for shutdown signal
        stop_event = asyncio.Event()

        def signal_handler():
            logger.info("Shutdown signal received")
            stop_event.set()

        loop = asyncio.get_event_loop()
        for sig in (signal.SIGINT, signal.SIGTERM):
            try:
                loop.add_signal_handler(sig, signal_handler)
            except NotImplementedError:
                # Windows doesn't support add_signal_handler
                pass

        try:
            await stop_event.wait()
        except asyncio.CancelledError:
            pass

        await self.stop()


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="COSMOS Throughput Testing Server",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--inst-port",
        type=int,
        default=INST_PORT,
        help="Port for INST (Ruby) target",
    )
    parser.add_argument(
        "--inst2-port",
        type=int,
        default=INST2_PORT,
        help="Port for INST2 (Python) target",
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debug logging",
    )

    args = parser.parse_args()

    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    server = ThroughputServer(
        inst_port=args.inst_port,
        inst2_port=args.inst2_port,
    )

    try:
        asyncio.run(server.run_forever())
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        sys.exit(0)


if __name__ == "__main__":
    main()
