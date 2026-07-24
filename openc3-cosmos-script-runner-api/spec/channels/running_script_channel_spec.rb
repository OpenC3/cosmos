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

RSpec.describe RunningScriptChannel, type: :channel do
  let(:uuid) { 'test-uuid' }
  let(:subscription_key) { "running-script-#{uuid}" }
  let(:broadcaster) { instance_double(RunningScriptReplayThread, start: nil, arm: nil, stop: nil) }

  before(:each) do
    mock_redis
    # Connections without the url_authenticated identifier are treated as
    # authenticated (see ApplicationCable::Channel#connection_url_authenticated?)
    stub_connection uuid: uuid, scope: 'DEFAULT'
    RunningScriptChannel.class_variable_set(:@@broadcasters, {})
    allow(RunningScriptReplayThread).to receive(:new).and_return(broadcaster)
  end

  after(:each) do
    RunningScriptChannel.class_variable_set(:@@broadcasters, {})
  end

  # Seed the replay stream the way running_script.rb does, so subscribed()
  # exercises the real xrange backlog read
  def backlog(*events)
    events.each_with_index do |event, i|
      OpenC3::Topic.write_topic("running-script-channel:42:replay", { 'data' => event.to_json }, "10#{i}-0")
    end
  end

  describe '#subscribed' do
    it 'transmits the backlog and starts a live tail with the legacy arm delay' do
      backlog({ 'type' => 'line', 'line_no' => 1 }, { 'type' => 'output', 'line' => 'hi' })
      subscribe id: '42'
      expect(subscription).to be_confirmed
      expect(transmissions).to eq([
        { 'type' => 'line', 'line_no' => 1 },
        { 'type' => 'output', 'line' => 'hi' },
      ])
      # The tail must start strictly after the transmitted backlog (no gap, no
      # duplicates) and stay unarmed for up to LEGACY_ARM_DELAY unless the
      # client performs 'tail'
      expect(RunningScriptReplayThread).to have_received(:new).with(
        subscription_key, '42', '101-0', arm_delay: RunningScriptChannel::LEGACY_ARM_DELAY
      )
      expect(broadcaster).to have_received(:start)
    end

    it 'does not start a tail when the backlog already holds the terminal complete' do
      backlog({ 'type' => 'line', 'line_no' => 1 }, { 'type' => 'complete' })
      subscribe id: '42'
      expect(subscription).to be_confirmed
      expect(transmissions.last).to eq({ 'type' => 'complete' })
      expect(RunningScriptReplayThread).not_to have_received(:new)
    end

    it 'stops a leftover broadcaster for the same connection before starting a new one' do
      old_broadcaster = instance_double(RunningScriptReplayThread, stop: nil)
      RunningScriptChannel.class_variable_set(:@@broadcasters, { subscription_key => old_broadcaster })
      backlog({ 'type' => 'line', 'line_no' => 1 })
      subscribe id: '42'
      expect(old_broadcaster).to have_received(:stop)
      expect(RunningScriptChannel.class_variable_get(:@@broadcasters)[subscription_key]).to eq(broadcaster)
    end
  end

  describe '#tail' do
    it 'arms the live tail so events flow without waiting out the legacy delay' do
      backlog({ 'type' => 'line', 'line_no' => 1 })
      subscribe id: '42'
      perform :tail
      expect(broadcaster).to have_received(:arm)
    end

    it 'no-ops when the script already completed and no broadcaster exists' do
      backlog({ 'type' => 'complete' })
      subscribe id: '42'
      expect { perform :tail }.not_to raise_error
      expect(broadcaster).not_to have_received(:arm)
    end

    it 'is safe to perform repeatedly (client reconnects re-arm)' do
      backlog({ 'type' => 'line', 'line_no' => 1 })
      subscribe id: '42'
      perform :tail
      perform :tail
      expect(broadcaster).to have_received(:arm).twice
    end
  end

  describe '#unsubscribed' do
    it 'stops the broadcaster and clears it from the registry' do
      backlog({ 'type' => 'line', 'line_no' => 1 })
      subscribe id: '42'
      subscription.unsubscribe_from_channel
      expect(broadcaster).to have_received(:stop)
      expect(RunningScriptChannel.class_variable_get(:@@broadcasters)).to be_empty
    end
  end
end
