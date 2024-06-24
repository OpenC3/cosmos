# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/logs/buffered_packet_log_writer'
require 'openc3/logs/packet_log_reader'
require 'openc3/utilities/aws_bucket'
require 'fileutils'
require 'zlib'

module OpenC3
  describe BufferedPacketLogWriter do
    before(:all) do
      setup_system()
      @log_dir = File.expand_path(File.join(SPEC_DIR, 'install', 'outputs', 'logs'))
      FileUtils.mkdir_p(@log_dir)
    end

    before(:each) do
      @files = {}
      s3 = double("AwsS3Client").as_null_object
      allow(Aws::S3::Client).to receive(:new).and_return(s3)
      allow(s3).to receive(:put_object) do |args|
        @files[File.basename(args[:key])] = args[:body].read
      end
    end

    describe "initialize" do
      it "stores the buffer depth" do
        bplw = BufferedPacketLogWriter.new(@log_dir, "test")
        expect(bplw.instance_variable_get(:@buffer_depth)).to eql 60
        bplw.shutdown
        sleep 0.1
      end
    end

    describe "buffered_write" do
      it "buffers data writes" do
        time1 = Time.now.to_nsec_from_epoch
        time2 = time1 += 1_000_000_000
        time3 = time2 += 1_000_000_000
        timestamp1 = Time.from_nsec_from_epoch(time1).to_timestamp
        timestamp3 = Time.from_nsec_from_epoch(time3).to_timestamp
        label = 'test'
        # Create buffer depth of three
        bplw = BufferedPacketLogWriter.new(@log_dir, label, true, nil, 1_000_000_000, nil, nil, true, 3)
        expect(bplw.instance_variable_get(:@file_size)).to eq 0
        expect(bplw.buffered_first_time_nsec).to be_nil
        bplw.buffered_write(:RAW_PACKET, :TLM, 'TGT1', 'PKT1', time1, false, "\x01\x02", nil, '0-0')
        expect(bplw.instance_variable_get(:@file_size)).to eq 8
        expect(bplw.buffered_first_time_nsec).to eq time1
        bplw.buffered_write(:RAW_PACKET, :TLM, 'TGT2', 'PKT2', time2, false, "\x03\x04", nil, '0-0')
        expect(bplw.instance_variable_get(:@file_size)).to eq 8
        expect(bplw.buffered_first_time_nsec).to eq time1
        bplw.buffered_write(:RAW_PACKET, :TLM, 'TGT2', 'PKT2', time3, false, "\x05\x06", nil, '0-0')
        expect(bplw.instance_variable_get(:@file_size)).to_not eq 8
        expect(bplw.buffered_first_time_nsec).to eq time1
        bplw.shutdown
        sleep 0.1 # Allow for shutdown thread "copy" to S3
        expect(bplw.buffered_first_time_nsec).to be_nil # set to nil in close_file

        # Files copied to S3 are named via the first_time, last_time, label
        expect(@files.keys).to contain_exactly("#{timestamp1}__#{timestamp3}__#{label}.bin.gz")

        # Verify the packets by using PacketLogReader
        bin = @files["#{timestamp1}__#{timestamp3}__#{label}.bin.gz"]
        gz = Zlib::GzipReader.new(StringIO.new(bin))
        File.open('test_log.bin', 'wb') { |file| file.write gz.read }
        reader = PacketLogReader.new
        reader.open('test_log.bin')
        pkt = reader.read
        expect(pkt.target_name).to eq 'TGT1'
        expect(pkt.packet_name).to eq 'PKT1'
        expect(pkt.stored).to be false
        expect(pkt.buffer).to eq "\x01\x02"
        pkt = reader.read
        expect(pkt.target_name).to eq 'TGT2'
        expect(pkt.packet_name).to eq 'PKT2'
        expect(pkt.stored).to be false
        expect(pkt.buffer).to eq "\x03\x04"
        pkt = reader.read
        expect(pkt.target_name).to eq 'TGT2'
        expect(pkt.packet_name).to eq 'PKT2'
        expect(pkt.stored).to be false
        expect(pkt.buffer).to eq "\x05\x06"
        pkt = reader.read
        expect(pkt).to be_nil
        reader.close()
        FileUtils.rm_f 'test_log.bin'
      end
    end
  end
end
