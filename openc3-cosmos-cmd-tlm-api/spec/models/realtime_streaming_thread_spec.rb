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

  before(:each) do
    @streaming_api = double('StreamingApi')
    allow(@streaming_api).to receive(:transmit_notice)
    @object = double('StreamingObject', db_shard: 0)
    allow(@object).to receive(:offset=)
    @thread = RealtimeStreamingThread.new(@streaming_api, StreamingObjectCollection.new, scope: 'DEFAULT')
    allow(OpenC3::Topic).to receive(:get_last_offset).and_return('99999999999999-0')
  end

  def msg_id(seconds_ago, now)
    "#{((now - seconds_ago) * 1000).to_i}-0"
  end

  def check(seconds_ago, now)
    allow(Time).to receive(:now).and_return(Time.at(now))
    @thread.check_lag({ topic => msg_id(seconds_ago, now) }, { topic => [@object] }, {})
  end

  it "does nothing while within the max lag" do
    now = Time.now.to_f
    check(1, now)
    check(9, now + 20)
    expect(@streaming_api).to_not have_received(:transmit_notice)
    expect(@object).to_not have_received(:offset=)
  end

  it "skips ahead when the lag doesn't shrink over a window" do
    now = Time.now.to_f
    check(15, now)
    expect(@streaming_api).to_not have_received(:transmit_notice)
    check(16, now + 5)
    expect(@streaming_api).to_not have_received(:transmit_notice)
    check(20, now + 11)
    expect(@object).to have_received(:offset=).with('99999999999999-0')
    expect(@streaming_api).to have_received(:transmit_notice).with('SKIPPED', /skipped 20.0s/, skipped_seconds: be_within(0.01).of(20.0))
  end

  it "gives a stream that is catching up more time" do
    now = Time.now.to_f
    check(40, now)
    check(30, now + 11)
    check(20, now + 22)
    check(11, now + 33)
    expect(@streaming_api).to_not have_received(:transmit_notice)
    check(5, now + 44)
    check(15, now + 50)
    check(15, now + 55)
    expect(@streaming_api).to_not have_received(:transmit_notice)
  end

  it "skips immediately when far behind" do
    now = Time.now.to_f
    check(61, now)
    expect(@streaming_api).to have_received(:transmit_notice).with('SKIPPED', anything, skipped_seconds: be_within(0.01).of(61.0))
  end

  it "uses the most behind topic" do
    now = Time.now.to_f
    allow(Time).to receive(:now).and_return(Time.at(now))
    other = 'DEFAULT__DECOM__{INST}__ADCS'
    @thread.check_lag({ topic => msg_id(1, now), other => msg_id(70, now) }, { topic => [@object] }, { other => [@object] })
    expect(OpenC3::Topic).to have_received(:get_last_offset).twice
    expect(@streaming_api).to have_received(:transmit_notice)
  end

  it "can be disabled" do
    stub_const('ENV', ENV.to_h.merge('OPENC3_STREAMING_MAX_LAG_SECONDS' => '0'))
    @thread = RealtimeStreamingThread.new(@streaming_api, StreamingObjectCollection.new, scope: 'DEFAULT')
    check(1000, Time.now.to_f)
    expect(@streaming_api).to_not have_received(:transmit_notice)
  end
end
