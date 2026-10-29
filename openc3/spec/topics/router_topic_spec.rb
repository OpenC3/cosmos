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
require 'openc3/topics/router_topic'
require 'openc3/models/target_model'
require 'openc3/packets/packet'

module OpenC3
  describe RouterTopic do
    before(:each) do
      mock_redis()
    end

    describe "route_command" do
      it "routes an identified command to its target" do
        packet = Packet.new("INST", "ABORT")
        packet.buffer = "\x01\x02"
        expect(Topic).to receive(:write_topic).with("{DEFAULT__CMD}TARGET__INST",
          { 'target_name' => 'INST', 'cmd_name' => 'ABORT', 'cmd_buffer' => "\x01\x02" }, '*', 100, db_shard: 0)
        RouterTopic.route_command(packet, ["INST", "INST2"], scope: "DEFAULT")
      end

      it "routes an unidentified command to the only target, naming that target" do
        packet = Packet.new(nil, nil)
        packet.buffer = "\x01\x02"
        expect(Topic).to receive(:write_topic).with("{DEFAULT__CMD}TARGET__INST",
          { 'target_name' => 'INST', 'cmd_name' => 'UNKNOWN', 'cmd_buffer' => "\x01\x02" }, '*', 100, db_shard: 0)
        RouterTopic.route_command(packet, ["INST"], scope: "DEFAULT")
      end

      it "raises if an unidentified command has more than one possible target" do
        packet = Packet.new(nil, nil)
        packet.buffer = "\x01\x02"
        expect { RouterTopic.route_command(packet, ["INST", "INST2"], scope: "DEFAULT") }.to raise_error(/No route for command/)
      end
    end
  end

  describe RouterTopic, "multiple db_shards" do
    before(:each) do
      mock_redis()
      setup_system()
      # INST lives on db_shard 1 while SYSTEM and the router stay on db_shard 0
      TargetModel.new(name: "INST", scope: "DEFAULT", db_shard: 1).create
      TargetModel.new(name: "SYSTEM", scope: "DEFAULT", db_shard: 0).create
    end

    it "routes a command to the target's db_shard" do
      packet = Packet.new("INST", "ABORT")
      packet.buffer = "\x01\x02"
      RouterTopic.route_command(packet, ["INST"], scope: "DEFAULT")
      _, msg_hash = EphemeralStore.instance(db_shard: 1).get_newest_message("{DEFAULT__CMD}TARGET__INST")
      expect(msg_hash['cmd_name']).to eql 'ABORT'
      expect(EphemeralStore.instance(db_shard: 0).exists?("{DEFAULT__CMD}TARGET__INST")).to be false
    end

    it "receives telemetry from each target's db_shard" do
      router = Struct.new(:name, :tlm_target_names).new("ROUTER_INT", %w(INST SYSTEM))
      received = Queue.new
      thread = Thread.new do
        RouterTopic.receive_telemetry(router, scope: "DEFAULT", db_shard: 0) do |topic, _msg_id, _msg_hash, _redis|
          received << topic
          nil
        end
      end
      begin
        # Each db_shard only starts reading once the read on the other times out
        # so keep writing until the router has seen a packet from both
        topics = []
        start = Time.now
        while topics.uniq.length < 2 and (Time.now - start) < 5
          EphemeralStore.instance(db_shard: 1).write_topic("DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS", { 'packet_name' => 'HEALTH_STATUS' })
          EphemeralStore.instance(db_shard: 0).write_topic("DEFAULT__TELEMETRY__{SYSTEM}__META", { 'packet_name' => 'META' })
          sleep 0.2
          topics << received.pop until received.empty?
        end
        expect(topics.uniq).to contain_exactly("DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS", "DEFAULT__TELEMETRY__{SYSTEM}__META")
      ensure
        thread.kill
        thread.join
      end
    end
  end
end
