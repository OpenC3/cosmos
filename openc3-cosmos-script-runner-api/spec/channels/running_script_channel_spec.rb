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
  # Keyed by (connection, script id) -- not connection alone -- so tearing down
  # one script's subscription can't stop another's replay thread
  let(:subscription_key) { "running-script-#{uuid}-42" }
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
    it 'transmits the backlog and starts streaming live events bounded by the arm timeout' do
      backlog({ 'type' => 'line', 'line_no' => 1 }, { 'type' => 'output', 'line' => 'hi' })
      subscribe id: '42'
      expect(subscription).to be_confirmed
      expected = [
        { 'type' => 'line', 'line_no' => 1 },
        { 'type' => 'output', 'line' => 'hi' },
      ]
      expect(transmissions).to eq([expected])
      # Streaming must start strictly after the transmitted backlog (no gap, no
      # duplicates) and stay unarmed for up to ARM_TIMEOUT unless the
      # client performs 'ready'
      expect(RunningScriptReplayThread).to have_received(:new).with(
        subscription_key, '42', '101-0', arm_delay: RunningScriptChannel::ARM_TIMEOUT
      )
      expect(broadcaster).to have_received(:start)
    end

    it 'does not start streaming when the backlog already holds the terminal complete' do
      backlog({ 'type' => 'line', 'line_no' => 1 }, { 'type' => 'complete' })
      subscribe id: '42'
      expect(subscription).to be_confirmed
      expected = [
        { 'type' => 'line', 'line_no' => 1 },
        { 'type' => 'complete' },
      ]
      expect(transmissions.last).to eq(expected)
      expect(RunningScriptReplayThread).not_to have_received(:new)
    end

    it 'transmits a large backlog in bounded, ordered batches' do
      events = (1..(RunningScriptReplayThread::MAX_BATCH_SIZE + 1)).map do |line_no|
        { 'type' => 'line', 'line_no' => line_no }
      end
      backlog(*events)

      subscribe id: '42'

      expect(transmissions.map(&:length)).to eq([RunningScriptReplayThread::MAX_BATCH_SIZE, 1])
      expect(transmissions.flatten).to eq(events)
    end

    it 'transmits the batch parsed before a bad backlog entry rather than losing it' do
      backlog({ 'type' => 'line', 'line_no' => 1 })
      OpenC3::Topic.write_topic("running-script-channel:42:replay", { 'data' => 'not json' }, '102-0')

      subscribe id: '42'

      # Batching must not let one corrupt entry discard the whole preceding
      # backlog and leave the client with no state for a script that already ran
      expect(subscription).to be_confirmed
      expect(transmissions).to eq([[{ 'type' => 'line', 'line_no' => 1 }]])
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

  describe '#ready' do
    it 'starts streaming events without waiting out the arm timeout' do
      backlog({ 'type' => 'line', 'line_no' => 1 })
      subscribe id: '42'
      perform :ready
      expect(broadcaster).to have_received(:arm)
    end

    it 'no-ops when the script already completed and no broadcaster exists' do
      backlog({ 'type' => 'complete' })
      subscribe id: '42'
      expect { perform :ready }.not_to raise_error
      expect(broadcaster).not_to have_received(:arm)
    end

    it 'is safe to perform repeatedly (client reconnects report ready again)' do
      backlog({ 'type' => 'line', 'line_no' => 1 })
      subscribe id: '42'
      perform :ready
      perform :ready
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
