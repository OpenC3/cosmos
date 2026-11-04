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

"""HMAC-SHA256 signing of script control messages.

CROSS-LANGUAGE CONTRACT: this is the twin of
openc3/lib/openc3/utilities/script_message_signing.rb and must produce
byte-identical output. The signed string is:

    canonical(payload) + ":" + nonce

canonical(payload) is JSON, UTF-8, non-ASCII NOT escaped, object keys sorted
bytewise (recursively, after stringifying keys), no insignificant whitespace.
Payloads may contain only str, int, bool, None, list and dict. Floats are
rejected because their text form differs between languages.

    sig = lowercase hex(HMAC_SHA256(signing_key, signed string))
    nonce = 32 lowercase hex chars (16 random bytes)
Envelope: {"payload": ..., "nonce": ..., "sig": ...}
"""

import hashlib
import hmac
import json
import secrets


def canonical(payload):
    # UTF-8 byte order == Unicode code-point order, so bytewise (Ruby) and code-point (Python) key sorting produce identical canonical output.
    return json.dumps(_normalize(payload), sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sign(signing_key, payload):
    nonce = secrets.token_hex(16)
    return {"payload": payload, "nonce": nonce, "sig": _compute_sig(signing_key, payload, nonce)}


def verify(signing_key, envelope):
    """Pure signature check. Replay protection is the caller's concern.
    Returns False (never raises) on any malformed input or mismatch."""
    try:
        if not isinstance(envelope, dict):
            return False
        if not signing_key or not isinstance(signing_key, str):
            return False
        if "payload" not in envelope:
            return False
        nonce = envelope.get("nonce")
        sig = envelope.get("sig")
        if not isinstance(nonce, str) or not nonce:
            return False
        if not isinstance(sig, str) or not sig:
            return False
        expected = _compute_sig(signing_key, envelope["payload"], nonce)
        return hmac.compare_digest(sig.encode("utf-8"), expected.encode("utf-8"))
    except Exception:
        return False


class NonceCache:
    """Bounded FIFO set of seen nonces for replay protection."""

    DEFAULT_MAX = 10_000

    def __init__(self, max_size=DEFAULT_MAX):
        self._max = max_size
        self._set = {}  # dict preserves insertion order: oldest first

    def include(self, nonce):
        return nonce in self._set

    def add(self, nonce):
        if nonce in self._set:
            return
        while len(self._set) >= self._max and self._set:
            del self._set[next(iter(self._set))]
        self._set[nonce] = True

    def size(self):
        return len(self._set)


def accept(signing_key, raw_json, seen_nonces):
    """Parse and verify a raw JSON control message and enforce replay protection.
    Returns (accepted, payload). Never raises. payload is None when the envelope
    is invalid; on a replay it is the payload but accepted is False."""
    try:
        envelope = json.loads(raw_json)
        if not verify(signing_key, envelope):
            return (False, None)
        nonce = envelope["nonce"]
        if seen_nonces.include(nonce):
            return (False, envelope["payload"])
        seen_nonces.add(nonce)
        return (True, envelope["payload"])
    except Exception:
        return (False, None)


def _compute_sig(signing_key, payload, nonce):
    message = f"{canonical(payload)}:{nonce}"
    return hmac.new(str(signing_key).encode("utf-8"), message.encode("utf-8"), hashlib.sha256).hexdigest()


def _key_to_str(key):
    # Match Ruby's Object#to_s for the common key types
    if key is True:
        return "true"
    if key is False:
        return "false"
    if key is None:
        return ""
    return str(key)


def _normalize(obj):
    if isinstance(obj, dict):
        return {_key_to_str(k): _normalize(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [_normalize(v) for v in obj]
    if isinstance(obj, float):
        raise ValueError("unsupported float in signed payload")
    return obj
