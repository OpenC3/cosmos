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

require "rails_helper"

RSpec.describe StreamingObjectFileReader, type: :model do
  let(:start_time) { Time.at(1748151200) }
  let(:end_time) { Time.at(1748152200) }
  let(:scope) { "DEFAULT" }
  let(:collection) do
    double(
      "StreamingObjectCollection",
      target_info: [["INST__TLM__RAW"], start_time, end_time, {}],
      apply_last_offsets: nil,
    )
  end
  let(:reader) { StreamingObjectFileReader.new(collection, scope: scope) }

  before(:each) do
    @bucket_file_cache = class_double("BucketFileCache")
    stub_const("BucketFileCache", @bucket_file_cache)
    allow(@bucket_file_cache).to receive(:hint)
    allow(@bucket_file_cache).to receive(:unreserve)

    @bucket_utilities = class_double("OpenC3::BucketUtilities")
    stub_const("OpenC3::BucketUtilities", @bucket_utilities)
    allow(@bucket_utilities).to receive(:files_between_time).and_return([])
  end

  # Builds a reader double sitting on a single packet at the given time
  def log_reader(time, bucket_file)
    packet = double("packet", packet_time: time, packet_name: "HEALTH_STATUS")
    double(
      "BufferedPacketLogReader",
      next_packet_time: time,
      buffered_read: packet,
      bucket_file: bucket_file,
      last_offsets: {},
      close: nil,
    )
  end

  def bucket_file(name)
    double(name, topic_prefix: "DEFAULT__TELEMETRY__{INST}")
  end

  describe "#close" do
    # next_packet_and_topic only unreserves a file once its reader runs out of
    # packets. Anything that ends the read early leaves the rest reserved, and
    # a reservation that is never released also blocks BucketFileCache from
    # aging the file out, so it stays on disk for the life of the process.
    it "releases files that are still open" do
      file1 = bucket_file("bucket_file1")
      file2 = bucket_file("bucket_file2")
      reader1 = log_reader(start_time, file1)
      reader2 = log_reader(start_time, file2)
      reader.instance_variable_set(:@open_readers, [reader1, reader2])

      expect(reader1).to receive(:close)
      expect(reader2).to receive(:close)
      expect(@bucket_file_cache).to receive(:unreserve).with(file1)
      expect(@bucket_file_cache).to receive(:unreserve).with(file2)

      reader.close

      expect(reader.instance_variable_get(:@open_readers)).to be_empty
    end

    it "does nothing when no files are open" do
      reader.instance_variable_set(:@open_readers, [])
      expect(@bucket_file_cache).to_not receive(:unreserve)
      expect { reader.close }.to_not raise_error
    end

    it "releases open files when each stops at the end time" do
      file1 = bucket_file("bucket_file1")
      # Sits past @end_time so each returns on the first packet, before this
      # reader ever runs out and gets unreserved the normal way
      reader.instance_variable_set(:@open_readers, [log_reader(end_time + 1, file1)])
      allow(reader).to receive(:open_current_files)

      expect(@bucket_file_cache).to receive(:unreserve).with(file1)

      expect(reader.each { |_packet, _topic| }).to be true
      expect(reader.instance_variable_get(:@open_readers)).to be_empty
    end

    it "releases open files when the caller breaks out of each" do
      file1 = bucket_file("bucket_file1")
      reader.instance_variable_set(:@open_readers, [log_reader(start_time + 1, file1)])
      allow(reader).to receive(:open_current_files)

      expect(@bucket_file_cache).to receive(:unreserve).with(file1)

      reader.each { |_packet, _topic| break } # How a cancelled stream unwinds

      expect(reader.instance_variable_get(:@open_readers)).to be_empty
    end

    it "leaves nothing reserved when every reader runs out normally" do
      file1 = bucket_file("bucket_file1")
      exhausted = double("BufferedPacketLogReader", next_packet_time: nil, bucket_file: file1,
                                                    last_offsets: {}, close: nil)
      reader.instance_variable_set(:@open_readers, [exhausted])
      allow(reader).to receive(:open_current_files)

      # Unreserved once by next_packet_and_topic, and not again by close
      expect(@bucket_file_cache).to receive(:unreserve).with(file1).once

      expect(reader.each { |_packet, _topic| }).to be false
    end
  end
end
