# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

require 'spec_helper'
require 'openc3/topics/telemetry_decom_topic'
require 'openc3/packets/packet'
require 'openc3/models/cvt_model'

module OpenC3
  describe TelemetryDecomTopic do
    before(:each) do
      mock_redis()
      allow(Topic).to receive(:write_topic)
      allow(CvtModel).to receive(:build_json_from_packet).and_return({ 'TEMP1' => 1.0 })
      allow(CvtModel).to receive(:set_json)
    end

    describe "self.write_packet" do
      let(:packet) do
        packet = Packet.new('TARGET', 'PKT')
        packet.received_time = Time.now
        packet.packet_time = Time.now
        packet.received_count = 5
        packet.stored = false
        packet
      end

      it "writes packet to correct decom topic" do
        expect(Topic).to receive(:write_topic).with(
          "DEFAULT__DECOM__{TARGET}__PKT",
          hash_including(
            target_name: 'TARGET',
            packet_name: 'PKT',
            received_count: 5,
            stored: 'false'
          ),
          nil,
          db_shard: 0
        )
        TelemetryDecomTopic.write_packet(packet, scope: 'DEFAULT')
      end

      it "includes extra field when packet.extra is set" do
        packet.extra = { 'foo' => 'bar', 'count' => 42 }
        expect(Topic).to receive(:write_topic) do |_topic, msg_hash, _id, _opts|
          expect(msg_hash[:extra]).to eq(JSON.generate({ 'foo' => 'bar', 'count' => 42 }))
        end
        TelemetryDecomTopic.write_packet(packet, scope: 'DEFAULT')
      end

      it "omits extra field when packet.extra is nil" do
        packet.extra = nil
        expect(Topic).to receive(:write_topic) do |_topic, msg_hash, _id, _opts|
          expect(msg_hash).not_to have_key(:extra)
        end
        TelemetryDecomTopic.write_packet(packet, scope: 'DEFAULT')
      end

      it "updates CVT when packet is not stored" do
        packet.stored = false
        expect(CvtModel).to receive(:set_json).with(
          kind_of(String), kind_of(Hash),
          target_name: 'TARGET', packet_name: 'PKT', scope: 'DEFAULT'
        )
        TelemetryDecomTopic.write_packet(packet, scope: 'DEFAULT')
      end

      it "skips CVT update when packet is stored" do
        packet.stored = true
        expect(CvtModel).not_to receive(:set_json)
        TelemetryDecomTopic.write_packet(packet, scope: 'DEFAULT')
      end

      it "passes include_limits_states to CvtModel.build_json_from_packet" do
        expect(CvtModel).to receive(:build_json_from_packet)
          .with(packet, include_limits_states: false)
          .and_return({ 'TEMP1' => 1.0 })
        TelemetryDecomTopic.write_packet(packet, include_limits_states: false, scope: 'DEFAULT')
      end

      it "defaults include_limits_states to true" do
        expect(CvtModel).to receive(:build_json_from_packet)
          .with(packet, include_limits_states: true)
          .and_return({ 'TEMP1' => 1.0 })
        TelemetryDecomTopic.write_packet(packet, scope: 'DEFAULT')
      end
    end
  end
end
