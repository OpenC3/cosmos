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
require 'openc3/logs/log_writer'

module OpenC3
  describe LogWriter do
    before(:each) do
      mock_redis_db_shards()
      set_target_db_shard('INST', 0)
      set_target_db_shard('MY_TARGET', 1)
      set_target_db_shard('INST', 2, scope: 'OTHER')
    end

    describe "db_shard_for_topic" do
      it "returns the db_shard of the target of a topic" do
        expect(LogWriter.db_shard_for_topic('DEFAULT__DECOM__{INST}__HEALTH_STATUS')).to eql 0
        expect(LogWriter.db_shard_for_topic('DEFAULT__TELEMETRY__{MY_TARGET}__MY_PKT')).to eql 1
        expect(LogWriter.db_shard_for_topic('DEFAULT__COMMAND__{MY_TARGET}__ABORT')).to eql 1
        expect(LogWriter.db_shard_for_topic('DEFAULT__DECOMCMD__{MY_TARGET}__ABORT')).to eql 1
      end

      it "looks up the target in the scope of the topic" do
        expect(LogWriter.db_shard_for_topic('OTHER__DECOM__{INST}__HEALTH_STATUS')).to eql 2
      end

      it "returns db_shard 0 for a topic without a target" do
        expect(LogWriter.db_shard_for_topic('DEFAULT__openc3_log_messages')).to eql 0
      end
    end

    describe "cleanup" do
      it "trims each logged topic on the db_shard of its target" do
        topics = {
          'DEFAULT__DECOM__{INST}__HEALTH_STATUS' => 0,
          'DEFAULT__DECOM__{MY_TARGET}__MY_PKT' => 1,
          'OTHER__DECOM__{INST}__HEALTH_STATUS' => 2,
        }
        # Each topic has 3 entries on its target's db_shard and on every other db_shard
        3.times do |db_shard|
          store = EphemeralStore.instance(db_shard: db_shard)
          topics.each_key do |topic|
            (1..3).each { |index| store.write_topic(topic, { 'index' => index.to_s }, "#{index}-0") }
          end
          # MockRedis has no XTRIM MINID so trim to the entries at or after minid
          store.redis_pool.with do |redis|
            redis.define_singleton_method(:xtrim_minid) do |key, minid, **|
              xtrim(key, xrange(key, '-', '+').count { |id, _| id >= minid })
            end
          end
        end

        writer = LogWriter.new('DEFAULT/logs', true, nil, 1_000_000_000, nil, nil, true, cycle_thread: false)
        writer.cleanup_offsets = [topics.transform_values { '3-0' }]
        writer.cleanup_times = [Time.now - 1]
        # Run a single pass of the cycle thread over this writer
        allow_any_instance_of(Sleeper).to receive(:sleep).and_return(true)
        LogWriter.class_variable_get(:@@instances) << writer
        begin
          writer.send(:cycle_thread_body)
        ensure
          LogWriter.class_variable_get(:@@instances).delete(writer)
        end

        topics.each do |topic, target_db_shard|
          3.times do |db_shard|
            # Only the target's db_shard is trimmed up to the cleanup offset
            expected = db_shard == target_db_shard ? 1 : 3
            expect(EphemeralStore.instance(db_shard: db_shard).xlen(topic)).to eql(expected), "#{topic} on db_shard #{db_shard}"
          end
        end
        expect(writer.cleanup_offsets).to be_empty
      end
    end
  end
end
