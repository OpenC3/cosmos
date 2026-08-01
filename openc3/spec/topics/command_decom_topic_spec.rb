# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

require 'spec_helper'
require 'openc3/topics/command_decom_topic'
require 'openc3/packets/packet'
require 'openc3/conversions/polynomial_conversion'

module OpenC3
  describe CommandDecomTopic do
    before(:each) do
      mock_redis()
      allow(EphemeralStoreQueued).to receive(:write_topic)
    end

    describe "self.write_packet" do
      # VALUE has a write conversion which doubles the given value so the
      # buffer never holds what the user actually commanded.
      # STATE only has states and thus reads back correctly from the buffer.
      let(:packet) do
        packet = Packet.new('TARGET', 'CMD')
        item = packet.append_item('VALUE', 16, :UINT)
        item.write_conversion = PolynomialConversion.new(0, 2)
        item = packet.append_item('STATE', 8, :UINT)
        item.states = { 'FALSE' => 0, 'TRUE' => 1 }
        packet.received_time = Time.now
        packet.packet_time = Time.now
        packet.received_count = 1
        packet.stored = false
        packet.write('VALUE', 5)
        packet.write('STATE', 'TRUE')
        packet
      end

      def json_data(packet)
        store_instance = EphemeralStoreQueued.instance(db_shard: 0)
        result = nil
        expect(store_instance).to receive(:write_topic) do |_topic, msg_hash|
          result = JSON.parse(msg_hash['json_data'], allow_nan: true)
        end
        CommandDecomTopic.write_packet(packet, scope: 'DEFAULT')
        result
      end

      it "writes packet to correct topic format" do
        store_instance = EphemeralStoreQueued.instance(db_shard: 0)
        expect(store_instance).to receive(:write_topic).with(
          "DEFAULT__DECOMCMD__{TARGET}__CMD",
          hash_including(
            target_name: 'TARGET',
            packet_name: 'CMD',
            received_count: 1,
            stored: 'false'
          )
        )
        CommandDecomTopic.write_packet(packet, scope: 'DEFAULT')
      end

      it "logs the given value for items with a write conversion" do
        packet.given_values = { 'VALUE' => 5, 'STATE' => 'TRUE' }
        hash = json_data(packet)
        expect(hash['VALUE']).to eq(10) # raw value in the buffer
        expect(hash['VALUE__C']).to eq(5) # value the user commanded
      end

      it "matches given values regardless of key case" do
        packet.given_values = { 'value' => 5 }
        hash = json_data(packet)
        expect(hash['VALUE__C']).to eq(5)
      end

      it "reads the converted value when the item was not given" do
        packet.given_values = { 'STATE' => 'TRUE' }
        hash = json_data(packet)
        expect(hash['VALUE__C']).to eq(10)
      end

      it "reads the converted value when there are no given values" do
        expect(packet.given_values).to be_nil
        hash = json_data(packet)
        expect(hash['VALUE__C']).to eq(10)
      end

      it "reads the converted state value rather than the given value" do
        # The user can give either the state name or the state value so always
        # read the state name back out of the buffer
        packet.given_values = { 'STATE' => 1 }
        hash = json_data(packet)
        expect(hash['STATE']).to eq(1)
        expect(hash['STATE__C']).to eq('TRUE')
      end

      it "ignores given values for raw commands" do
        # Raw commands skip the write conversion so the given value is the raw value
        packet.raw = true
        packet.write('VALUE', 10, :RAW)
        # Deliberately different from the buffer to prove the buffer wins
        packet.given_values = { 'VALUE' => 99 }
        hash = json_data(packet)
        expect(hash['VALUE']).to eq(10)
        expect(hash['VALUE__C']).to eq(10)
      end

      it "removes hidden items" do
        packet.get_item('STATE').hidden = true
        hash = json_data(packet)
        expect(hash).not_to have_key('STATE')
        expect(hash).not_to have_key('STATE__C')
      end
    end
  end
end
