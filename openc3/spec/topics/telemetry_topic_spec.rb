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
require 'openc3/topics/telemetry_topic'
require 'openc3/packets/packet'

module OpenC3
  describe TelemetryTopic do
    describe "self.write_packet" do
      let(:packet) do
        packet = Packet.new('TARGET', 'PACKET')
        packet.received_time = Time.now
        packet.packet_time = Time.now
        packet.received_count = 1
        packet
      end

      before(:each) do
        mock_redis()
        allow(Store).to receive(:db_shard_for_target).and_return(3)
      end

      it "writes to the queued store for the target shard" do
        queued_store = double("queued store")
        expect(EphemeralStoreQueued).to receive(:instance).with(db_shard: 3).and_return(queued_store)
        expect(queued_store).to receive(:write_topic).with("DEFAULT__TELEMETRY__{TARGET}__PACKET", hash_including(target_name: 'TARGET'))
        TelemetryTopic.write_packet(packet, queued: true, scope: 'DEFAULT')
      end

      it "writes directly to the target shard when not queued" do
        expect(EphemeralStoreQueued).not_to receive(:instance)
        expect(Topic).to receive(:write_topic).with("DEFAULT__TELEMETRY__{TARGET}__PACKET", hash_including(target_name: 'TARGET'), db_shard: 3)
        TelemetryTopic.write_packet(packet, scope: 'DEFAULT')
      end
    end
  end
end
