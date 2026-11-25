# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.md
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
import re
import unittest
from unittest.mock import patch

from openc3.utilities import script_message_signing as sms


class TestScriptMessageSigning(unittest.TestCase):
    def setUp(self):
        self.key = "a" * 64

    def test_round_trips_a_hash_payload(self):
        env = sms.sign(self.key, {"method": "debug", "args": "x"})
        self.assertTrue(sms.verify(self.key, env))

    def test_round_trips_a_string_payload(self):
        self.assertTrue(sms.verify(self.key, sms.sign(self.key, "stop")))

    def test_envelope_shape(self):
        env = sms.sign(self.key, "stop")
        self.assertEqual(list(env.keys()), ["payload", "nonce", "sig"])
        self.assertTrue(re.fullmatch(r"[0-9a-f]{32}", env["nonce"]))
        self.assertTrue(re.fullmatch(r"[0-9a-f]{64}", env["sig"]))

    def test_rejects_tampered_payload(self):
        env = sms.sign(self.key, "stop")
        env["payload"] = "go"
        self.assertFalse(sms.verify(self.key, env))

    def test_rejects_tampered_nonce(self):
        env = sms.sign(self.key, "stop")
        env["nonce"] = "0" * 32
        self.assertFalse(sms.verify(self.key, env))

    def test_rejects_wrong_key(self):
        self.assertFalse(sms.verify("b" * 64, sms.sign(self.key, "stop")))

    def test_rejects_short_or_non_string_sig(self):
        env = sms.sign(self.key, "stop")
        self.assertFalse(sms.verify(self.key, {**env, "sig": "abc"}))
        self.assertFalse(sms.verify(self.key, {**env, "sig": 5}))

    def test_missing_or_blank_fields_return_false(self):
        self.assertFalse(sms.verify(self.key, {"payload": "stop"}))
        env = sms.sign(self.key, "stop")
        self.assertFalse(sms.verify(self.key, {**env, "nonce": ""}))
        self.assertFalse(sms.verify(self.key, {**env, "nonce": 5}))
        self.assertFalse(sms.verify(self.key, {**env, "sig": None}))
        self.assertFalse(sms.verify(self.key, {"nonce": env["nonce"], "sig": env["sig"]}))
        self.assertFalse(sms.verify(self.key, None))
        self.assertFalse(sms.verify(self.key, "stop"))
        self.assertFalse(sms.verify("", env))
        self.assertFalse(sms.verify(None, env))

    def test_canonical_sorts_keys(self):
        self.assertEqual(sms.canonical({"b": 1, "a": 2}), '{"a":2,"b":1}')

    def test_canonical_nested_and_string(self):
        self.assertEqual(sms.canonical("stop"), '"stop"')
        self.assertEqual(
            sms.canonical({"z": [{"y": 1, "x": 2}], "a": None}),
            '{"a":null,"z":[{"x":2,"y":1}]}',
        )

    def test_canonical_bools(self):
        self.assertEqual(sms.canonical({"t": True, "f": False}), '{"f":false,"t":true}')

    def test_canonical_stringifies_non_string_keys(self):
        self.assertEqual(sms.canonical({1: "x", "b": 2}), '{"1":"x","b":2}')

    def test_pinned_cross_language_vectors(self):
        # Literal values computed from the Ruby module (script_message_signing_spec.rb)
        with patch("openc3.utilities.script_message_signing.secrets.token_hex", return_value="0" * 32):
            env = sms.sign(self.key, {"method": "debug", "args": "x"})
            self.assertEqual(env["sig"], "6df099d6f40be0a6cdb58038f4ca144d71756705452ece4c754321aa394412f6")
            env = sms.sign(self.key, "café")
            self.assertEqual(env["sig"], "eeb9878f9486bd18406ce7f25d0ecbfe04aabab415dc1b22034789871a4c4951")
        self.assertEqual(sms.canonical("café"), '"café"')

    def test_pinned_non_ascii_object_key_vector(self):
        # Literal computed from the Ruby module; non-ASCII KEY forces an ordering decision
        payload = {"é": 1, "a": 2, "z": 3}
        self.assertEqual(sms.canonical(payload), '{"a":2,"z":3,"é":1}')
        with patch("openc3.utilities.script_message_signing.secrets.token_hex", return_value="0" * 32):
            env = sms.sign(self.key, payload)
        self.assertEqual(env["sig"], "7edd9b1fcbc5e514feeabf7e8e8af625fdfe6616c2c3faa64ea0d4445e90a826")

    def test_floats_raise_and_verify_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "float"):
            sms.canonical({"a": [1.5]})
        with self.assertRaisesRegex(ValueError, "float"):
            sms.sign(self.key, 1.0e20)
        env = sms.sign(self.key, "stop")
        env["payload"] = 1.5
        self.assertFalse(sms.verify(self.key, env))

    def test_rejects_uppercase_hex_sig(self):
        env = sms.sign(self.key, "stop")
        env["sig"] = env["sig"].upper()
        self.assertFalse(sms.verify(self.key, env))


class TestAccept(unittest.TestCase):
    def setUp(self):
        self.key = "a" * 64
        self.seen = sms.NonceCache()

    def raw(self, payload):
        return json.dumps(sms.sign(self.key, payload))

    def test_accepts_valid_message(self):
        ok, payload = sms.accept(self.key, self.raw("stop"), self.seen)
        self.assertTrue(ok)
        self.assertEqual(payload, "stop")

    def test_rejects_replay(self):
        raw = self.raw({"method": "debug", "args": "x"})
        self.assertTrue(sms.accept(self.key, raw, self.seen)[0])
        ok, payload = sms.accept(self.key, raw, self.seen)
        self.assertFalse(ok)
        self.assertEqual(payload, {"method": "debug", "args": "x"})

    def test_rejects_bad_signature_without_recording_nonce(self):
        env = sms.sign(self.key, "stop")
        forged = dict(env, sig="0" * 64)
        ok, payload = sms.accept(self.key, json.dumps(forged), self.seen)
        self.assertFalse(ok)
        self.assertIsNone(payload)
        self.assertEqual(self.seen.size(), 0)
        # The genuine message with the same nonce is still accepted
        self.assertTrue(sms.accept(self.key, json.dumps(env), self.seen)[0])

    def test_rejects_wrong_key(self):
        self.assertFalse(sms.accept("b" * 64, self.raw("stop"), self.seen)[0])

    def test_malformed_input_never_raises(self):
        for raw in [
            "not json",
            "",
            None,
            "[]",
            "{}",
            '{"payload":"stop"}',
            '{"payload":"stop","nonce":"n"}',
            '"shutdown"',
        ]:
            self.assertEqual(sms.accept(self.key, raw, self.seen), (False, None))

    def test_nonce_cache_is_bounded_fifo(self):
        cache = sms.NonceCache(3)
        for n in ["a", "b", "c", "d"]:
            cache.add(n)
        self.assertEqual(cache.size(), 3)
        self.assertFalse(cache.include("a"))
        for n in ["b", "c", "d"]:
            self.assertTrue(cache.include(n))
        cache.add("d")
        self.assertEqual(cache.size(), 3)

    def test_default_max(self):
        self.assertEqual(sms.NonceCache.DEFAULT_MAX, 10_000)

    def test_replay_rejected_until_evicted(self):
        cache = sms.NonceCache(1)
        first = self.raw("stop")
        self.assertTrue(sms.accept(self.key, first, cache)[0])
        self.assertTrue(sms.accept(self.key, self.raw("go"), cache)[0])  # evicts first
        self.assertTrue(sms.accept(self.key, first, cache)[0])


class TestForgedControlMessageRegression(unittest.TestCase):
    """Regression for the original PoC: an operator-privileged process forged
    control messages (a debug eval and a stop) on ANOTHER script's
    cmd-running-script-channel. The child only acts on what accept() approves."""

    def setUp(self):
        self.key = "k" * 64
        self.seen = sms.NonceCache()

    def test_drops_forged_debug_signed_with_guessed_key(self):
        forged = json.dumps(sms.sign("x" * 64, {"method": "debug", "args": "open('/tmp/pwn','w')"}))
        accepted, _ = sms.accept(self.key, forged, self.seen)
        self.assertFalse(accepted)
        self.assertEqual(self.seen.size(), 0)

    def test_drops_legacy_unsigned_messages(self):
        self.assertEqual(sms.accept(self.key, json.dumps({"method": "debug", "args": "1"}), self.seen), (False, None))
        self.assertEqual(sms.accept(self.key, '"stop"', self.seen), (False, None))
        no_sig = json.dumps({"payload": "stop", "nonce": "a" * 32})
        self.assertEqual(sms.accept(self.key, no_sig, self.seen), (False, None))

    def test_ignores_forged_stop_but_accepts_signed_stop(self):
        forged = json.dumps({"payload": "stop", "nonce": "b" * 32, "sig": "0" * 64})
        self.assertEqual(sms.accept(self.key, forged, self.seen), (False, None))
        signed = json.dumps(sms.sign(self.key, "stop"))
        self.assertEqual(sms.accept(self.key, signed, self.seen), (True, "stop"))

    def test_drops_replay_of_captured_signed_message(self):
        signed = json.dumps(sms.sign(self.key, {"method": "debug", "args": "1"}))
        self.assertTrue(sms.accept(self.key, signed, self.seen)[0])
        self.assertFalse(sms.accept(self.key, signed, self.seen)[0])


if __name__ == "__main__":
    unittest.main()
