# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
from unittest.mock import patch

from openc3.topics.decom_interface_topic import DecomInterfaceTopic
from openc3.topics.topic import Topic


class TestDecomInterfaceTopicBuildCmd(unittest.TestCase):
    """Regression tests for github.com/OpenC3/cosmos/issues/3217.

    The Ruby build_cmd handler writes the raw command buffer bytes directly to
    the ACKCMD topic. The Python caller must handle that shape without trying
    to UTF-8 decode or JSON-parse the buffer."""

    DECOM_ID = b"1700000000000-0"

    def _ack(self, fields):
        msg = {b"id": self.DECOM_ID, b"result": b"SUCCESS"}
        msg.update(fields)
        return [("ack", b"x", msg, None)]

    @patch.object(Topic, "read_topics")
    @patch.object(Topic, "write_topic", return_value=DECOM_ID)
    @patch.object(Topic, "update_topic_offsets")
    def test_ruby_raw_bytes_buffer_returned_as_bytes(self, _offsets, _write, read):
        raw = b"\x13\xe7\xc0\x00\x00\x00\x00\x01\x00\x00@\xa0\x00\x00\xab\x00\x00\x00\x00"
        read.return_value = self._ack(
            {
                b"target_name": b"INST",
                b"packet_name": b"COLLECT",
                b"received_count": b"0",
                b"buffer": raw,
            }
        )

        result = DecomInterfaceTopic.build_cmd("INST", "COLLECT", {}, True, False, timeout=1, scope="DEFAULT")

        self.assertEqual(result["target_name"], "INST")
        self.assertEqual(result["packet_name"], "COLLECT")
        self.assertEqual(result["buffer"], raw)
        self.assertIsInstance(result["buffer"], bytes)
        self.assertIsInstance(result["target_name"], str)

    @patch.object(Topic, "read_topics")
    @patch.object(Topic, "write_topic", return_value=DECOM_ID)
    @patch.object(Topic, "update_topic_offsets")
    def test_non_utf8_buffer_does_not_raise(self, _offsets, _write, read):
        """Before the fix this raised UnicodeDecodeError on byte 0xc0 (the
        CCSDS sequence-flags byte) because the caller did .decode() on every
        value."""
        raw = b"\xff\xfe\xfd\xc0\x80\x90\xa0"
        read.return_value = self._ack(
            {
                b"target_name": b"INST",
                b"packet_name": b"PKT",
                b"received_count": b"0",
                b"buffer": raw,
            }
        )

        result = DecomInterfaceTopic.build_cmd("INST", "PKT", {}, True, False, timeout=1, scope="DEFAULT")

        self.assertEqual(result["buffer"], raw)

    @patch.object(Topic, "read_topics")
    @patch.object(Topic, "write_topic", return_value=DECOM_ID)
    @patch.object(Topic, "update_topic_offsets")
    def test_error_result_raises_runtime_error(self, _offsets, _write, read):
        read.return_value = [("ack", b"x", {b"id": self.DECOM_ID, b"result": b"value out of range"}, None)]

        with self.assertRaisesRegex(RuntimeError, "out of range"):
            DecomInterfaceTopic.build_cmd("INST", "PKT", {}, True, False, timeout=1, scope="DEFAULT")

    @patch.object(Topic, "read_topics", return_value=[])
    @patch.object(Topic, "write_topic", return_value=DECOM_ID)
    @patch.object(Topic, "update_topic_offsets")
    def test_timeout_raises_runtime_error(self, _offsets, _write, _read):
        with self.assertRaisesRegex(RuntimeError, "Timeout of 0.05s waiting for cmd ack"):
            DecomInterfaceTopic.build_cmd("BLAH", "PKT", {}, True, False, timeout=0.05, scope="DEFAULT")


class TestDecomInterfaceTopicBuildCmdHandler(unittest.TestCase):
    """The Python handler (handle_build_cmd) must write raw bytes to the ACKCMD
    topic to match the Ruby handler's format."""

    @patch("openc3.microservices.interface_decom_common.Topic")
    @patch("openc3.microservices.interface_decom_common.System")
    def test_handler_writes_raw_bytes_buffer(self, mock_system, mock_topic):
        from openc3.microservices.interface_decom_common import handle_build_cmd

        command = mock_system.commands.build_cmd.return_value
        command.target_name = "INST"
        command.packet_name = "COLLECT"
        command.received_count = 0
        command.packet_time.to_nsec_from_epoch = 1
        command.received_time.to_nsec_from_epoch = 1
        command.buffer_no_copy.return_value = bytearray(b"\x13\xe7\xc0\x00\x00\x00\x00\x01")

        import json

        build_cmd_json = json.dumps(
            {
                "target_name": "INST",
                "cmd_name": "COLLECT",
                "cmd_params": {},
                "range_check": True,
                "raw": False,
            }
        )
        handle_build_cmd(build_cmd_json, "id-1", "DEFAULT")

        mock_topic.write_topic.assert_called_once()
        _, msg_hash = mock_topic.write_topic.call_args[0]
        self.assertEqual(msg_hash["buffer"], b"\x13\xe7\xc0\x00\x00\x00\x00\x01")
        self.assertIsInstance(msg_hash["buffer"], bytes)


if __name__ == "__main__":
    unittest.main()
