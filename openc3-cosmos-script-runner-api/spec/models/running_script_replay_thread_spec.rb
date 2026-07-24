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
require 'timeout'

RSpec.describe RunningScriptReplayThread, type: :model do
  let(:subscription_key) { 'running-script-test-uuid' }
  let(:id) { '42' }
  let(:topic) { "running-script-channel:#{id}:replay" }

  # Timestamps of each read_topics call, pushed from the broadcaster thread.
  # Queue#pop(timeout:) gives us race-free "wait until the thread reads"
  # synchronization instead of sleeping fixed amounts.
  let(:reads) { Queue.new }

  def wait_for_read(timeout)
    Timeout.timeout(timeout) { reads.pop }
  rescue Timeout::Error
    nil
  end

  after(:each) do
    if @thread_under_test
      @thread_under_test.stop
      @thread_under_test.instance_variable_get(:@thread)&.join(2)
    end
  end

  def start_thread(**kwargs)
    @thread_under_test = RunningScriptReplayThread.new(subscription_key, id, kwargs.delete(:start_offset) || '0-0', **kwargs)
    @thread_under_test.start
    @thread_under_test
  end

  describe '#initialize' do
    it 'guards a nil start offset back to 0-0 so read_topics cannot raise' do
      thread = RunningScriptReplayThread.new(subscription_key, id, nil)
      expect(thread.instance_variable_get(:@offsets)).to eq(['0-0'])
    end

    it 'starts armed when no arm delay is given' do
      allow(OpenC3::Topic).to receive(:read_topics) do
        reads << Time.now
        sleep 0.05
        nil
      end
      start_thread
      expect(wait_for_read(1.0)).not_to be_nil
    end
  end

  describe '#arm' do
    it 'defers the first read until armed, then reads immediately' do
      allow(OpenC3::Topic).to receive(:read_topics) do
        reads << Time.now
        sleep 0.05
        nil
      end
      # Delay far longer than the test: if arm() did not short-circuit it,
      # wait_for_read below would time out
      thread = start_thread(arm_delay: 30.0)
      expect(wait_for_read(0.3)).to be_nil # not yet armed: no reads
      thread.arm
      expect(wait_for_read(1.0)).not_to be_nil
    end

    it 'falls back to reading after arm_delay for legacy clients that never arm' do
      allow(OpenC3::Topic).to receive(:read_topics) do
        reads << Time.now
        sleep 0.05
        nil
      end
      start = Time.now
      start_thread(arm_delay: 0.3)
      first_read = wait_for_read(2.0)
      expect(first_read).not_to be_nil
      expect(first_read - start).to be >= 0.3
    end
  end

  describe '#stop' do
    it 'ends the thread during the arm wait without ever reading' do
      allow(OpenC3::Topic).to receive(:read_topics) do
        reads << Time.now
        nil
      end
      thread = start_thread(arm_delay: 30.0)
      thread.stop
      expect(thread.instance_variable_get(:@thread).join(2)).not_to be_nil
      expect(reads).to be_empty
    end
  end

  describe '#start' do
    it 'tails from the given offset and broadcasts each event to the subscription' do
      broadcasts = []
      allow(ActionCable.server).to receive(:broadcast) { |key, event| broadcasts << [key, event] }
      line_event = { 'type' => 'line', 'line_no' => 1 }
      complete_event = { 'type' => 'complete' }
      offsets_seen = nil
      allow(OpenC3::Topic).to receive(:read_topics) do |topics, offsets, &block|
        expect(topics).to eq([topic])
        offsets_seen = offsets.dup
        block.call(topic, '101-0', { 'data' => line_event.to_json }, nil)
        block.call(topic, '102-0', { 'data' => complete_event.to_json }, nil)
      end

      thread = start_thread(start_offset: '100-0')
      # 'complete' is terminal: the thread must end on its own (self-cleaning
      # even when the client disconnects abruptly and unsubscribed never fires)
      expect(thread.instance_variable_get(:@thread).join(2)).not_to be_nil
      expect(offsets_seen).to eq(['100-0'])
      expect(broadcasts).to eq([
        [subscription_key, line_event],
        [subscription_key, complete_event],
      ])
    end

    it 'skips entries with no data and keeps tailing' do
      broadcasts = []
      allow(ActionCable.server).to receive(:broadcast) { |key, event| broadcasts << [key, event] }
      event = { 'type' => 'complete' }
      allow(OpenC3::Topic).to receive(:read_topics) do |_topics, _offsets, &block|
        block.call(topic, '101-0', {}, nil)
        block.call(topic, '102-0', { 'data' => event.to_json }, nil)
      end

      thread = start_thread
      expect(thread.instance_variable_get(:@thread).join(2)).not_to be_nil
      expect(broadcasts).to eq([[subscription_key, event]])
    end
  end
end
