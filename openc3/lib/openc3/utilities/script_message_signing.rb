# encoding: ascii-8bit

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

require 'json'
require 'openssl'
require 'securerandom'

module OpenC3
  # HMAC-SHA256 signing of script control messages.
  #
  # CROSS-LANGUAGE CONTRACT: the Python twin (openc3/script_message_signing.py)
  # must produce byte-identical output. Signed string is:
  #
  #   canonical(payload) + ":" + nonce
  #
  # canonical(payload) is JSON, UTF-8, non-ASCII NOT escaped, object keys
  # sorted bytewise (recursively), no insignificant whitespace. So
  # canonical("stop") is "\"stop\"" including the quotes. The exact matching
  # Python call is:
  #   json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
  #
  # Signed payloads may contain only String, Integer, true/false, nil, Array
  # and Hash. Floats are rejected (ArgumentError) because their text form
  # differs between languages. sign may also raise on binary-encoded
  # (ascii-8bit) strings containing high bytes; verify returns false for them.
  #
  #   sig = lowercase hex(HMAC_SHA256(signing_key, signed string))
  #   Uppercase-hex sigs are rejected by verify.
  #   nonce = 32 lowercase hex chars (16 random bytes)
  # Envelope: { "payload" => ..., "nonce" => ..., "sig" => ... }
  module ScriptMessageSigning
    def self.canonical(payload)
      JSON.generate(sort_keys(payload))
    end

    def self.sign(signing_key, payload)
      nonce = SecureRandom.hex(16)
      { 'payload' => payload, 'nonce' => nonce, 'sig' => compute_sig(signing_key, payload, nonce) }
    end

    # Pure signature check. Replay protection is the caller's concern.
    # Returns false (never raises) on any malformed input or mismatch.
    def self.verify(signing_key, envelope)
      return false unless envelope.is_a?(Hash)
      return false if signing_key.to_s.empty?
      return false unless envelope.key?('payload')
      nonce = envelope['nonce']
      sig = envelope['sig']
      return false unless nonce.is_a?(String) && !nonce.empty?
      return false unless sig.is_a?(String) && !sig.empty?
      expected = compute_sig(signing_key, envelope['payload'], nonce)
      return false unless sig.bytesize == expected.bytesize
      OpenSSL.fixed_length_secure_compare(sig, expected)
    rescue StandardError
      false
    end

    # Bounded FIFO set of seen nonces for replay protection.
    class NonceCache
      DEFAULT_MAX = 10_000

      def initialize(max = DEFAULT_MAX)
        @max = max
        @set = {}
      end

      def include?(nonce)
        @set.key?(nonce)
      end

      def add(nonce)
        return if @set.key?(nonce)
        @set.shift while @set.size >= @max # Hash preserves insertion order: oldest first
        @set[nonce] = true
      end

      def size
        @set.size
      end
    end

    # Parse and verify a raw JSON control message and enforce replay protection.
    # Returns [accepted, payload]. Never raises. payload is nil when the
    # envelope is invalid; on a replay it is the payload but accepted is false.
    def self.accept?(signing_key, raw_json, seen_nonces)
      envelope = JSON.parse(raw_json, allow_nan: true)
      return [false, nil] unless verify(signing_key, envelope)
      nonce = envelope['nonce']
      return [false, envelope['payload']] if seen_nonces.include?(nonce)
      seen_nonces.add(nonce)
      [true, envelope['payload']]
    rescue StandardError
      [false, nil]
    end

    def self.compute_sig(signing_key, payload, nonce)
      OpenSSL::HMAC.hexdigest('SHA256', signing_key.to_s, "#{canonical(payload)}:#{nonce}")
    end
    private_class_method :compute_sig

    def self.sort_keys(obj)
      case obj
      when Hash
        # UTF-8 byte order == Unicode code-point order, so bytewise (Ruby) and code-point (Python) key sorting produce identical canonical output.
        obj.map { |k, v| [k.to_s, sort_keys(v)] }.sort_by { |k, _| k.b }.to_h
      when Array
        obj.map { |v| sort_keys(v) }
      when Float
        raise ArgumentError, 'unsupported Float in signed payload'
      else
        obj
      end
    end
    private_class_method :sort_keys
  end
end
