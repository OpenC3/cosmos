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

import time
import unittest
import threading
from unittest.mock import *
from test.test_helper import *
from openc3.interfaces.interface import Interface
from openc3.interfaces.protocols.protocol import Protocol
from openc3.packets.packet import Packet

gvPacket = None
gvData = None


class InterfaceTestProtocol(Protocol):
    def __init__(
        self, added_data, stop_count=0, packet_added_data=None, packet_stop_count=0
    ):
        self.added_data = added_data
        self.packet_added_data = packet_added_data
        self.stop_count = int(stop_count)
        self.packet_stop_count = int(packet_stop_count)
        global gvPacket
        gvPacket = None
        global gvData
        gvData = None

    def read_data(self, data, extra=None):
        if data == b"":
            return ("STOP", extra)

        if self.stop_count > 0:
            self.stop_count -= 1
            return ("STOP", extra)
        if self.added_data:
            if self.added_data == "DISCONNECT":
                return ("DISCONNECT", extra)
            if self.added_data == "STOP":
                return (data, extra)
            data += self.added_data
            return (data, extra)
        else:
            return (data, extra)

    write_data = read_data

    def read_packet(self, packet):
        if self.packet_stop_count > 0:
            self.packet_stop_count -= 1
            return "STOP"
        if self.packet_added_data:
            if self.packet_added_data == "DISCONNECT":
                return "DISCONNECT"
            if self.packet_added_data == "STOP":
                return packet
            buffer = packet.buffer_no_copy()
            buffer += self.packet_added_data
            packet.buffer = buffer
            return packet
        else:
            return packet

    write_packet = read_packet

    def post_write_interface(self, packet, data, extra=None):
        global gvPacket
        gvPacket = packet
        global gvData
        gvData = data
        return (packet, data, extra)


# class Include api(unittest.TestCase):
#     def test_includes_api(self):
#         expect(Interface().methods).to include :cmd


class Initialize(unittest.TestCase):
    def test_initializes_the_instance_variables(self):
        i = Interface()
        self.assertEqual(i.name, "Interface")
        self.assertEqual(i.target_names, [])
        self.assertTrue(i.connect_on_startup)
        self.assertTrue(i.auto_reconnect)
        self.assertEqual(i.reconnect_delay, 5.0)
        self.assertFalse(i.disable_disconnect)
        self.assertEqual(i.packet_log_writer_pairs, [])
        self.assertEqual(i.stream_log_pair, None)
        self.assertEqual(i.routers, [])
        self.assertEqual(i.read_count, 0)
        self.assertEqual(i.write_count, 0)
        self.assertEqual(i.bytes_read, 0)
        self.assertEqual(i.bytes_written, 0)
        self.assertEqual(i.num_clients, 0)
        self.assertEqual(i.read_queue_size, 0)
        self.assertEqual(i.write_queue_size, 0)
        self.assertEqual(i.interfaces, [])
        self.assertEqual(len(i.options), 0)
        self.assertEqual(len(i.read_protocols), 0)
        self.assertEqual(len(i.write_protocols), 0)
        self.assertEqual(len(i.protocol_info), 0)

    def test_raises_an_exception(self):
        with self.assertRaisesRegex(RuntimeError, "connected not defined by Interface"):
            Interface().connected()

    def test_read_allowed_is_true(self):
        self.assertTrue(Interface().read_allowed)

    def test_write_allowed_is_true(self):
        self.assertTrue(Interface().write_allowed)

    def test_write_raw_allowed_is_true(self):
        self.assertTrue(Interface().write_raw_allowed)


class ReadInterface(unittest.TestCase):
    def setUp(self):
        pass
        # TODO: This doesn't seem to do anything ... trying to avoid "Error saving log file to bucket" messages
        # mock = Mock(spec=BucketUtilities)
        # patcher = patch("openc3.utilities.bucket_utilities", return_value=mock)
        # patcher.start()
        # self.addCleanup(patcher.stop)

    def test_raises_if_not_connected(self):
        class MyInterface(Interface):
            def connected(self):
                return False

        with self.assertRaisesRegex(RuntimeError, "Interface not connected"):
            MyInterface().read()

    def test_optionally_logs_raw_data_received_from_read_interface(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def read_interface(self):
                data = b"\x01\x02\x03\x04"
                self.read_interface_base(data)
                return (data, None)

        interface = MyInterface()
        interface.start_raw_logging()
        packet = interface.read()
        self.assertEqual(packet.buffer, b"\x01\x02\x03\x04")
        self.assertEqual(interface.read_count, 1)
        self.assertEqual(interface.bytes_read, 4)
        filename = interface.stream_log_pair.read_log.filename
        interface.stop_raw_logging()
        file = open(filename, "rb")
        self.assertEqual(file.read(), b"\x01\x02\x03\x04")
        file.close()
        interface.stream_log_pair.shutdown()

    def test_aborts_and_doesnt_log_if_no_data_is_returned_from_read_interface(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def read_interface(self):
                return (None, None)

        interface = MyInterface()
        interface.start_raw_logging()
        self.assertIsNone(interface.read())
        # Filenames don't get assigned until logging starts
        self.assertIsNone(interface.stream_log_pair.read_log.filename)
        self.assertEqual(interface.bytes_read, 0)
        interface.stream_log_pair.shutdown()

    def test_counts_raw_bytes_read(self):
        class MyInterface(Interface):
            def __init__(self):
                super().__init__()
                self.i = 0

            def connected(self):
                return True

            def read_interface(self):
                match self.i:
                    case 0:
                        self.i += 1
                        data = b"\x01\x02\x03\x04"
                    case 1:
                        self.i += 1
                        data = b"\x01\x02"
                    case 2:
                        self.i += 1
                        data = b"\x01\x02\x03\x04\x01\x02"
                self.read_interface_base(data)
                return (data, None)

        interface = MyInterface()
        interface.read()
        self.assertEqual(interface.bytes_read, 4)
        interface.read()
        self.assertEqual(interface.bytes_read, 6)
        interface.read()
        self.assertEqual(interface.bytes_read, 12)

    def test_handles_unknown_protocol(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def read_interface(self):
                data = b"\x01\x02\x03\x04"
                self.read_interface_base(data)
                return (data, None)

        interface = MyInterface()
        with self.assertRaisesRegex(
            RuntimeError,
            "Unknown protocol descriptor DATA. Must be 'READ', 'WRITE', or 'READ_WRITE'",
        ):
            interface.add_protocol(InterfaceTestProtocol, ["RUN"], "DATA")

    def test_allows_protocol_read_data_to_manipulate_data(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def read_interface(self):
                data = b"\x01\x02\x03\x04"
                self.read_interface_base(data)
                return (data, None)

        interface = MyInterface()
        interface.add_protocol(InterfaceTestProtocol, [b"\x05"], "READ")
        interface.add_protocol(InterfaceTestProtocol, [b"\x06"], "READ")
        interface.start_raw_logging()
        packet = interface.read()
        self.assertEqual(packet.buffer, b"\x01\x02\x03\x04\x05\x06")
        self.assertEqual(interface.read_count, 1)
        self.assertEqual(interface.bytes_read, 4)
        filename = interface.stream_log_pair.read_log.filename
        interface.stop_raw_logging()
        # Raw logging is still the original read_data return
        file = open(filename, "rb")
        self.assertEqual(file.read(), b"\x01\x02\x03\x04")
        file.close()
        interface.stream_log_pair.shutdown()

    def test_aborts_if_protocol_read_data_returns_disconnect(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def read_interface(self):
                data = b"\x01\x02\x03\x04"
                self.read_interface_base(data)
                return (data, None)

        interface = MyInterface()
        interface.add_protocol(InterfaceTestProtocol, ["DISCONNECT"], "READ")
        interface.start_raw_logging()
        packet = interface.read()
        self.assertIsNone(packet)
        self.assertEqual(interface.read_count, 0)
        self.assertEqual(interface.bytes_read, 4)
        filename = interface.stream_log_pair.read_log.filename
        interface.stop_raw_logging()
        file = open(filename, "rb")
        self.assertEqual(file.read(), b"\x01\x02\x03\x04")
        file.close()
        interface.stream_log_pair.shutdown()

    def test_gets_more_data_if_a_protocol_read_data_returns_stop(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def read_interface(self):
                data = b"\x01\x02\x03\x04"
                self.read_interface_base(data)
                return (data, None)

        interface = MyInterface()
        interface.add_protocol(InterfaceTestProtocol, [None, 1], "READ")
        interface.start_raw_logging()
        packet = interface.read()
        self.assertEqual(packet.buffer, b"\x01\x02\x03\x04")
        self.assertEqual(interface.read_count, 1)
        self.assertEqual(interface.bytes_read, 8)
        filename = interface.stream_log_pair.read_log.filename
        interface.stop_raw_logging()
        file = open(filename, "rb")
        self.assertEqual(file.read(), b"\x01\x02\x03\x04\x01\x02\x03\x04")
        file.close()
        interface.stream_log_pair.shutdown()

    def test_allows_protocol_read_packet_to_manipulate_packet(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def read_interface(self):
                data = b"\x01\x02\x03\x04"
                self.read_interface_base(data)
                return (data, None)

        interface = MyInterface()
        interface.add_protocol(InterfaceTestProtocol, [None, 0, b"\x08"], "READ")
        packet = interface.read()
        self.assertEqual(packet.buffer, b"\x01\x02\x03\x04\x08")
        self.assertEqual(interface.read_count, 1)
        self.assertEqual(interface.bytes_read, 4)

    def test_aborts_if_protocol_read_packet_returns_disconnect(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def read_interface(self):
                data = b"\x01\x02\x03\x04"
                self.read_interface_base(data)
                return (data, None)

            def post_read_packet(packet):
                return None

        interface = MyInterface()
        interface.add_protocol(InterfaceTestProtocol, [None, 0, "DISCONNECT"], "READ")
        packet = interface.read()
        self.assertIsNone(packet)
        self.assertEqual(interface.read_count, 0)
        self.assertEqual(interface.bytes_read, 4)

    def test_gets_more_data_if_protocol_read_packet_returns_stop(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def read_interface(self):
                data = b"\x01\x02\x03\x04"
                self.read_interface_base(data)
                return (data, None)

        interface = MyInterface()
        interface.add_protocol(InterfaceTestProtocol, [None, 0, None, 1], "READ")
        packet = interface.read()
        self.assertEqual(packet.buffer, b"\x01\x02\x03\x04")
        self.assertEqual(interface.read_count, 1)
        self.assertEqual(interface.bytes_read, 8)

    def test_returns_an_unidentified_packet(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def read_interface(self):
                data = b"\x01\x02\x03\x04"
                self.read_interface_base(data)
                return (data, None)

        interface = MyInterface()
        packet = interface.read()
        self.assertIsNone(packet.target_name)
        self.assertIsNone(packet.packet_name)


class WriteInterface(unittest.TestCase):
    def setUp(self):
        self.packet = Packet("TGT", "PKT", "BIG_ENDIAN", "Packet", b"\x01\x02\x03\x04")

    def test_raises_an_error_if_not_connected(self):
        class MyInterface(Interface):
            def connected(self):
                return False

        interface = MyInterface()
        with self.assertRaisesRegex(RuntimeError, "Interface not connected"):
            interface.write(self.packet)
        self.assertEqual(interface.write_count, 0)
        self.assertEqual(interface.bytes_written, 0)

    def test_is_single_threaded(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def write_interface(self, data, extra=None):
                self.write_interface_base(data)
                time.sleep(0.1)

        interface = MyInterface()
        start_time = time.time()
        threads = []
        for x in range(10):
            thread = threading.Thread(
                target=interface.write,
                args=[self.packet],
            )
            thread.start()
            threads.append(thread)
        for threads in threads:
            thread.join()
        self.assertGreater(time.time() - start_time, 1)
        self.assertEqual(interface.write_count, 10)
        self.assertEqual(interface.bytes_written, 40)

    def test_disconnects_if_write_interface_raises_an_exception(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def write_interface(self, data, extra=None):
                raise RuntimeError("Doom")

            def disconnect(self):
                self.disconnect_called = True

        interface = MyInterface()
        with self.assertRaisesRegex(RuntimeError, "Doom"):
            interface.write(self.packet)
        self.assertTrue(interface.disconnect_called)
        self.assertEqual(interface.write_count, 1)
        self.assertEqual(interface.bytes_written, 0)

    def test_allows_protocols_write_packet_to_modify_the_packet(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def write_interface(self, data, extra=None):
                self.write_interface_base(data)

        interface = MyInterface()
        interface.add_protocol(InterfaceTestProtocol, [None, 0, b"\x06", 0], "WRITE")
        interface.add_protocol(InterfaceTestProtocol, [None, 0, b"\x05", 0], "WRITE")
        interface.start_raw_logging()
        interface.write(self.packet)
        self.assertEqual(interface.write_count, 1)
        self.assertEqual(interface.bytes_written, 6)
        filename = interface.stream_log_pair.write_log.filename
        interface.stop_raw_logging()
        file = open(filename, "rb")
        self.assertEqual(file.read(), b"\x01\x02\x03\x04\x05\x06")
        file.close()
        interface.stream_log_pair.shutdown()

    def test_aborts_if_write_packet_returns_disconnect(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def write_interface(self, data, extra=None):
                self.write_interface_base(data)

        interface = MyInterface()
        interface.add_protocol(
            InterfaceTestProtocol, [None, 0, "DISCONNECT", 0], "WRITE"
        )
        interface.write(self.packet)
        self.assertEqual(interface.write_count, 1)
        self.assertEqual(interface.bytes_written, 0)

    def test_stops_if_write_packet_returns_stop(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def write_interface(self, data, extra=None):
                self.write_interface_base(data)

        interface = MyInterface()
        interface.add_protocol(InterfaceTestProtocol, [None, 0, "STOP", 1], "WRITE")
        interface.write(self.packet)
        interface.write(self.packet)
        self.assertEqual(interface.write_count, 2)
        self.assertEqual(interface.bytes_written, 4)

    def test_allows_protocol_write_data_to_modify_the_data(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def write_interface(self, data, extra=None):
                self.write_interface_base(data)

        interface = MyInterface()
        interface.add_protocol(InterfaceTestProtocol, [b"\x07", 0, None, 0], "WRITE")
        interface.add_protocol(InterfaceTestProtocol, [b"\x08", 0, None, 0], "WRITE")
        interface.start_raw_logging()
        interface.write(self.packet)
        self.assertEqual(interface.write_count, 1)
        self.assertEqual(interface.bytes_written, 6)
        filename = interface.stream_log_pair.write_log.filename
        interface.stop_raw_logging()
        file = open(filename, "rb")
        self.assertEqual(file.read(), b"\x01\x02\x03\x04\x08\x07")
        file.close()
        interface.stream_log_pair.shutdown()

    def test_aborts_if_write_data_returns_disconnect(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def write_interface(self, data, extra=None):
                self.write_interface_base(data)

        interface = MyInterface()
        interface.add_protocol(
            InterfaceTestProtocol, ["DISCONNECT", 0, None, 0], "WRITE"
        )
        interface.write(self.packet)
        self.assertEqual(interface.write_count, 1)
        self.assertEqual(interface.bytes_written, 0)

    def test_stops_if_write_data_returns_stop(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def write_interface(self, data, extra=None):
                self.write_interface_base(data)

        interface = MyInterface()
        interface.add_protocol(InterfaceTestProtocol, ["STOP", 1, None, 0], "WRITE")
        interface.write(self.packet)
        interface.write(self.packet)
        self.assertEqual(interface.write_count, 2)
        self.assertEqual(interface.bytes_written, 4)

    def test_calls_post_write_interface_with_the_packet_and_data(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def write_interface(self, data, extra=None):
                self.write_interface_base(data)

        interface = MyInterface()
        interface.add_protocol(InterfaceTestProtocol, [None, 0, None, 0], "WRITE")
        self.assertIsNone(gvPacket)
        self.assertIsNone(gvData)
        interface.write(self.packet)
        self.assertEqual(interface.write_count, 1)
        self.assertEqual(interface.bytes_written, 4)
        self.assertEqual(gvPacket, self.packet)
        self.assertEqual(gvData, self.packet.buffer)


class WriteRawInterface(unittest.TestCase):
    def setUp(self):
        self.data = b"\x01\x02\x03\x04"

    def test_raises_if_not_connected(self):
        class MyInterface(Interface):
            def connected(self):
                return False

        with self.assertRaisesRegex(RuntimeError, "Interface not connected"):
            MyInterface().write_raw(self.data)

    def test_is_single_threaded(self):
        class MyInterface(Interface):
            def connected(self):
                return True

            def write_interface(self, data, extra=None):
                self.write_interface_base(data)
                time.sleep(0.1)

        interface = MyInterface()
        start_time = time.time()
        threads = []
        for x in range(10):
            thread = threading.Thread(
                target=interface.write_raw,
                args=[self.data],
            )
            thread.start()
            threads.append(thread)
        for threads in threads:
            thread.join()
        self.assertGreater(time.time() - start_time, 1)
        self.assertEqual(interface.write_count, 0)
        self.assertEqual(interface.bytes_written, 40)


class CopyTo(unittest.TestCase):
    def test_copies_the_interface(self):
        i = Interface()
        i.name = "TEST"
        i.target_names = ["TGT1", "TGT2"]
        i.connect_on_startup = False
        i.auto_reconnect = False
        i.reconnect_delay = 1.0
        i.disable_disconnect = True
        i.packet_log_writer_pairs = [1, 2]
        i.routers = [3, 4]
        i.read_count = 1
        i.write_count = 2
        i.bytes_read = 3
        i.bytes_written = 4
        i.num_clients = 5
        i.read_queue_size = 6
        i.write_queue_size = 7
        i.read_protocols = [1, 2]
        i.write_protocols = [3, 4]
        i.protocol_info = [[Protocol, [], "READ_WRITE"]]

        i2 = Interface()
        i.copy_to(i2)
        self.assertEqual(i2.name, "TEST")
        self.assertEqual(i2.target_names, ["TGT1", "TGT2"])
        self.assertFalse(i2.connect_on_startup)
        self.assertFalse(i2.auto_reconnect)
        self.assertEqual(i2.reconnect_delay, 1.0)
        self.assertTrue(i2.disable_disconnect)
        self.assertEqual(i2.packet_log_writer_pairs, [1, 2])
        self.assertEqual(i2.routers, [3, 4])
        self.assertEqual(i2.read_count, 1)
        self.assertEqual(i2.write_count, 2)
        self.assertEqual(i2.bytes_read, 3)
        self.assertEqual(i2.bytes_written, 4)
        self.assertEqual(i2.num_clients, 0)  # does not get copied)
        self.assertEqual(i2.read_queue_size, 0)  # does not get copied)
        self.assertEqual(i2.write_queue_size, 0)  # does not get copied)
        self.assertGreater(len(i2.read_protocols), 0)
        self.assertGreater(len(i2.write_protocols), 0)
        self.assertEqual(i2.protocol_info, [[Protocol, [], "READ_WRITE"]])


class InterfaceCmd(unittest.TestCase):
    def test_just_returns_False_by_default(self):
        i = Interface()
        self.assertEqual(i.interface_cmd("SOMETHING", "WITH", "ARGS"), False)


class ProtocolCmd(unittest.TestCase):
    class InterfaceCmdProtocol(Protocol):
        def __init__(self, *args):
            super().__init__(args)
            self.cmd_name = None
            self.cmd_args = None

        def protocol_cmd(self, cmd_name, *cmd_args):
            self.cmd_name = cmd_name
            self.cmd_args = cmd_args

    def setUp(self):
        self.i = Interface()
        self.i.add_protocol(
            ProtocolCmd.InterfaceCmdProtocol, [None, 0, None, 0], "WRITE"
        )
        self.write_protocol = self.i.write_protocols[-1]
        self.i.add_protocol(
            ProtocolCmd.InterfaceCmdProtocol, [None, 0, None, 0], "READ"
        )
        self.read_protocol = self.i.read_protocols[-1]
        self.i.add_protocol(
            ProtocolCmd.InterfaceCmdProtocol, [None, 0, None, 0], "READ_WRITE"
        )
        self.read_write_protocol = self.i.read_protocols[-1]

    def test_handles_unknown_protocol_descriptors(self):
        with self.assertRaisesRegex(
            RuntimeError,
            "Unknown protocol descriptor DATA. Must be 'READ', 'WRITE', or 'READ_WRITE'",
        ):
            self.i.protocol_cmd("A", "GREAT", "CMD", read_write="DATA")

    def test_can_target_read_protocols(self):
        self.i.protocol_cmd("A", "GREAT", "CMD", read_write="READ")
        self.assertIsNone(self.write_protocol.cmd_name)
        self.assertEqual(self.read_protocol.cmd_name, "A")
        self.assertEqual(self.read_protocol.cmd_args, ("GREAT", "CMD"))
        self.assertEqual(self.read_write_protocol.cmd_name, "A")
        self.assertEqual(self.read_write_protocol.cmd_args, ("GREAT", "CMD"))

    def test_can_target_write_protocols(self):
        self.i.protocol_cmd("A", "GREAT", "CMD", read_write="WRITE")
        self.assertEqual(self.write_protocol.cmd_name, "A")
        self.assertEqual(self.write_protocol.cmd_args, ("GREAT", "CMD"))
        self.assertIsNone(self.read_protocol.cmd_name)
        self.assertEqual(self.read_write_protocol.cmd_name, "A")
        self.assertEqual(self.read_write_protocol.cmd_args, ("GREAT", "CMD"))

    def test_can_target_read_write_protocols(self):
        self.i.protocol_cmd("A", "GREAT", "CMD", read_write="READ_WRITE")
        self.assertEqual(self.read_protocol.cmd_name, "A")
        self.assertEqual(self.read_protocol.cmd_args, ("GREAT", "CMD"))
        self.assertEqual(self.write_protocol.cmd_name, "A")
        self.assertEqual(self.write_protocol.cmd_args, ("GREAT", "CMD"))
        self.assertEqual(self.read_write_protocol.cmd_name, "A")
        self.assertEqual(self.read_write_protocol.cmd_args, ("GREAT", "CMD"))

    def test_can_target_protocols_based_on_index_test_0(self):
        self.i.protocol_cmd("A", "GREAT", "CMD", index=0)
        self.assertEqual(self.write_protocol.cmd_name, "A")
        self.assertEqual(self.write_protocol.cmd_args, ("GREAT", "CMD"))
        self.assertIsNone(self.read_protocol.cmd_name)
        self.assertIsNone(self.read_write_protocol.cmd_name)

    def test_can_target_protocols_based_on_index_test_1(self):
        self.i.protocol_cmd("A", "GREAT", "CMD", index=1)
        self.assertIsNone(self.write_protocol.cmd_name)
        self.assertEqual(self.read_protocol.cmd_name, "A")
        self.assertEqual(self.read_protocol.cmd_args, ("GREAT", "CMD"))
        self.assertIsNone(self.read_write_protocol.cmd_name)

    def test_can_target_protocols_based_on_index_test_2(self):
        self.i.protocol_cmd("A", "GREAT", "CMD", index=2)
        self.assertIsNone(self.write_protocol.cmd_name)
        self.assertIsNone(self.read_protocol.cmd_name)
        self.assertEqual(self.read_write_protocol.cmd_name, "A")
        self.assertEqual(self.read_write_protocol.cmd_args, ("GREAT", "CMD"))

    def test_can_target_protocols_based_on_index_ignoring_type(self):
        self.i.protocol_cmd("A", "GREAT", "CMD", read_write="READ", index=2)
        self.assertIsNone(self.write_protocol.cmd_name)
        self.assertIsNone(self.read_protocol.cmd_name)
        self.assertEqual(self.read_write_protocol.cmd_name, "A")
        self.assertEqual(self.read_write_protocol.cmd_args, ("GREAT", "CMD"))
