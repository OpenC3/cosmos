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

require 'rails_helper'

RSpec.describe RealtimeStreamingThread, type: :model do
  let(:topic) { 'DEFAULT__DECOM__{INST}__HEALTH_STATUS' }
  let(:other) { 'DEFAULT__DECOM__{INST}__ADCS' }
  # Arbitrary Redis server time (ms) that msg_ids are stamped with
  let(:base_ms) { 1_700_000_000_000 }

  before(:each) do
    @streaming_api = double('StreamingApi')
    allow(@streaming_api).to receive(:transmit_notice)
    @object = double('StreamingObject', db_shard: 0)
    allow(@object).to receive(:offset=)
    @other_object = double('OtherStreamingObject', db_shard: 0)
    allow(@other_object).to receive(:offset=)
    @thread = RealtimeStreamingThread.new(@streaming_api, StreamingObjectCollection.new, scope: 'DEFAULT')
    allow(Process).to receive(:clock_gettime).and_call_original
  end

  def at(seconds)
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(1000.0 + seconds)
  end

  def head_id(lag_seconds)
    "#{base_ms + (lag_seconds * 1000).to_i}-0"
  end

  # Simulate a pass where the newest message read trails the stream head by lag_seconds
  def check(lag_seconds, seconds)
    at(seconds)
    allow(@thread).to receive(:stream_heads).and_return({ topic => head_id(lag_seconds) })
    @thread.check_lag({ topic => "#{base_ms}-0" }, { topic => [@object] }, {})
  end

  it "does nothing while within the max lag" do
    check(1, 0)
    check(9, 20)
    expect(@streaming_api).to_not have_received(:transmit_notice)
    expect(@object).to_not have_received(:offset=)
  end

  it "skips ahead to the stream head when the lag doesn't shrink over a window" do
    check(15, 0)
    expect(@streaming_api).to_not have_received(:transmit_notice)
    check(16, 5)
    expect(@streaming_api).to_not have_received(:transmit_notice)
    check(20, 11)
    expect(@object).to have_received(:offset=).with(head_id(20))
    expect(@streaming_api).to have_received(:transmit_notice).with('SKIPPED', /skipped 20.0s/, skipped_seconds: be_within(0.01).of(20.0))
  end

  it "gives a stream that is catching up more time" do
    check(40, 0)
    check(30, 11)
    check(20, 22)
    check(11, 33)
    expect(@streaming_api).to_not have_received(:transmit_notice)
    check(5, 44)
    check(15, 50)
    check(15, 55)
    expect(@streaming_api).to_not have_received(:transmit_notice)
  end

  it "skips immediately when far behind" do
    check(61, 0)
    expect(@streaming_api).to have_received(:transmit_notice).with('SKIPPED', anything, skipped_seconds: be_within(0.01).of(61.0))
  end

  it "only checks the lag once per interval" do
    check(1, 0)
    check(70, 0.5)
    expect(@thread).to have_received(:stream_heads).once
    expect(@streaming_api).to_not have_received(:transmit_notice)
    check(70, 1.5)
    expect(@streaming_api).to have_received(:transmit_notice)
  end

  it "uses the most behind topic and only advances topics that are behind" do
    at(0)
    allow(@thread).to receive(:stream_heads).and_return({ topic => head_id(1), other => head_id(70) })
    @thread.check_lag({ topic => "#{base_ms}-0", other => "#{base_ms}-0" }, { topic => [@object] }, { other => [@other_object] })
    expect(@other_object).to have_received(:offset=).with(head_id(70))
    expect(@object).to_not have_received(:offset=)
    expect(@streaming_api).to have_received(:transmit_notice).with('SKIPPED', anything, skipped_seconds: be_within(0.01).of(70.0))
  end

  it "can be disabled" do
    stub_const('ENV', ENV.to_h.merge('OPENC3_STREAMING_MAX_LAG_SECONDS' => '0'))
    @thread = RealtimeStreamingThread.new(@streaming_api, StreamingObjectCollection.new, scope: 'DEFAULT')
    allow(@thread).to receive(:stream_heads)
    check(1000, 0)
    expect(@thread).to_not have_received(:stream_heads)
    expect(@streaming_api).to_not have_received(:transmit_notice)
  end

  context "with redis" do
    before(:each) do
      mock_redis()
    end

    it "reads the newest msg_id of each topic" do
      OpenC3::Topic.write_topic(topic, { 'a' => '1' }, '1000-0')
      OpenC3::Topic.write_topic(topic, { 'a' => '2' }, '2000-0')
      OpenC3::Topic.write_topic(other, { 'a' => '3' }, '3000-0')
      heads = @thread.stream_heads([topic, other, 'DEFAULT__DECOM__{INST}__EMPTY'], { topic => [@object] }, { other => [@object] })
      expect(heads).to eql({ topic => '2000-0', other => '3000-0', 'DEFAULT__DECOM__{INST}__EMPTY' => nil })
    end

    it "is not fooled by clock skew between this host and redis" do
      msg_id = OpenC3::Topic.write_topic(topic, { 'a' => '1' })
      # This host's clock is far ahead of the Redis server that stamped msg_id
      allow(Time).to receive(:now).and_return(Time.now + 120)
      at(0)
      @thread.check_lag({ topic => msg_id }, { topic => [@object] }, {})
      expect(@streaming_api).to_not have_received(:transmit_notice)
      expect(@object).to_not have_received(:offset=)
    end
  end
end
