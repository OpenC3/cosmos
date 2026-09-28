# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

require 'spec_helper'
require 'openc3/topics/topic'
require 'openc3/topics/telemetry_topic'
require 'openc3/models/target_model'
require 'openc3/packets/packet'

module OpenC3
  describe Topic do
    before(:each) do
      mock_redis()
      Topic.clear_log_cycle_times
      @saved_max_age = ENV['OPENC3_STREAM_MAX_AGE_SECONDS']
      ENV.delete('OPENC3_STREAM_MAX_AGE_SECONDS')
    end

    after(:each) do
      if @saved_max_age
        ENV['OPENC3_STREAM_MAX_AGE_SECONDS'] = @saved_max_age
      else
        ENV.delete('OPENC3_STREAM_MAX_AGE_SECONDS')
      end
      Topic.clear_log_cycle_times
    end

    describe "self.stream_max_age_seconds" do
      it "defaults to 600 seconds" do
        expect(Topic.stream_max_age_seconds).to eql 600
      end

      it "reads the environment variable" do
        ENV['OPENC3_STREAM_MAX_AGE_SECONDS'] = '120'
        expect(Topic.stream_max_age_seconds).to eql 120.0
      end
    end

    describe "self.stream_safety_minid" do
      it "caps relative to now for auto generated ids" do
        now = Time.now
        allow(Time).to receive(:now).and_return(now)
        expect(Topic.stream_safety_minid).to eql(((now.to_f * 1000).to_i - 600_000).to_s)
        expect(Topic.stream_safety_minid(nil)).to eql(((now.to_f * 1000).to_i - 600_000).to_s)
      end

      it "caps relative to an explicit id so the added entry is kept" do
        expect(Topic.stream_safety_minid('1700000000000-5')).to eql '1699999400000'
      end

      it "never trims younger than min_age_seconds" do
        expect(Topic.stream_safety_minid('1700000000000-0', min_age_seconds: 1320)).to eql '1699998680000'
        # A smaller min age does not reduce the configured max age
        expect(Topic.stream_safety_minid('1700000000000-0', min_age_seconds: 10)).to eql '1699999400000'
      end

      it "returns nil when disabled" do
        ENV['OPENC3_STREAM_MAX_AGE_SECONDS'] = '0'
        expect(Topic.stream_safety_minid).to be_nil
        ENV['OPENC3_STREAM_MAX_AGE_SECONDS'] = ''
        expect(Topic.stream_safety_minid(min_age_seconds: 1320)).to be_nil
      end

      it "returns nil for ids younger than the max age since the epoch" do
        expect(Topic.stream_safety_minid('1000-0')).to be_nil
      end
    end

    describe "self.log_stream_min_age_seconds" do
      it "defaults to two default log cycles plus the cleanup delay" do
        expect(Topic.log_stream_min_age_seconds('NOPE', :TLM, scope: 'DEFAULT')).to eql 1320
      end

      it "uses the target log cycle times" do
        model = TargetModel.new(folder_name: 'INST', name: 'INST', scope: 'DEFAULT', tlm_log_cycle_time: 3600, cmd_log_cycle_time: 1200)
        model.create
        expect(Topic.log_stream_min_age_seconds('INST', :TLM, scope: 'DEFAULT')).to eql 7320
        expect(Topic.log_stream_min_age_seconds('INST', :CMD, scope: 'DEFAULT')).to eql 2520
      end

      it "caches the log cycle time" do
        expect(TargetModel).to receive(:get).once.and_return(nil)
        Topic.log_stream_min_age_seconds('INST', :TLM, scope: 'DEFAULT')
        Topic.log_stream_min_age_seconds('INST', :TLM, scope: 'DEFAULT')
      end
    end

    describe "self.write_topic" do
      it "passes minid through to XADD" do
        expect_any_instance_of(MockRedis).to receive(:xadd).with('TOPIC', { 'a' => 1 }, id: '*', minid: '123', approximate: 'true').and_return('1-0')
        expect(Topic.write_topic('TOPIC', { 'a' => 1 }, minid: '123')).to eql '1-0'
      end

      it "uses maxlen when no minid is given" do
        expect_any_instance_of(MockRedis).to receive(:xadd).with('TOPIC', { 'a' => 1 }, id: '*', maxlen: 10, approximate: 'true').and_return('1-0')
        expect(Topic.write_topic('TOPIC', { 'a' => 1 }, '*', 10)).to eql '1-0'
      end
    end

    describe "TelemetryTopic.write_packet" do
      it "applies the safety minid based on the log cycle" do
        packet = Packet.new('INST', 'HEALTH_STATUS')
        packet.received_time = Time.now
        packet.packet_time = Time.now
        packet.received_count = 1
        now = Time.now
        allow(Time).to receive(:now).and_return(now)
        expected = ((now.to_f * 1000).to_i - 1_320_000).to_s
        expect(Topic).to receive(:write_topic).with("DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS", kind_of(Hash), minid: expected, db_shard: 0)
        TelemetryTopic.write_packet(packet, scope: 'DEFAULT')

        store_instance = EphemeralStoreQueued.instance(db_shard: 0)
        expect(store_instance).to receive(:write_topic).with("DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS", kind_of(Hash), minid: expected)
        TelemetryTopic.write_packet(packet, queued: true, scope: 'DEFAULT')
      end
    end
  end
end
