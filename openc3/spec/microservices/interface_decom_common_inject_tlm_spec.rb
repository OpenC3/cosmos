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
    class InjectTlmVariableSizeHarness
      include InterfaceDecomCommon

      def initialize
        @scope = 'DEFAULT'
      end
    end

    before(:each) do
      @handler = InjectTlmVariableSizeHarness.new
      # Packet from https://github.com/OpenC3/cosmos/issues/4185
      @packet = Packet.new('FTGT', 'PKT', :BIG_ENDIAN)
      @packet.append_item('HDR', 8, :UINT)
      @packet.append_item('LEN', 8, :UINT)
      data = @packet.append_item('DATA', 32, :FLOAT, 0)
      data.variable_bit_size = { 'length_item_name' => 'LEN', 'length_value_bit_offset' => 0, 'length_bits_per_count' => 32 }
      @packet.append_item('TRAILER', 8, :UINT)
      @packet.buffer = "\x00" * @packet.defined_length
      telemetry = double('Telemetry')
      allow(System).to receive(:telemetry).and_return(telemetry)
      allow(telemetry).to receive(:packet).with('FTGT', 'PKT').and_return(@packet)
      allow(TargetModel).to receive(:increment_telemetry_count).and_return(1)
      allow(TelemetryTopic).to receive(:write_packet)
    end

    def inject(item_hash)
      inject_tlm = { 'target_name' => 'FTGT', 'packet_name' => 'PKT', 'item_hash' => item_hash, 'type' => 'CONVERTED' }
      @handler.handle_inject_tlm(JSON.generate(inject_tlm, allow_nan: true))
    end

    it 'writes a variable sized array when the length item is given before it' do
      [[-2.5, 5.0, 3.5], [1.5, 3.0, 4.5, 6.0, 7.5], [-2.5, 5.0, 3.5]].each do |values|
        inject({ 'HDR' => 0xA5, 'LEN' => values.length, 'DATA' => values, 'TRAILER' => 0x5A })
        expect(@packet.buffer).to eql "\xA5" + [values.length].pack('C') + values.pack('g*') + "\x5A"
        expect(@packet.read('LEN')).to eql values.length
        expect(@packet.read('DATA')).to eql values
        expect(@packet.read('TRAILER')).to eql 0x5A
      end
    end

    it 'writes a length item when its variable sized item is not given' do
      inject({ 'HDR' => 0xA5, 'DATA' => [1.5], 'TRAILER' => 0x5A })
      inject({ 'len' => 0 })
      expect(@packet.read('LEN')).to eql 0
    end
  end
end
