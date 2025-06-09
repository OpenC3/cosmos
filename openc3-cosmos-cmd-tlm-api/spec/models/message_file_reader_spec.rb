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

RSpec.describe MessageFileReader, type: :model do
  let(:start_time) { 1748151200000000000 } # Sun May 25 2025 05:33:20 GMT+0000
  let(:end_time) { 1748152200000000000 } # Sun May 25 2025 05:50:00 GMT+0000
  let(:start_time_formatted) { 202505250533200000000 }
  let(:end_time_formatted) { 202505250550000000000 }
  let(:scope) { "DEFAULT" }

  before(:each) do
    # Mock BucketFileCache
    @bucket_file_cache = class_double("BucketFileCache")
    stub_const("BucketFileCache", @bucket_file_cache)
    allow(@bucket_file_cache).to receive(:hint)
    allow(@bucket_file_cache).to receive(:reserve).and_return(double("bucket_file", local_path: "/tmp/test.txt"))
    allow(@bucket_file_cache).to receive(:unreserve)

    # Mock OpenC3::BucketUtilities
    @bucket_utilities = class_double("OpenC3::BucketUtilities")
    stub_const("OpenC3::BucketUtilities", @bucket_utilities)
    allow(@bucket_utilities).to receive(:files_between_time).and_return([])

    # Mock MessageLogReader
    @message_log_reader = double("MessageLogReader")
    allow(MessageLogReader).to receive(:new).and_return(@message_log_reader)
    allow(@message_log_reader).to receive(:open)
    allow(@message_log_reader).to receive(:close)
    allow(@message_log_reader).to receive(:bucket_file).and_return(double("bucket_file"))
    allow(@message_log_reader).to receive(:next_entry_time).and_return(nil)
    allow(@message_log_reader).to receive(:read).and_return(nil)

    # Mock environment variable
    ENV["OPENC3_LOGS_BUCKET"] = "test-bucket"
  end

  after(:each) do
    ENV.delete("OPENC3_LOGS_BUCKET")
  end

  describe "#initialize" do
    it "initializes with start_time, end_time, and scope" do
      reader = MessageFileReader.new(start_time: start_time, end_time: end_time, scope: scope)
      expect(reader.instance_variable_get(:@scope)).to eq(scope)
      expect(reader.instance_variable_get(:@start_time)).to eq(start_time)
      expect(reader.instance_variable_get(:@end_time)).to eq(end_time)
      expect(reader.instance_variable_get(:@start_time_object)).to be_a(Time)
      expect(reader.instance_variable_get(:@end_time_object)).to be_a(Time)
      expect(reader.instance_variable_get(:@open_readers)).to eq([])
      expect(reader.instance_variable_get(:@extend_file_list)).to be_truthy
    end

    it "handles nil end_time" do
      reader = MessageFileReader.new(start_time: start_time, end_time: nil, scope: scope)
      expect(reader.instance_variable_get(:@start_time_object)).to be_a(Time)
      expect(reader.instance_variable_get(:@end_time_object)).to be_nil
    end

    it "builds file list and hints bucket cache" do
      expect(@bucket_utilities).to receive(:files_between_time).with(
        "test-bucket",
        "DEFAULT/text_logs/openc3_log_messages",
        Time.from_nsec_from_epoch(start_time),
        Time.from_nsec_from_epoch(end_time),
        file_suffix: ".txt",
        overlap: true
      )
      expect(@bucket_file_cache).to receive(:hint)

      MessageFileReader.new(start_time: start_time, end_time: end_time, scope: scope)
    end
  end

  describe "#each" do
    let(:reader) { MessageFileReader.new(start_time: start_time, end_time: end_time, scope: scope) }

    it "yields log entries within time range" do
      log_entry = {"time" => start_time + 1000}
      allow(reader).to receive(:read).and_return(log_entry, nil)

      yielded_entries = []
      result = reader.each { |entry| yielded_entries << entry }

      expect(yielded_entries).to eq([log_entry])
      expect(result).to be_falsey
    end

    it "skips entries before start_time" do
      early_entry = {"time" => start_time - 1000}
      valid_entry = {"time" => start_time + 1000}
      allow(reader).to receive(:read).and_return(early_entry, valid_entry, nil)

      yielded_entries = []
      reader.each { |entry| yielded_entries << entry }

      expect(yielded_entries).to eq([valid_entry])
    end

    it "returns true when end_time is reached" do
      log_entry = {"time" => end_time + 1000}
      allow(reader).to receive(:read).and_return(log_entry)

      result = reader.each { |entry| }
      expect(result).to be_truthy
    end
  end

  describe "#read" do
    let(:reader) { MessageFileReader.new(start_time: start_time, end_time: end_time, scope: scope) }

    it "opens current files and returns next log entry" do
      expect(reader).to receive(:open_current_files)
      expect(reader).to receive(:next_log_entry).and_return({"time" => start_time})

      result = reader.read
      expect(result).to eq({"time" => start_time})
    end
  end

  describe "#open_current_files" do
    let(:reader) { MessageFileReader.new(start_time: start_time, end_time: end_time, scope: scope) }

    before(:each) do
      reader.instance_variable_set(:@open_readers, [])
    end

    it "opens files when current time is appropriate" do
      file_path = "scope/logs/#{start_time}__#{end_time}__DEFAULT__INST__PARAMS__rt__raw.txt"
      reader.instance_variable_set(:@file_list, [file_path])

      bucket_file = double("bucket_file", local_path: "/tmp/test.txt")
      allow(@bucket_file_cache).to receive(:reserve).and_return(bucket_file)
      allow(reader).to receive(:get_file_times).and_return([Time.at(start_time / 1_000_000_000.0), Time.at(end_time / 1_000_000_000.0)])

      expect(MessageLogReader).to receive(:new).with(bucket_file).and_return(@message_log_reader)
      expect(@message_log_reader).to receive(:open).with("/tmp/test.txt")

      reader.open_current_files

      open_readers = reader.instance_variable_get(:@open_readers)
      expect(open_readers).to include(@message_log_reader)
    end

    it "extends file list when no files available and extend_file_list is true" do
      reader.instance_variable_set(:@file_list, [])
      reader.instance_variable_set(:@extend_file_list, true)

      expect(reader).to receive(:build_file_list)
      expect(@bucket_file_cache).to receive(:hint)

      reader.open_current_files

      expect(reader.instance_variable_get(:@extend_file_list)).to be_falsey
    end

    it "does not extend file list when extend_file_list is false" do
      reader.instance_variable_set(:@file_list, [])
      reader.instance_variable_set(:@extend_file_list, false)

      expect(reader).not_to receive(:build_file_list)

      reader.open_current_files
    end
  end

  describe "#next_log_entry" do
    let(:reader) { MessageFileReader.new(start_time: start_time, end_time: end_time, scope: scope) }

    it "returns entry from reader with earliest timestamp" do
      reader1 = double("reader1")
      reader2 = double("reader2")
      bucket_file1 = double("bucket_file1")
      bucket_file2 = double("bucket_file2")

      allow(reader1).to receive(:next_entry_time).and_return(1000)
      allow(reader1).to receive(:bucket_file).and_return(bucket_file1)
      allow(reader2).to receive(:next_entry_time).and_return(2000)
      allow(reader2).to receive(:bucket_file).and_return(bucket_file2)

      reader.instance_variable_set(:@open_readers, [reader1, reader2])

      log_entry = {"time" => "1000"}
      expect(reader1).to receive(:read).and_return(log_entry)

      result = reader.next_log_entry
      expect(result).to eq(log_entry)
    end

    it "closes readers that have no more entries" do
      reader1 = double("reader1")
      bucket_file1 = double("bucket_file1")

      allow(reader1).to receive(:next_entry_time).and_return(nil)
      allow(reader1).to receive(:bucket_file).and_return(bucket_file1)

      reader.instance_variable_set(:@open_readers, [reader1])

      expect(reader1).to receive(:close)
      expect(@bucket_file_cache).to receive(:unreserve).with(bucket_file1)

      result = reader.next_log_entry

      open_readers = reader.instance_variable_get(:@open_readers)
      expect(open_readers).to be_empty
    end

    it "updates current_time_object with entry time" do
      reader1 = double("reader1")
      bucket_file1 = double("bucket_file1")

      allow(reader1).to receive(:next_entry_time).and_return(1500)
      allow(reader1).to receive(:bucket_file).and_return(bucket_file1)

      reader.instance_variable_set(:@open_readers, [reader1])

      log_entry = {"time" => "1500"}
      allow(reader1).to receive(:read).and_return(log_entry)

      expect(Time).to receive(:from_nsec_from_epoch).with(1500)

      reader.next_log_entry
    end

    it "returns nil when no more files or readers available" do
      reader.instance_variable_set(:@open_readers, [])
      reader.instance_variable_set(:@file_list, [])

      result = reader.next_log_entry
      expect(result).to be_nil
    end
  end

  describe "#build_file_list" do
    let(:reader) { MessageFileReader.new(start_time: start_time, end_time: end_time, scope: scope) }

    before(:each) do
      # Reset the file list for testing
      reader.instance_variable_set(:@file_list, [])
      reader.instance_variable_set(:@historical_file_list, {})
    end

    it "calls BucketUtilities.files_between_time with correct parameters" do
      expect(@bucket_utilities).to receive(:files_between_time).with(
        "test-bucket",
        "DEFAULT/text_logs/openc3_log_messages",
        anything,
        anything,
        file_suffix: ".txt",
        overlap: false
      ).and_return(["file1.txt", "file2.txt"])

      reader.build_file_list
    end

    it "sorts the file list" do
      files = ["file3.txt", "file1.txt", "file2.txt"]
      allow(@bucket_utilities).to receive(:files_between_time).and_return(files)

      reader.build_file_list
      file_list = reader.instance_variable_get(:@file_list)

      expect(file_list).to eq(["file1.txt", "file2.txt", "file3.txt"])
    end

    it "removes files that have been seen before" do
      files = ["file1.txt", "file2.txt", "file3.txt"]
      allow(@bucket_utilities).to receive(:files_between_time).and_return(files)

      # Mark file2.txt as already seen
      reader.instance_variable_set(:@historical_file_list, {"file2.txt" => true})

      reader.build_file_list
      file_list = reader.instance_variable_get(:@file_list)

      expect(file_list).to eq(["file1.txt", "file3.txt"])
    end

    it "marks new files as seen in historical_file_list" do
      files = ["file1.txt", "file2.txt"]
      allow(@bucket_utilities).to receive(:files_between_time).and_return(files)

      reader.build_file_list
      historical_list = reader.instance_variable_get(:@historical_file_list)

      expect(historical_list["file1.txt"]).to be_truthy
      expect(historical_list["file2.txt"]).to be_truthy
    end
  end

  describe "#get_file_times" do
    let(:reader) { MessageFileReader.new(start_time: start_time, end_time: end_time, scope: scope) }

    it "parses file timestamps from bucket path" do
      bucket_path = "scope/logs/#{start_time_formatted}__#{end_time_formatted}__DEFAULT__INST__PARAMS__rt__raw.txt"

      start_time_obj = Time.from_nsec_from_epoch(start_time)
      end_time_obj = Time.from_nsec_from_epoch(end_time)

      file_start_time, file_end_time = reader.get_file_times(bucket_path)

      expect(file_start_time).to eq(start_time_obj)
      expect(file_end_time).to eq(end_time_obj)
    end
  end
end
