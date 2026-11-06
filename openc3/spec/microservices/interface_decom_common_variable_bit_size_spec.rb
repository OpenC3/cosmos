# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/microservices/interface_decom_common'

module OpenC3
  describe InterfaceDecomCommon do
    class InjectTlmVariableBitSizeHarness
      include InterfaceDecomCommon

      def initialize
        @scope = 'DEFAULT'
      end
    end

    before(:each) do
      @handler = InjectTlmVariableBitSizeHarness.new
      @packet = Packet.new('TGT', 'PKT', :BIG_ENDIAN)
      @packet.append_item('HDR', 8, :UINT)
      @packet.append_item('LEN', 8, :UINT)
      item = @packet.append_item('DATA', 0, :STRING)
      item.variable_bit_size = { 'length_item_name' => 'LEN', 'length_bits_per_count' => 8, 'length_value_bit_offset' => 0 }
      @packet.append_item('TRAILER', 8, :UINT)
      @packet.buffer = "\x00" * @packet.defined_length
      telemetry = double('Telemetry')
      allow(System).to receive(:telemetry).and_return(telemetry)
      allow(telemetry).to receive(:packet).with('TGT', 'PKT').and_return(@packet)
      allow(TargetModel).to receive(:increment_telemetry_count).and_return(1)
      allow(TelemetryTopic).to receive(:write_packet)
    end

    def inject(item_hash)
      @handler.handle_inject_tlm(JSON.generate({
        'target_name' => 'TGT',
        'packet_name' => 'PKT',
        'item_hash' => item_hash,
        'type' => 'CONVERTED'
      }))
    end

    def expect_packet(data)
      expect(@packet.read('HDR')).to eql 0xA5
      expect(@packet.read('LEN')).to eql data.length
      expect(@packet.read('DATA')).to eql data
      expect(@packet.read('TRAILER')).to eql 0x5A
      expect(@packet.buffer.length).to eql 3 + data.length
    end

    it 'sets the length item from the variable sized item across repeated injections' do
      # Sequence from https://github.com/OpenC3/cosmos/issues/4183
      inject({ 'HDR' => 0xA5, 'LEN' => 11, 'DATA' => 'hello world', 'TRAILER' => 0x5A })
      expect_packet('hello world')
      inject({ 'HDR' => 0xA5, 'DATA' => 'hello world', 'TRAILER' => 0x5A })
      expect_packet('hello world')
      inject({ 'HDR' => 0xA5, 'LEN' => 0, 'DATA' => '', 'TRAILER' => 0x5A })
      expect_packet('')
      inject({ 'HDR' => 0xA5, 'LEN' => 0, 'DATA' => 'hello world!', 'TRAILER' => 0x5A })
      expect_packet('hello world!')
      inject({ 'HDR' => 0xA5, 'LEN' => 0, 'DATA' => 'hello world!', 'TRAILER' => 0x5A })
      expect_packet('hello world!')
      inject({ 'HDR' => 0xA5, 'LEN' => 0, 'DATA' => '', 'TRAILER' => 0x5A })
      expect_packet('')
      inject({ 'HDR' => 0xA5, 'LEN' => 11, 'DATA' => 'hello world', 'TRAILER' => 0x5A })
      expect_packet('hello world')
    end

    it 'keeps the current variable sized item when only other items are given' do
      inject({ 'HDR' => 0xA5, 'DATA' => 'hello', 'TRAILER' => 0x5A })
      inject({ 'TRAILER' => 0x5A })
      expect_packet('hello')
    end

    it 'skips the length item regardless of case and hash order' do
      inject({ 'trailer' => 0x5A, 'len' => 3, 'hdr' => 0xA5, 'data' => 'hello' })
      expect_packet('hello')
    end
  end
end
