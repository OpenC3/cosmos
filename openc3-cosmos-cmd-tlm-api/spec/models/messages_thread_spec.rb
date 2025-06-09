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

RSpec.describe MessagesThread, type: :model do
  let(:subscription_key) { "test_subscription_123" }
  let(:scope) { "DEFAULT" }
  let(:start_time) { Time.now.to_nsec_from_epoch }
  let(:end_time) { (Time.now + 3600).to_nsec_from_epoch }

  before(:each) do
    mock_redis
    setup_system

    # Mock ActionCable
    allow(ActionCable.server).to receive(:broadcast)

    allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return([nil, nil])
    allow(OpenC3::EphemeralStore.instance).to receive(:read_topics).and_yield("test_topic", "msg_id", {"time" => start_time}, nil)
  end

  describe "#initialize" do
    it "initializes with default parameters" do
      thread = MessagesThread.new(subscription_key, scope: scope)

      expect(thread.instance_variable_get(:@subscription_key)).to eq(subscription_key)
      expect(thread.instance_variable_get(:@scope)).to eq(scope)
      expect(thread.instance_variable_get(:@start_time)).to be_nil
      expect(thread.instance_variable_get(:@end_time)).to be_nil
      expect(thread.instance_variable_get(:@types)).to be_nil
      expect(thread.instance_variable_get(:@level)).to be_nil
      expect(thread.instance_variable_get(:@thread_mode)).to eq(:SETUP)
      expect(thread.instance_variable_get(:@topics)).to eq(["DEFAULT__openc3_log_messages", "DEFAULT__openc3_ephemeral_messages"])
    end

    it "initializes with custom parameters" do
      types = ["INFO", "ERROR"]
      level = "WARN"

      thread = MessagesThread.new(
        subscription_key,
        10,
        50,
        start_offset: "123-0",
        start_time: start_time,
        end_time: end_time,
        types: types,
        level: level,
        scope: scope
      )

      expect(thread.instance_variable_get(:@history_count)).to eq(10)
      expect(thread.instance_variable_get(:@max_batch_size)).to eq(50)
      expect(thread.instance_variable_get(:@start_time)).to eq(start_time)
      expect(thread.instance_variable_get(:@end_time)).to eq(end_time)
      expect(thread.instance_variable_get(:@types)).to eq(types)
      expect(thread.instance_variable_get(:@level)).to eq(level)
      expect(thread.instance_variable_get(:@offsets)).to eq(["123-0", "$"])
    end

    it "converts single type to array" do
      thread = MessagesThread.new(subscription_key, types: "ERROR", scope: scope)

      expect(thread.instance_variable_get(:@types)).to eq(["ERROR"])
    end
  end

  describe "#setup_thread_body" do
    let(:current_time) { Time.now }

    before do
      allow(Time).to receive(:now).and_return(current_time)
    end

    context "when start_time is too far in the future" do
      it "cancels the thread and logs message" do
        future_time = (current_time + 120).to_nsec_from_epoch # 2 minutes in future
        thread = MessagesThread.new(subscription_key, start_time: future_time, scope: scope)

        logger_messages = []
        allow(OpenC3::Logger).to receive(:info) do |msg|
          logger_messages << msg
        end

        thread.setup_thread_body

        expect(thread.instance_variable_get(:@cancel_thread)).to be true
        expect(logger_messages).to include("MessagesThread - Finishing stream start_time too far in future")
      end
    end

    context "when start_time is within acceptable range" do
      context "when Redis has data" do
        let(:oldest_msg_id) { "#{current_time.to_i - 100}000-0" }
        let(:oldest_msg_hash) { {"time" => (current_time.to_i - 100) * 1_000_000_000} }

        before do
          allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message)
            .and_return([oldest_msg_id, oldest_msg_hash])
        end

        it "sets thread mode to FILE when start_time is before oldest Redis data" do
          old_start_time = (current_time - 200).to_nsec_from_epoch # 10 seconds ago
          thread = MessagesThread.new(subscription_key, start_time: old_start_time, scope: scope)
          thread.setup_thread_body

          expect(thread.instance_variable_get(:@thread_mode)).to eq(:FILE)
        end

        it "sets thread mode to STREAM when start_time is after oldest Redis data" do
          recent_start_time = (current_time - 10).to_nsec_from_epoch # 10 seconds ago
          thread = MessagesThread.new(subscription_key, start_time: recent_start_time, scope: scope, start_offset: "123-0")
          thread.setup_thread_body

          expect(thread.instance_variable_get(:@thread_mode)).to eq(:STREAM)
        end

        it "cancels when end_time is before oldest Redis data" do
          early_end_time = (current_time - 200).to_nsec_from_epoch
          thread = MessagesThread.new(
            subscription_key,
            start_time: start_time,
            end_time: early_end_time,
            scope: scope
          )

          logger_messages = []
          allow(OpenC3::Logger).to receive(:info) do |msg|
            logger_messages << msg
          end

          thread.setup_thread_body

          expect(thread.instance_variable_get(:@cancel_thread)).to be true
          expect(logger_messages).to include("MessagesThread - Finishing stream - start_time after end_time")
        end
      end

      context "when Redis has no data" do
        before do
          allow(OpenC3::EphemeralStore.instance).to receive(:get_oldest_message).and_return([nil, nil])
        end

        it "sets thread mode to FILE" do
          thread = MessagesThread.new(subscription_key, start_time: start_time, scope: scope)
          thread.setup_thread_body

          expect(thread.instance_variable_get(:@thread_mode)).to eq(:FILE)
        end
      end
    end
  end

  describe "#thread_body" do
    let(:thread) { MessagesThread.new(subscription_key, scope: scope) }

    it "calls setup_thread_body when in SETUP mode" do
      thread.instance_variable_set(:@thread_mode, :SETUP)
      expect(thread).to receive(:setup_thread_body)

      thread.thread_body
    end

    it "calls redis_thread_body when in STREAM mode" do
      thread.instance_variable_set(:@thread_mode, :STREAM)
      expect(thread).to receive(:redis_thread_body)

      thread.thread_body
    end

    it "calls file_thread_body when in FILE mode" do
      thread.instance_variable_set(:@thread_mode, :FILE)
      expect(thread).to receive(:file_thread_body)

      thread.thread_body
    end

    it "returns early if thread is cancelled" do
      thread.instance_variable_set(:@cancel_thread, true)
      expect(thread).not_to receive(:setup_thread_body)

      thread.thread_body
    end
  end

  describe "#file_thread_body" do
    let(:thread) { MessagesThread.new(subscription_key, scope: scope, start_offset: "123-0") }
    let(:mock_file_reader) { double("MessageFileReader") }
    let(:log_entries) do
      [
        {"time" => start_time.to_s, "type" => "INFO", "message" => "Test message 1"},
        {"time" => (start_time + 1000).to_s, "type" => "ERROR", "message" => "Test message 2"}
      ]
    end

    before do
      allow(MessageFileReader).to receive(:new).and_return(mock_file_reader)
      allow(mock_file_reader).to receive(:each).and_yield(log_entries[0]).and_yield(log_entries[1])
      allow(thread).to receive(:handle_log_entry).and_return(log_entries[0], log_entries[1])
      allow(thread).to receive(:transmit_results)
    end

    it "processes log entries from file reader" do
      expect(thread).to receive(:handle_log_entry).twice
      expect(thread).to receive(:transmit_results).at_least(:once)

      thread.file_thread_body
    end

    it "switches to STREAM mode after processing files" do
      thread.file_thread_body

      expect(thread.instance_variable_get(:@thread_mode)).to eq(:STREAM)
    end

    it "sets redis offset when available" do
      thread.file_thread_body

      offsets = thread.instance_variable_get(:@offsets)
      expect(offsets[0]).to eq("0-0")
    end

    it "stops processing when thread is cancelled" do
      allow(thread).to receive(:handle_log_entry) do
        thread.instance_variable_set(:@cancel_thread, true)
        log_entries[0]
      end

      expect(thread).to receive(:handle_log_entry).once
      thread.file_thread_body
    end
  end

  describe "#redis_thread_body" do
    let(:thread) { MessagesThread.new(subscription_key, scope: scope, start_offset: "123-0") }

    before do
      allow(thread).to receive(:transmit_results)
    end

    it "processes messages from Redis topics" do
      log_entry = {:msg_id => "msg_id", "time" => start_time}

      allow(OpenC3::EphemeralStore.instance).to receive(:read_topics).and_yield("DEFAULT__openc3_log_messages", "msg_id", {"time" => start_time}, nil)
      expect(thread).to receive(:handle_log_entry).with(log_entry)
      thread.redis_thread_body
    end

    it "updates offsets as messages are processed" do
      thread.instance_variable_set(:@offset_index_by_topic, {"test_topic" => 0})
      thread.instance_variable_set(:@offsets, ["0-0"])

      allow(OpenC3::EphemeralStore.instance).to receive(:read_topics).and_yield("test_topic", "new_msg_id", {"time" => start_time}, nil)

      allow(thread).to receive(:handle_log_entry).and_return(nil)

      thread.redis_thread_body

      expect(thread.instance_variable_get(:@offsets)[0]).to eq("new_msg_id")
    end
  end

  describe "#handle_log_entry" do
    let(:thread) { MessagesThread.new(subscription_key, scope: scope) }
    let(:base_log_entry) do
      {
        "time" => start_time.to_s,
        "type" => "INFO",
        "level" => "INFO",
        "message" => "Test message"
      }
    end

    context "time filtering" do
      it "filters out entries before start_time" do
        thread.instance_variable_set(:@start_time, start_time)
        early_entry = base_log_entry.merge("time" => (start_time - 1000).to_s)

        result = thread.handle_log_entry(early_entry)
        expect(result).to be_nil
      end

      it "allows entries at or after start_time" do
        thread.instance_variable_set(:@start_time, start_time)

        result = thread.handle_log_entry(base_log_entry)
        expect(result).to eq(base_log_entry)
      end

      it "cancels thread and filters entries after end_time" do
        thread.instance_variable_set(:@end_time, end_time)
        late_entry = base_log_entry.merge("time" => (end_time + 1000).to_s)

        logger_messages = []
        allow(OpenC3::Logger).to receive(:info) do |msg|
          logger_messages << msg
        end

        result = thread.handle_log_entry(late_entry)

        expect(result).to be_nil
        expect(thread.instance_variable_get(:@cancel_thread)).to be true
        expect(logger_messages).to include(match(/Finishing.*Reached End Time/))
      end
    end

    context "offset handling" do
      it "saves redis offset and returns nil for offset entries" do
        offset_entry = base_log_entry.merge("type" => "offset", "last_offset" => "123-0")

        result = thread.handle_log_entry(offset_entry)

        expect(result).to be_nil
        expect(thread.instance_variable_get(:@redis_offset)).to eq("123-0")
      end
    end

    context "type filtering" do
      it "filters entries not matching specified types" do
        thread.instance_variable_set(:@types, ["ERROR", "WARN"])

        result = thread.handle_log_entry(base_log_entry)
        expect(result).to be_nil
      end

      it "allows entries matching specified types" do
        thread.instance_variable_set(:@types, ["INFO", "ERROR"])

        result = thread.handle_log_entry(base_log_entry)
        expect(result).to eq(base_log_entry)
      end

      it "allows all entries when no types filter is set" do
        result = thread.handle_log_entry(base_log_entry)
        expect(result).to eq(base_log_entry)
      end
    end

    context "level filtering" do
      let(:debug_entry) { base_log_entry.merge("level" => "DEBUG") }
      let(:info_entry) { base_log_entry.merge("level" => "INFO") }
      let(:warn_entry) { base_log_entry.merge("level" => "WARN") }
      let(:error_entry) { base_log_entry.merge("level" => "ERROR") }
      let(:fatal_entry) { base_log_entry.merge("level" => "FATAL") }

      it "allows DEBUG and above when level is DEBUG" do
        thread.instance_variable_set(:@level, "DEBUG")

        expect(thread.handle_log_entry(debug_entry)).to eq(debug_entry)
        expect(thread.handle_log_entry(info_entry)).to eq(info_entry)
        expect(thread.handle_log_entry(warn_entry)).to eq(warn_entry)
        expect(thread.handle_log_entry(error_entry)).to eq(error_entry)
        expect(thread.handle_log_entry(fatal_entry)).to eq(fatal_entry)
      end

      it "allows INFO and above when level is INFO" do
        thread.instance_variable_set(:@level, "INFO")

        expect(thread.handle_log_entry(debug_entry)).to be_nil
        expect(thread.handle_log_entry(info_entry)).to eq(info_entry)
        expect(thread.handle_log_entry(warn_entry)).to eq(warn_entry)
        expect(thread.handle_log_entry(error_entry)).to eq(error_entry)
        expect(thread.handle_log_entry(fatal_entry)).to eq(fatal_entry)
      end

      it "allows WARN and above when level is WARN" do
        thread.instance_variable_set(:@level, "WARN")

        expect(thread.handle_log_entry(debug_entry)).to be_nil
        expect(thread.handle_log_entry(info_entry)).to be_nil
        expect(thread.handle_log_entry(warn_entry)).to eq(warn_entry)
        expect(thread.handle_log_entry(error_entry)).to eq(error_entry)
        expect(thread.handle_log_entry(fatal_entry)).to eq(fatal_entry)
      end

      it "allows ERROR and above when level is ERROR" do
        thread.instance_variable_set(:@level, "ERROR")

        expect(thread.handle_log_entry(debug_entry)).to be_nil
        expect(thread.handle_log_entry(info_entry)).to be_nil
        expect(thread.handle_log_entry(warn_entry)).to be_nil
        expect(thread.handle_log_entry(error_entry)).to eq(error_entry)
        expect(thread.handle_log_entry(fatal_entry)).to eq(fatal_entry)
      end

      it "only allows FATAL when level is FATAL" do
        thread.instance_variable_set(:@level, "FATAL")

        expect(thread.handle_log_entry(debug_entry)).to be_nil
        expect(thread.handle_log_entry(info_entry)).to be_nil
        expect(thread.handle_log_entry(warn_entry)).to be_nil
        expect(thread.handle_log_entry(error_entry)).to be_nil
        expect(thread.handle_log_entry(fatal_entry)).to eq(fatal_entry)
      end

      it "allows all entries when no level filter is set" do
        expect(thread.handle_log_entry(debug_entry)).to eq(debug_entry)
        expect(thread.handle_log_entry(info_entry)).to eq(info_entry)
        expect(thread.handle_log_entry(warn_entry)).to eq(warn_entry)
        expect(thread.handle_log_entry(error_entry)).to eq(error_entry)
        expect(thread.handle_log_entry(fatal_entry)).to eq(fatal_entry)
      end
    end
  end

  describe "#thread_teardown" do
    let(:thread) { MessagesThread.new(subscription_key, scope: scope) }

    it "sends stream complete marker with empty results" do
      logger_messages = []
      allow(OpenC3::Logger).to receive(:info) do |msg|
        logger_messages << msg
      end

      expect(thread).to receive(:transmit_results).with([], force: true)

      thread.thread_teardown

      expect(logger_messages).to include("MessagesThread - Sending stream complete marker")
    end
  end

  describe "constants" do
    it "defines ALLOWABLE_START_TIME_OFFSET_NSEC" do
      expect(MessagesThread::ALLOWABLE_START_TIME_OFFSET_NSEC).to eq(60 * Time::NSEC_PER_SECOND)
    end
  end
end
