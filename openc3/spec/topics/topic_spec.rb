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
require 'openc3/topics/topic'
require 'openc3/topics/telemetry_topic'
require 'openc3/models/target_model'
require 'openc3/packets/packet'

module OpenC3
  describe Topic do
    before(:each) do
      mock_redis()
      Topic.clear_stream_max_age_cache
      @saved_max_age = ENV['OPENC3_STREAM_MAX_AGE_SECONDS']
      ENV.delete('OPENC3_STREAM_MAX_AGE_SECONDS')
    end

    after(:each) do
      if @saved_max_age
        ENV['OPENC3_STREAM_MAX_AGE_SECONDS'] = @saved_max_age
      else
        ENV.delete('OPENC3_STREAM_MAX_AGE_SECONDS')
      end
      Topic.clear_stream_max_age_cache
    end

    describe "self.stream_max_age_seconds" do
      it "defaults to 600 seconds" do
        expect(Topic.stream_max_age_seconds).to eql 600
      end

      it "reads the environment variable" do
        ENV['OPENC3_STREAM_MAX_AGE_SECONDS'] = '120'
        expect(Topic.stream_max_age_seconds).to eql 120.0
      end

      it "uses the default for invalid or non-finite values" do
        allow(Logger).to receive(:warn)
        %w(abc 10s nan inf 1e400).each do |value|
          ENV['OPENC3_STREAM_MAX_AGE_SECONDS'] = value
          expect(Topic.stream_max_age_seconds).to eql 600
          Topic.clear_stream_max_age_cache
          expect(Topic.stream_max_age_ms).to eql 600_000
        end
        expect(Logger).to have_received(:warn).with(/'1e400' is invalid/).at_least(:once)
      end
    end

    describe "self.stream_safety_minid" do
      it "caches the max age" do
        expect(Topic.stream_max_age_ms).to eql 600_000
        ENV['OPENC3_STREAM_MAX_AGE_SECONDS'] = '120'
        expect(Topic.stream_max_age_ms).to eql 600_000
        Topic.clear_stream_max_age_cache
        expect(Topic.stream_max_age_ms).to eql 120_000
      end

      it "raises small max ages to the minimum" do
        ENV['OPENC3_STREAM_MAX_AGE_SECONDS'] = '0.5'
        expect(Logger).to receive(:warn).with(/below the minimum/)
        expect(Topic.stream_max_age_ms).to eql 120_000
      end

      it "caps relative to now for auto generated ids" do
        allow(Process).to receive(:clock_gettime).and_call_original
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_REALTIME, :millisecond).and_return(1700000000000)
        expect(Topic.stream_safety_minid).to eql '1699999400000'
        expect(Topic.stream_safety_minid(nil)).to eql '1699999400000'
      end

      it "caps relative to an explicit id so the added entry is kept" do
        expect(Topic.stream_safety_minid('1700000000000-5')).to eql '1699999400000'
      end

      it "uses an explicit max age" do
        expect(Topic.stream_safety_minid('1700000000000-0', max_age_ms: 1_320_000)).to eql '1699998680000'
        expect(Topic.stream_safety_minid('1700000000000-0', max_age_ms: 0)).to be_nil
      end

      it "returns nil when disabled" do
        ENV['OPENC3_STREAM_MAX_AGE_SECONDS'] = '0'
        expect(Topic.stream_safety_minid).to be_nil
        expect(Topic.log_stream_safety_minid('INST', :TLM, scope: 'DEFAULT')).to be_nil
        Topic.clear_stream_max_age_cache
        ENV['OPENC3_STREAM_MAX_AGE_SECONDS'] = ''
        expect(Topic.stream_safety_minid).to be_nil
        expect(Topic.log_stream_safety_minid('INST', :TLM, scope: 'DEFAULT')).to be_nil
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

      it "raises if the target lookup fails" do
        allow(TargetModel).to receive(:get).and_raise(RuntimeError, 'down')
        expect { Topic.log_stream_min_age_seconds('INST', :TLM, scope: 'DEFAULT') }.to raise_error(RuntimeError, 'down')
      end
    end

    describe "self.log_stream_safety_minid" do
      before(:each) do
        allow(Process).to receive(:clock_gettime).and_call_original
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_REALTIME, :millisecond).and_return(1700000000000)
      end

      it "never trims younger than two log cycles plus the cleanup delay" do
        expect(Topic.log_stream_safety_minid('INST', :TLM, scope: 'DEFAULT')).to eql '1699998680000'
      end

      it "uses the configured max age when larger" do
        ENV['OPENC3_STREAM_MAX_AGE_SECONDS'] = '3600'
        expect(Topic.log_stream_safety_minid('INST', :TLM, scope: 'DEFAULT')).to eql '1699996400000'
      end

      it "caches the max age per stream" do
        expect(TargetModel).to receive(:get).twice.and_return(nil)
        Topic.log_stream_safety_minid('INST', :TLM, scope: 'DEFAULT')
        Topic.log_stream_safety_minid('INST', :TLM, scope: 'DEFAULT')
        Topic.log_stream_safety_minid('INST', :CMD, scope: 'DEFAULT')
        Topic.log_stream_safety_minid('INST', :CMD, scope: 'DEFAULT')
      end

      it "doesn't cap or cache when the log cycle lookup fails and retries later" do
        monotonic = 1000.0
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { monotonic }
        model = { 'tlm_log_cycle_time' => 3600 }
        calls = 0
        allow(TargetModel).to receive(:get) do
          calls += 1
          raise 'down' if calls == 1
          model
        end
        expect(Logger).to receive(:warn).with(/Unable to determine log cycle time for INST TLM/).once
        expect(Topic.log_stream_safety_minid('INST', :TLM, scope: 'DEFAULT')).to be_nil
        # Not retried until the retry interval passes
        monotonic += Topic::LOG_CYCLE_LOOKUP_RETRY_SECONDS - 1
        expect(Topic.log_stream_safety_minid('INST', :TLM, scope: 'DEFAULT')).to be_nil
        expect(calls).to eql 1
        monotonic += 1
        expect(Topic.log_stream_safety_minid('INST', :TLM, scope: 'DEFAULT')).to eql (1700000000000 - 7_320_000).to_s
        # Now cached
        expect(Topic.log_stream_safety_minid('INST', :TLM, scope: 'DEFAULT')).to eql (1700000000000 - 7_320_000).to_s
        expect(calls).to eql 2
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

      it "raises if both maxlen and minid are given" do
        expect { Topic.write_topic('TOPIC', { 'a' => 1 }, '*', 10, minid: '123') }.to raise_error(ArgumentError, /both maxlen and minid/)
      end
    end

    describe "TelemetryTopic.write_packet" do
      it "applies the safety minid based on the log cycle" do
        packet = Packet.new('INST', 'HEALTH_STATUS')
        packet.received_time = Time.now
        packet.packet_time = Time.now
        packet.received_count = 1
        allow(Process).to receive(:clock_gettime).and_call_original
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_REALTIME, :millisecond).and_return(1700000000000)
        expected = '1699998680000'
        expect(Topic).to receive(:write_topic).with("DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS", kind_of(Hash), minid: expected, db_shard: 0)
        TelemetryTopic.write_packet(packet, scope: 'DEFAULT')

        store_instance = EphemeralStoreQueued.instance(db_shard: 0)
        expect(store_instance).to receive(:write_topic).with("DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS", kind_of(Hash), minid: expected)
        TelemetryTopic.write_packet(packet, queued: true, scope: 'DEFAULT')
      end
    end
  end

  describe Topic do
    before(:each) do
      mock_redis_db_shards()
    end

    def shard(db_shard)
      EphemeralStore.instance(db_shard: db_shard)
    end

    describe "mock_redis_db_shards" do
      it "gives each db_shard its own data" do
        Store.instance(db_shard: 1).set('KEY', 'one')
        expect(Store.instance(db_shard: 0).get('KEY')).to be_nil
        expect(Store.instance(db_shard: 1).get('KEY')).to eql 'one'
        # The ephemeral store is separate from the store on the same db_shard
        expect(shard(1).get('KEY')).to be_nil
      end
    end

    describe "db_shard routing" do
      it "writes and reads a topic on the given db_shard only" do
        Topic.write_topic('TOPIC', { 'received_count' => '5' }, db_shard: 1)
        expect(shard(0).xlen('TOPIC')).to eql 0
        expect(shard(1).xlen('TOPIC')).to eql 1

        expect(Topic.get_cnt('TOPIC', db_shard: 1)).to eql 5
        expect(Topic.get_cnt('TOPIC')).to eql 0
        expect(Topic.get_newest_message('TOPIC', db_shard: 1)[1]).to eql({ 'received_count' => '5' })
        expect(Topic.get_newest_message('TOPIC')).to be_nil
        expect(Topic.get_oldest_message('TOPIC', db_shard: 1)[1]).to eql({ 'received_count' => '5' })
        expect(Topic.get_oldest_message('TOPIC')).to be_nil
        expect(Topic.get_last_offset('TOPIC', db_shard: 1)).not_to eql '0-0'
        expect(Topic.get_last_offset('TOPIC')).to eql '0-0'

        messages = []
        Topic.read_topics(['TOPIC'], ['0-0'], 0, db_shard: 1) { |_topic, _msg_id, msg_hash, _redis| messages << msg_hash }
        expect(messages).to eql [{ 'received_count' => '5' }]
        Topic.read_topics(['TOPIC'], ['0-0'], 0) { |_topic, _msg_id, msg_hash, _redis| messages << msg_hash }
        expect(messages.length).to eql 1
      end

      it "clears, trims and deletes a topic on the given db_shard only" do
        3.times { |index| Topic.write_topic('TOPIC', { 'index' => index.to_s }, "#{index + 1}-0", db_shard: 1) }
        Topic.write_topic('TOPIC', { 'index' => '0' }, db_shard: 0)

        # MockRedis has no xtrim_minid so check the trim goes to the db_shard 1 store
        expect(shard(0)).not_to receive(:trim_topic)
        expect(shard(1)).to receive(:trim_topic).with('TOPIC', '2-0', false, limit: 0)
        Topic.trim_topic('TOPIC', '2-0', false, db_shard: 1)
        Topic.clear_topics(['TOPIC'], 1, db_shard: 1)
        expect(shard(1).xlen('TOPIC')).to eql 1
        Topic.del('TOPIC', db_shard: 1)
        expect(shard(1).exists('TOPIC')).to eql 0
        expect(shard(0).xlen('TOPIC')).to eql 1
      end

      it "writes an ack to the given db_shard" do
        Topic.write_ack('{DEFAULT__CMD}TARGET__INST', 'SUCCESS', '1-0', db_shard: 1)
        _, msg = Topic.get_newest_message('{DEFAULT__ACKCMD}TARGET__INST', db_shard: 1)
        expect(msg).to eql({ 'result' => 'SUCCESS', 'id' => '1-0' })
        expect(shard(0).exists('{DEFAULT__ACKCMD}TARGET__INST')).to eql 0
      end
    end

    describe "group_topics_by_db_shard" do
      before(:each) do
        set_target_db_shard('INST', 0)
        set_target_db_shard('INST2', 1)
        set_target_db_shard('MY_TARGET', 2)
      end

      it "groups command topics by the db_shard of their target" do
        topics = ['{DEFAULT__CMD}TARGET__INST', '{DEFAULT__CMD}TARGET__INST2', '{DEFAULT__CMD}TARGET__MY_TARGET', '{DEFAULT__CMD}INTERFACE__INT']
        groups = Topic.group_topics_by_db_shard(topics, target_pattern: 'CMD}TARGET__', scope: 'DEFAULT')
        expect(groups).to eql({
          0 => ['{DEFAULT__CMD}TARGET__INST', '{DEFAULT__CMD}INTERFACE__INT'],
          1 => ['{DEFAULT__CMD}TARGET__INST2'],
          2 => ['{DEFAULT__CMD}TARGET__MY_TARGET'],
        })
      end

      it "groups telemetry topics by the db_shard of their target" do
        topics = ['DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS', 'DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS', 'DEFAULT__TELEMETRY__{MY_TARGET}__MY_PKT']
        groups = Topic.group_topics_by_db_shard(topics, target_pattern: '__TELEMETRY__', scope: 'DEFAULT')
        expect(groups).to eql({
          0 => ['DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS'],
          1 => ['DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS'],
          2 => ['DEFAULT__TELEMETRY__{MY_TARGET}__MY_PKT'],
        })
      end

      it "puts a target which isn't on a db_shard on db_shard 0" do
        groups = Topic.group_topics_by_db_shard(['{DEFAULT__CMD}TARGET__UNKNOWN'], target_pattern: 'CMD}TARGET__', scope: 'DEFAULT')
        expect(groups).to eql({ 0 => ['{DEFAULT__CMD}TARGET__UNKNOWN'] })
      end

      it "looks up the db_shard in the given scope" do
        set_target_db_shard('INST', 3, scope: 'OTHER')
        groups = Topic.group_topics_by_db_shard(['{OTHER__CMD}TARGET__INST'], target_pattern: 'CMD}TARGET__', scope: 'OTHER')
        expect(groups).to eql({ 3 => ['{OTHER__CMD}TARGET__INST'] })
      end
    end

    describe "all_same_db_shard?" do
      it "is true for at most one db_shard" do
        expect(Topic.all_same_db_shard?({})).to be true
        expect(Topic.all_same_db_shard?({ 1 => ['A', 'B'] })).to be true
        expect(Topic.all_same_db_shard?({ 0 => ['A'], 1 => ['B'] })).to be false
      end
    end
  end
end
