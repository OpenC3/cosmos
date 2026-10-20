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
    class DbShardAckHarness
      include InterfaceDecomCommon

      def initialize
        @scope = 'DEFAULT'
        @logger = Logger
      end
    end

    before(:each) do
      mock_redis_db_shards()
      # The ack must go to the db_shard of the target where DecomInterfaceTopic waits for it
      set_target_db_shard('INST2', 2)
      @handler = DbShardAckHarness.new
      @packet = double('Packet', target_name: 'INST2', packet_name: 'HEALTH_STATUS', packet_time: Time.now,
                                 received_time: Time.now, received_count: 1, stored: false, extra: nil)
      allow(@packet).to receive(:buffer).and_return("\x00")
      allow(@packet).to receive(:stored=)
      allow(@packet).to receive(:received_time=)
      allow(@packet).to receive(:received_count=)
      telemetry = double('Telemetry')
      allow(System).to receive(:telemetry).and_return(telemetry)
      allow(telemetry).to receive(:packet).with('INST2', 'HEALTH_STATUS').and_return(@packet)
      commands = double('Commands')
      allow(System).to receive(:commands).and_return(commands)
      allow(commands).to receive(:build_cmd).and_return(@packet)
      allow(TargetModel).to receive(:increment_telemetry_count).and_return(1)
      allow(TelemetryTopic).to receive(:write_packet)
    end

    def ack(db_shard)
      Topic.get_newest_message('{DEFAULT__ACKCMD}TARGET__INST2', db_shard: db_shard)&.last
    end

    it "acks inject_tlm on the db_shard of the target" do
      @handler.handle_inject_tlm_with_ack(JSON.generate({ 'target_name' => 'INST2', 'packet_name' => 'HEALTH_STATUS', 'type' => 'CONVERTED' }), '1-0')
      expect(ack(2)).to include('id' => '1-0', 'result' => 'SUCCESS')
      expect(ack(0)).to be_nil
    end

    it "acks a failed inject_tlm on the db_shard of the target" do
      allow(TelemetryTopic).to receive(:write_packet).and_raise("bad packet")
      @handler.handle_inject_tlm_with_ack(JSON.generate({ 'target_name' => 'INST2', 'packet_name' => 'HEALTH_STATUS', 'type' => 'CONVERTED' }), '1-0')
      expect(ack(2)).to include('id' => '1-0', 'result' => 'bad packet')
      expect(ack(0)).to be_nil
    end

    it "acks build_cmd on the db_shard of the target" do
      @handler.handle_build_cmd(JSON.generate({ 'target_name' => 'INST2', 'cmd_name' => 'ABORT', 'cmd_params' => {}, 'range_check' => true, 'raw' => false }), '2-0')
      expect(ack(2)).to include('id' => '2-0', 'result' => 'SUCCESS')
      expect(ack(0)).to be_nil
    end

    it "acks get_tlm_buffer on the db_shard of the target" do
      @handler.handle_get_tlm_buffer(JSON.generate({ 'target_name' => 'INST2', 'packet_name' => 'HEALTH_STATUS' }), '3-0')
      expect(ack(2)).to include('id' => '3-0', 'result' => 'SUCCESS')
      expect(ack(0)).to be_nil
    end
  end
end
