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

module OpenC3
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
