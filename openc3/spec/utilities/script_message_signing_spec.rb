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

require 'spec_helper'
require 'openc3/utilities/script_message_signing'

module OpenC3
  describe ScriptMessageSigning, no_ext: true do
    let(:key) { 'a' * 64 }

    it 'round-trips a hash payload' do
      env = described_class.sign(key, { 'method' => 'debug', 'args' => 'x' })
      expect(described_class.verify(key, env)).to be true
    end

    it 'round-trips a string payload' do
      expect(described_class.verify(key, described_class.sign(key, 'stop'))).to be true
    end

    it 'returns the envelope shape with a 32 hex nonce and lowercase hex sig' do
      env = described_class.sign(key, 'stop')
      expect(env.keys).to eq(%w[payload nonce sig])
      expect(env['nonce']).to match(/\A[0-9a-f]{32}\z/)
      expect(env['sig']).to match(/\A[0-9a-f]{64}\z/)
    end

    it 'rejects a tampered payload' do
      env = described_class.sign(key, 'stop')
      env['payload'] = 'go'
      expect(described_class.verify(key, env)).to be false
    end

    it 'rejects a tampered nonce' do
      env = described_class.sign(key, 'stop')
      env['nonce'] = '0' * 32
      expect(described_class.verify(key, env)).to be false
    end

    it 'rejects a wrong key' do
      expect(described_class.verify('b' * 64, described_class.sign(key, 'stop'))).to be false
    end

    it 'rejects a short or non-string sig without raising' do
      env = described_class.sign(key, 'stop')
      expect(described_class.verify(key, env.merge('sig' => 'abc'))).to be false
      expect(described_class.verify(key, env.merge('sig' => 5))).to be false
    end

    it 'returns false (no raise) on missing or blank fields' do
      expect(described_class.verify(key, { 'payload' => 'stop' })).to be false
      env = described_class.sign(key, 'stop')
      expect(described_class.verify(key, env.merge('nonce' => ''))).to be false
      expect(described_class.verify(key, env.merge('sig' => nil))).to be false
      expect(described_class.verify(key, nil)).to be false
      expect(described_class.verify(key, 'stop')).to be false
      expect(described_class.verify('', env)).to be false
      expect(described_class.verify(nil, env)).to be false
    end

    it 'canonical sorts object keys deterministically' do
      expect(described_class.canonical({ 'b' => 1, 'a' => 2 })).to eq('{"a":2,"b":1}')
    end

    it 'canonical sorts nested keys and serializes strings with quotes' do
      expect(described_class.canonical('stop')).to eq('"stop"')
      expect(described_class.canonical({ 'z' => [{ 'y' => 1, 'x' => 2 }], 'a' => nil })).to eq('{"a":null,"z":[{"x":2,"y":1}]}')
    end

    # Literal cross-language vectors: the Python twin must assert these same values
    describe 'pinned vectors' do
      before { allow(SecureRandom).to receive(:hex).with(16).and_return('0' * 32) }

      it 'signs a hash payload to the pinned value' do
        env = described_class.sign(key, { 'method' => 'debug', 'args' => 'x' })
        expect(env['sig']).to eq('6df099d6f40be0a6cdb58038f4ca144d71756705452ece4c754321aa394412f6')
      end

      it 'signs a non-ASCII payload to the pinned value' do
        env = described_class.sign(key, "caf\u00e9")
        expect(env['sig']).to eq('eeb9878f9486bd18406ce7f25d0ecbfe04aabab415dc1b22034789871a4c4951')
        expect(described_class.canonical("caf\u00e9")).to eq("\"caf\u00e9\"")
      end

      it 'signs a payload with a non-ASCII object key to the pinned value' do
        payload = { "\u00e9" => 1, 'a' => 2, 'z' => 3 }
        expect(described_class.canonical(payload)).to eq("{\"a\":2,\"z\":3,\"\u00e9\":1}")
        env = described_class.sign(key, payload)
        expect(env['sig']).to eq('7edd9b1fcbc5e514feeabf7e8e8af625fdfe6616c2c3faa64ea0d4445e90a826')
      end
    end

    it 'raises on Float payloads in canonical and sign, and verify fails closed' do
      expect { described_class.canonical({ 'a' => [1.5] }) }.to raise_error(ArgumentError, /Float/)
      expect { described_class.sign(key, 1.0e20) }.to raise_error(ArgumentError, /Float/)
      env = described_class.sign(key, 'stop')
      env['payload'] = 1.5
      expect(described_class.verify(key, env)).to be false
    end

    it 'stringifies non-String keys' do
      expect(described_class.canonical({ 1 => 'x', :b => 2 })).to eq('{"1":"x","b":2}')
    end

    it 'rejects an uppercase-hex sig' do
      env = described_class.sign(key, 'stop')
      env['sig'] = env['sig'].upcase
      expect(described_class.verify(key, env)).to be false
    end

  describe '.accept?' do
    let(:key) { 'k' * 64 }
    let(:seen) { described_class::NonceCache.new }

    it 'accepts a valid envelope and returns the payload' do
      raw = JSON.generate(described_class.sign(key, 'stop'))
      expect(described_class.accept?(key, raw, seen)).to eq([true, 'stop'])
    end

    it 'rejects a replayed nonce' do
      raw = JSON.generate(described_class.sign(key, 'stop'))
      expect(described_class.accept?(key, raw, seen)).to eq([true, 'stop'])
      accepted, = described_class.accept?(key, raw, seen)
      expect(accepted).to be false
    end

    it 'rejects a bad signature without recording the nonce' do
      env = described_class.sign(key, 'stop')
      env['sig'] = '0' * 64
      expect(described_class.accept?(key, JSON.generate(env), seen)).to eq([false, nil])
      expect(seen.size).to eq(0)
    end

    it 'rejects an envelope signed with another key' do
      raw = JSON.generate(described_class.sign('z' * 64, 'stop'))
      expect(described_class.accept?(key, raw, seen)).to eq([false, nil])
    end

    it 'rejects non-JSON, non-envelope and missing fields without raising' do
      ['not json', '', nil, '"stop"', '[]', '{}', '{"payload":"stop"}', '{"payload":"stop","nonce":"a"}'].each do |raw|
        expect(described_class.accept?(key, raw, seen)).to eq([false, nil])
      end
    end

    it 'bounds the nonce cache and evicts the oldest' do
      cap = described_class::NonceCache::DEFAULT_MAX
      cache = described_class::NonceCache.new(3)
      %w[a b c d].each { |n| cache.add(n) }
      expect(cache.size).to eq(3)
      expect(cache.include?('a')).to be false
      expect(cache.include?('d')).to be true
      expect(cap).to eq(10_000)
    end

    it 'stays bounded when fed more than the cap through accept?' do
      small = described_class::NonceCache.new(5)
      first = JSON.generate(described_class.sign(key, 'go'))
      described_class.accept?(key, first, small)
      10.times { described_class.accept?(key, JSON.generate(described_class.sign(key, 'go')), small) }
      expect(small.size).to eq(5)
      expect(small.include?(JSON.parse(first)['nonce'])).to be false
    end
  end

  # Regression for the original PoC: an operator-privileged process forged
  # control messages (a `debug` eval and a `stop`) on ANOTHER script's
  # cmd-running-script-channel. The child only acts on what accept? approves.
  describe 'forged control message regression (PoC)' do
    let(:key) { 'k' * 64 }
    let(:seen) { ScriptMessageSigning::NonceCache.new }

    it 'drops a forged debug envelope signed with a guessed key' do
      forged = JSON.generate(ScriptMessageSigning.sign('x' * 64, { 'method' => 'debug', 'args' => 'File.write("/tmp/pwn","1")' }))
      accepted, = ScriptMessageSigning.accept?(key, forged, seen)
      expect(accepted).to be false
      expect(seen.size).to eq(0)
    end

    it 'drops legacy unsigned debug and stop messages' do
      legacy_debug = JSON.generate({ 'method' => 'debug', 'args' => 'puts 1' })
      expect(ScriptMessageSigning.accept?(key, legacy_debug, seen)).to eq([false, nil])
      expect(ScriptMessageSigning.accept?(key, '"stop"', seen)).to eq([false, nil])
      no_sig = JSON.generate({ 'payload' => 'stop', 'nonce' => 'a' * 32 })
      expect(ScriptMessageSigning.accept?(key, no_sig, seen)).to eq([false, nil])
    end

    it 'ignores a forged stop but accepts a controller-signed stop' do
      forged = JSON.generate({ 'payload' => 'stop', 'nonce' => 'b' * 32, 'sig' => '0' * 64 })
      expect(ScriptMessageSigning.accept?(key, forged, seen)).to eq([false, nil])
      signed = JSON.generate(ScriptMessageSigning.sign(key, 'stop'))
      expect(ScriptMessageSigning.accept?(key, signed, seen)).to eq([true, 'stop'])
    end

    it 'drops a replay of a captured signed message' do
      signed = JSON.generate(ScriptMessageSigning.sign(key, { 'method' => 'debug', 'args' => 'puts 1' }))
      accepted, = ScriptMessageSigning.accept?(key, signed, seen)
      expect(accepted).to be true
      accepted, = ScriptMessageSigning.accept?(key, signed, seen)
      expect(accepted).to be false
    end
  end
end
end
