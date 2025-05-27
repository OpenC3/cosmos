# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require "rails_helper"

RSpec.describe TopicsThread, type: :model do
  let(:topics) { ["DEFAULT__test_topic", "DEFAULT__another_topic"] }
  let(:subscription_key) { "test_subscription_123" }
  let(:history_count) { 5 }
  let(:max_batch_size) { 10 }

  before(:each) do
    mock_redis
    setup_system
    allow(ActionCable.server).to receive(:broadcast)
    allow(OpenC3::Logger).to receive(:error)

    # Define OpenC3::Topic methods for testing if they don't exist
    unless OpenC3::Topic.respond_to?(:read_topics)
      OpenC3::Topic.define_singleton_method(:read_topics) do |topics, offsets, &block|
        # Mock implementation
      end
    end

    unless OpenC3::Topic.respond_to?(:xrevrange)
      OpenC3::Topic.define_singleton_method(:xrevrange) do |topic, start_id, end_id, **options|
        []
      end
    end
  end

  describe "#initialize" do
    it "initializes with default parameters" do
      thread = TopicsThread.new(topics, subscription_key)

      expect(thread.instance_variable_get(:@topics)).to eq(topics)
      expect(thread.instance_variable_get(:@subscription_key)).to eq(subscription_key)
      expect(thread.instance_variable_get(:@history_count)).to eq(0)
      expect(thread.instance_variable_get(:@max_batch_size)).to eq(100)
      expect(thread.instance_variable_get(:@offsets)).to be_nil
      expect(thread.instance_variable_get(:@transmit_msg_id)).to be false
      expect(thread.instance_variable_get(:@cancel_thread)).to be false
      expect(thread.instance_variable_get(:@thread)).to be_nil
    end

    it "initializes with custom parameters" do
      offsets = ["123-0", "456-0"]
      thread = TopicsThread.new(
        topics,
        subscription_key,
        history_count,
        max_batch_size,
        offsets: offsets,
        transmit_msg_id: true
      )

      expect(thread.instance_variable_get(:@history_count)).to eq(history_count)
      expect(thread.instance_variable_get(:@max_batch_size)).to eq(max_batch_size)
      expect(thread.instance_variable_get(:@offsets)).to eq(offsets)
      expect(thread.instance_variable_get(:@transmit_msg_id)).to be true
    end

    it "converts history_count to integer" do
      thread = TopicsThread.new(topics, subscription_key, "10")
      expect(thread.instance_variable_get(:@history_count)).to eq(10)
    end

    it "creates offset index mapping" do
      thread = TopicsThread.new(topics, subscription_key)
      offset_index = thread.instance_variable_get(:@offset_index_by_topic)

      expect(offset_index).to eq({
        "DEFAULT__test_topic" => 0,
        "DEFAULT__another_topic" => 1
      })
    end
  end

  describe "#start" do
    let(:thread_instance) { TopicsThread.new(topics, subscription_key, history_count, max_batch_size) }

    before(:each) do
      allow(thread_instance).to receive(:thread_setup)
      allow(thread_instance).to receive(:thread_body)
      allow(thread_instance).to receive(:thread_teardown)
    end

    it "creates and starts a new thread" do
      expect(Thread).to receive(:new).and_call_original

      thread_instance.start

      expect(thread_instance.instance_variable_get(:@thread)).to be_a(Thread)
      thread_instance.stop
    end

    it "initializes offsets when not provided" do
      expect(thread_instance.instance_variable_get(:@offsets)).to be_nil
      expect(thread_instance).to receive(:thread_setup)

      thread_instance.start
      sleep(0.01) # Allow thread to start
      thread_instance.stop

      offsets = thread_instance.instance_variable_get(:@offsets)
      expect(offsets).to eq(["0-0", "0-0"])
    end

    it "does not reinitialize offsets when already provided" do
      custom_offsets = ["123-0", "456-0"]
      thread_with_offsets = TopicsThread.new(topics, subscription_key, history_count, max_batch_size, offsets: custom_offsets)

      thread_with_offsets.start
      sleep(0.01)
      thread_with_offsets.stop

      expect(thread_with_offsets.instance_variable_get(:@offsets)).to eq(custom_offsets)
    end

    it "continuously calls thread_body until cancelled" do
      call_count = 0
      allow(thread_instance).to receive(:thread_body) do
        call_count += 1
        sleep(0.001) # Small delay to prevent tight loop in test
      end

      thread_instance.start
      expect(thread_instance.instance_variable_get(:@thread)).to be_alive
      sleep(0.05) # Let it run for a bit
      thread_instance.stop
      sleep(0.01)

      expect(call_count).to be > 1
      expect(thread_instance.instance_variable_get(:@thread)).not_to be_alive
    end

    it "logs Redis::CommandError without LOADING message" do
      redis_error = Redis::CommandError.new("Some other Redis error")

      allow(thread_instance).to receive(:thread_body).and_raise(redis_error)
      expect(OpenC3::Logger).to receive(:error).with(/Redis::CommandError/)

      thread_instance.start
      sleep(0.01)

      expect(thread_instance.instance_variable_get(:@thread)).not_to be_alive
      thread_instance.stop
    end

    it "logs unexpected errors" do
      allow(thread_instance).to receive(:thread_body).and_raise(StandardError.new("Unexpected error"))
      expect(OpenC3::Logger).to receive(:error).with(/unexpectedly died/)

      thread_instance.start
      sleep(0.01)

      expect(thread_instance.instance_variable_get(:@thread)).not_to be_alive
      thread_instance.stop
    end

    it "calls thread_teardown in ensure block" do
      expect(thread_instance).to receive(:thread_teardown)

      thread_instance.start
      sleep(0.01)
      thread_instance.stop
      sleep(0.01)
    end

    it "calls thread_teardown even when error occurs" do
      allow(thread_instance).to receive(:thread_body).and_raise(StandardError.new("Test error"))
      expect(thread_instance).to receive(:thread_teardown)

      thread_instance.start
      sleep(0.01)
      thread_instance.stop
    end
  end

  describe "#thread_setup" do
    let(:thread_instance) { TopicsThread.new(topics, subscription_key, history_count, max_batch_size) }

    before(:each) do
      thread_instance.instance_variable_set(:@offsets, ["0-0", "0-0"])
      allow(thread_instance).to receive(:transmit_results)
    end

    it "processes each topic and updates offsets" do
      msg_id_1 = "1609459200000-0"
      msg_id_2 = "1609459201000-0"
      msg_hash_1 = {"data" => "message1"}
      msg_hash_2 = {"data" => "message2"}

      allow(OpenC3::Topic).to receive(:xrevrange).with("DEFAULT__test_topic", "+", "-", count: 5).and_return([[msg_id_1, msg_hash_1]])
      allow(OpenC3::Topic).to receive(:xrevrange).with("DEFAULT__another_topic", "+", "-", count: 5).and_return([[msg_id_2, msg_hash_2]])

      thread_instance.send(:thread_setup)

      expect(OpenC3::Topic).to have_received(:xrevrange).twice
      offsets = thread_instance.instance_variable_get(:@offsets)
      expect(offsets).to eq([msg_id_1, msg_id_2])
      expect(thread_instance).to have_received(:transmit_results).twice
    end

    it "skips ephemeral topics and handles zero history count" do
      ephemeral_topics = ["DEFAULT__openc3_ephemeral_messages", "DEFAULT__test_topic"]
      zero_history_thread = TopicsThread.new(ephemeral_topics, subscription_key, 0, max_batch_size)
      zero_history_thread.instance_variable_set(:@offsets, ["0-0", "0-0"])
      allow(zero_history_thread).to receive(:transmit_results)

      allow(OpenC3::Topic).to receive(:xrevrange).with("DEFAULT__test_topic", "+", "-", count: 1).and_return([["123-0", {"data" => "test"}]])

      zero_history_thread.send(:thread_setup)

      expect(OpenC3::Topic).not_to have_received(:xrevrange).with("DEFAULT__openc3_ephemeral_messages", anything, anything, anything)
      expect(OpenC3::Topic).to have_received(:xrevrange).with("DEFAULT__test_topic", "+", "-", count: 1)
      expect(zero_history_thread).not_to have_received(:transmit_results)
    end
  end
end
