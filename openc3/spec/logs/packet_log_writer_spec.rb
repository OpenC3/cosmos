# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/logs/packet_log_writer'
require 'openc3/logs/packet_log_reader'
require 'openc3/utilities/aws_bucket'
require 'fileutils'
require 'zlib'

module OpenC3
  describe PacketLogWriter do
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
      it "raises with a cycle_time < #{PacketLogWriter::CYCLE_TIME_INTERVAL}" do
        expect { PacketLogWriter.new(@log_dir, "test", true, 0, nil) }.to raise_error("cycle_time must be >= #{PacketLogWriter::CYCLE_TIME_INTERVAL}")
        expect { PacketLogWriter.new(@log_dir, "test", true, 1, nil) }.to raise_error("cycle_time must be >= #{PacketLogWriter::CYCLE_TIME_INTERVAL}")
        expect { PacketLogWriter.new(@log_dir, "test", true, 1.5, nil) }.to raise_error("cycle_time must be >= #{PacketLogWriter::CYCLE_TIME_INTERVAL}")
      end
    end

    describe "write" do
      it "raises with invalid type" do
        capture_io do |stdout|
          plw = PacketLogWriter.new(@log_dir, 'test')
          plw.write(:BLAH, :CMD, 'TGT', 'CMD', 0, true, "\x01\x02", nil, '0-0')
          expect(stdout.string).to match("Unknown entry_type: BLAH")
          plw.shutdown
          sleep 0.1
        end
      end

      it "writes binary data to a binary file" do
        first_time = Time.now.to_nsec_from_epoch
        last_time = first_time += 1_000_000_000
        first_timestamp = Time.from_nsec_from_epoch(first_time).to_timestamp
        last_timestamp = Time.from_nsec_from_epoch(last_time).to_timestamp
        label = 'test'
        plw = PacketLogWriter.new(@log_dir, label)
        expect(plw.instance_variable_get(:@file_size)).to eq 0
        # Mark the first packet as "stored" (true)
        plw.write(:RAW_PACKET, :TLM, 'TGT1', 'PKT1', first_time, true, "\x01\x02", nil, '0-0')
        expect(plw.instance_variable_get(:@file_size)).to_not eq 0
        plw.write(:RAW_PACKET, :TLM, 'TGT2', 'PKT2', last_time, false, "\x03\x04", nil, '0-0')
        plw.shutdown
        sleep 0.1 # Allow for shutdown thread "copy" to S3

        # Files copied to S3 are named via the first_time, last_time, label
        expect(@files.keys).to contain_exactly("#{first_timestamp}__#{last_timestamp}__#{label}.bin.gz")

        # Verify the OPENC3 header on the binary file
        bin = @files["#{first_timestamp}__#{last_timestamp}__#{label}.bin.gz"]
        io = StringIO.new(bin)
        gz = Zlib::GzipReader.new(io)
        bin = gz.read
        results = bin.unpack("Z8")[0]
        expect(results).to eq 'COSMOS5_'
        # puts bin.formatted

        # Verify the packets by using PacketLogReader
        File.open('test_log.bin', 'wb') { |file| file.write bin }
        reader = PacketLogReader.new
        reader.open('test_log.bin')
        pkt = reader.read
        expect(pkt.target_name).to eq 'TGT1'
        expect(pkt.packet_name).to eq 'PKT1'
        expect(pkt.stored).to be true
        expect(pkt.buffer).to eq "\x01\x02"
        pkt = reader.read
        expect(pkt.target_name).to eq 'TGT2'
        expect(pkt.packet_name).to eq 'PKT2'
        expect(pkt.stored).to be false
        expect(pkt.buffer).to eq "\x03\x04"
        pkt = reader.read
        expect(pkt).to be_nil
        reader.close()
        FileUtils.rm_f 'test_log.bin'
      end

      it "correctly writes multiple files in a row" do
        first_time = Time.now.to_nsec_from_epoch
        last_time = first_time += 1_000_000_000
        first_time2 = first_time + 1
        last_time2 = last_time + 1
        first_timestamp = Time.from_nsec_from_epoch(first_time).to_timestamp
        last_timestamp = Time.from_nsec_from_epoch(last_time).to_timestamp
        first_timestamp2 = Time.from_nsec_from_epoch(first_time2).to_timestamp
        last_timestamp2 = Time.from_nsec_from_epoch(last_time2).to_timestamp
        label = 'test'
        plw = PacketLogWriter.new(@log_dir, label)
        expect(plw.instance_variable_get(:@file_size)).to eq 0
        # Mark the first packet as "stored" (true)
        plw.write(:RAW_PACKET, :TLM, 'TGT1', 'PKT1', first_time, true, "\x01\x02", nil, '0-0')
        expect(plw.instance_variable_get(:@file_size)).to_not eq 0
        plw.write(:RAW_PACKET, :TLM, 'TGT2', 'PKT2', last_time, false, "\x03\x04", nil, '0-0')
        plw.start_new_file
        expect(plw.instance_variable_get(:@file_size)).to eq PacketLogWriter::OPENC3_FILE_HEADER.length
        plw.write(:RAW_PACKET, :TLM, 'TGT2', 'PKT2', first_time2, false, "\x03\x04", nil, '0-0')
        expect(plw.instance_variable_get(:@file_size)).to_not eq 0
        plw.write(:RAW_PACKET, :TLM, 'TGT1', 'PKT1', last_time2, true, "\x01\x02", nil, '0-0')
        plw.shutdown
        sleep 0.2 # Allow for shutdown thread "copy" to S3

        # Files copied to S3 are named via the first_time, last_time, label
        expect(@files.keys).to contain_exactly(
          "#{first_timestamp}__#{last_timestamp}__#{label}.bin.gz",
          "#{first_timestamp2}__#{last_timestamp2}__#{label}.bin.gz"
        )

        # Verify the OPENC3 header on the binary file
        bin = @files["#{first_timestamp}__#{last_timestamp}__#{label}.bin.gz"]
        io = StringIO.new(bin)
        gz = Zlib::GzipReader.new(io)
        bin = gz.read
        results = bin.unpack("Z8")[0]
        expect(results).to eq 'COSMOS5_'
        # puts bin.formatted

        # Verify the OPENC3 header on the binary file
        bin2 = @files["#{first_timestamp2}__#{last_timestamp2}__#{label}.bin.gz"]
        io2 = StringIO.new(bin2)
        gz2 = Zlib::GzipReader.new(io2)
        bin2 = gz2.read
        results = bin2.unpack("Z8")[0]
        expect(results).to eq 'COSMOS5_'
        # puts bin.formatted

        # Verify the packets by using PacketLogReader
        File.open('test_log.bin', 'wb') { |file| file.write bin }
        reader = PacketLogReader.new
        reader.open('test_log.bin')
        pkt = reader.read
        expect(pkt.target_name).to eq 'TGT1'
        expect(pkt.packet_name).to eq 'PKT1'
        expect(pkt.stored).to be true
        expect(pkt.buffer).to eq "\x01\x02"
        pkt = reader.read
        expect(pkt.target_name).to eq 'TGT2'
        expect(pkt.packet_name).to eq 'PKT2'
        expect(pkt.stored).to be false
        expect(pkt.buffer).to eq "\x03\x04"
        pkt = reader.read
        expect(pkt).to be_nil
        reader.close()
        FileUtils.rm_f 'test_log.bin'

        File.open('test_log.bin', 'wb') { |file| file.write bin2 }
        reader = PacketLogReader.new
        reader.open('test_log.bin')
        pkt = reader.read
        expect(pkt.target_name).to eq 'TGT2'
        expect(pkt.packet_name).to eq 'PKT2'
        expect(pkt.stored).to be false
        expect(pkt.buffer).to eq "\x03\x04"
        pkt = reader.read
        expect(pkt.target_name).to eq 'TGT1'
        expect(pkt.packet_name).to eq 'PKT1'
        expect(pkt.stored).to be true
        expect(pkt.buffer).to eq "\x01\x02"
        pkt = reader.read
        expect(pkt).to be_nil
        reader.close()
        FileUtils.rm_f 'test_log.bin'
      end

      it "cycles the log when it a size" do
        time = Time.now.to_nsec_from_epoch
        target_name = 'TGT'
        packet_name = 'PKT'
        pkt = Packet.new(target_name, packet_name)
        pkt.buffer = "\x01\x02\x03\x04"
        label = 'test'

        # Figure out the exact size of the file using PacketLogWriter constants
        file_size = PacketLogWriter::OPENC3_FILE_HEADER.length
        # The target and packet declarations are only repeated once per target / packet
        tmp = Array.new(PacketLogWriter::OPENC3_TARGET_DECLARATION_PACK_ITEMS, 0)
        data = tmp.pack(PacketLogWriter::OPENC3_TARGET_DECLARATION_PACK_DIRECTIVE)
        file_size += data.length + target_name.length
        tmp = Array.new(PacketLogWriter::OPENC3_PACKET_DECLARATION_PACK_ITEMS, 0)
        data = tmp.pack(PacketLogWriter::OPENC3_PACKET_DECLARATION_PACK_DIRECTIVE)
        file_size += data.length + packet_name.length

        # Set the file size to contain exactly two packets
        tmp = Array.new(PacketLogWriter::OPENC3_PACKET_PACK_ITEMS, 0)
        data = tmp.pack(PacketLogWriter::OPENC3_PACKET_PACK_DIRECTIVE)
        file_size += 2 * (data.length + pkt.buffer.length)

        plw = PacketLogWriter.new(@log_dir, label, true, nil, file_size)
        plw.write(:RAW_PACKET, :TLM, target_name, packet_name, time, false, pkt.buffer, nil, '0-0')
        time += 1_000_000_000
        plw.write(:RAW_PACKET, :TLM, target_name, packet_name, time, false, pkt.buffer, nil, '0-0')
        time += 1_000_000_000
        sleep 0.1

        # At this point we've written two packets ... our file should be full but not closed
        expect(plw.instance_variable_get(:@file_size)).to eq file_size
        expect(@files.keys.length).to eq 0 # No files have been written out

        # One more write should cause the first file to close and new one to open
        plw.write(:RAW_PACKET, :TLM, target_name, packet_name, time, false, pkt.buffer, nil, '0-0')
        sleep 0.2
        expect(@files.keys.length).to eq 1 # Initial files

        plw.shutdown
        sleep 0.2
        expect(@files.keys.length).to eq 2
      end

      it "cycles the log after a set amount of time" do
        # Monkey patch the constant so the test doesn't take forever
        # Fortify says Access Specifier Manipulation
        # but this is test code only
        default_cycle_time_interval = LogWriter::CYCLE_TIME_INTERVAL
        LogWriter.__send__(:remove_const, :CYCLE_TIME_INTERVAL)
        LogWriter.const_set(:CYCLE_TIME_INTERVAL, 0.1)

        time = Time.now.to_nsec_from_epoch
        label = 'test'
        plw = PacketLogWriter.new(@log_dir, label, true, 1, nil) # cycle every sec
        15.times do
          plw.write(:RAW_PACKET, :TLM, 'TGT1', 'PKT1', time, true, "\x01\x02", nil, '0-0')
          time += 200_000_000
          sleep 0.2
        end
        plw.shutdown
        sleep 0.2
        # Since we wrote about 3s we should see 3 separate cycles
        expect(@files.keys.length).to eq 3

        # Monkey patch the constant back to the default
        # Fortify says Access Specifier Manipulation
        # but this is test code only
        LogWriter.__send__(:remove_const, :CYCLE_TIME_INTERVAL)
        LogWriter.const_set(:CYCLE_TIME_INTERVAL, default_cycle_time_interval)
      end

      it "handles errors creating the log file" do
        capture_io do |stdout|
          allow(File).to receive(:new) { raise "Error" }
          plw = PacketLogWriter.new(@log_dir, "test")
          plw.write(:RAW_PACKET, :TLM, 'TGT1', 'PKT1', Time.now.to_nsec_from_epoch, true, "\x01\x02", nil, '0-0')
          sleep 0.1
          plw.stop
          expect(stdout.string).to include("ERROR")
          plw.shutdown
          sleep 0.1
        end
      end

      it "handles errors closing the log file" do
        capture_io do |stdout|
          allow_any_instance_of(File).to receive(:close).and_raise('Nope')
          plw = PacketLogWriter.new(@log_dir, "test")
          plw.write(:RAW_PACKET, :TLM, 'TGT1', 'PKT1', Time.now.to_nsec_from_epoch, true, "\x01\x02", nil, '0-0')
          sleep 0.1
          plw.stop
          expect(stdout.string).to match("Error closing")
          plw.shutdown
          sleep 0.1
        end
      end

      it "raises an error after #{PacketLogWriter::OPENC3_MAX_TARGET_INDEX} targets" do
        capture_io do |stdout|
          plw = PacketLogWriter.new(@log_dir, "test")
          # Plus 2 because 0 to MAX are all valid so +1 is ok and +2 errors
          (PacketLogWriter::OPENC3_MAX_TARGET_INDEX + 2).times do |i|
            plw.write(:RAW_PACKET, :TLM, "TGT#{i}", "PKT", Time.now.to_nsec_from_epoch, true, "\x01\x02", nil, '0-0')
          end
          expect(stdout.string).to match("Target Index Overflow")
          plw.shutdown
          sleep 1
        end
      end

      it "raises an error after #{PacketLogWriter::OPENC3_MAX_PACKET_INDEX} packets" do
        capture_io do |stdout|
          plw = PacketLogWriter.new(@log_dir, "test")
          # Plus 2 because 0 to MAX are all valid so +1 is ok and +2 errors
          (PacketLogWriter::OPENC3_MAX_PACKET_INDEX + 2).times do |i|
            plw.write(:RAW_PACKET, :TLM, "TGT", "PKT#{i}", Time.now.to_nsec_from_epoch, true, "\x01\x02", nil, '0-0')
          end
          expect(stdout.string).to match("Packet Index Overflow")
          plw.shutdown
          sleep 1
        end
      end
    end

    describe "start" do
      it "enables logging" do
        plw = PacketLogWriter.new(@log_dir, 'test', false) # Logging not enabled
        plw.write(:RAW_PACKET, :CMD, 'TGT', 'CMD', Time.now.to_nsec_from_epoch, true, "\x01\x02", nil, '0-0')
        expect(plw.instance_variable_get(:@file_size)).to eq 0

        plw.start # Enable logging
        plw.write(:RAW_PACKET, :CMD, 'TGT', 'CMD', Time.now.to_nsec_from_epoch, true, "\x01\x02", nil, '0-0')
        expect(plw.instance_variable_get(:@file_size)).to_not eq 0

        plw.shutdown
        sleep 0.1
        expect(@files.keys.length).to eq 1
      end
    end

    describe "shutdown" do
      it "closes the file and writes out the buffer" do
        plw = PacketLogWriter.new(@log_dir, 'test')
        plw.write(:RAW_PACKET, :CMD, 'TGT', 'CMD', Time.now.to_nsec_from_epoch, true, "\x01\x02", nil, '0-0')
        expect(plw.instance_variable_get(:@file_size)).to_not eq 0

        plw.shutdown
        sleep 0.1
        expect(plw.instance_variable_get(:@file_size)).to eq 0
        expect(@files.keys.length).to eq 1
      end

      it "closes the file cleanly even if no packet written" do
        plw = PacketLogWriter.new(@log_dir, 'test')
        plw.start_new_file
        expect(plw.instance_variable_get(:@file_size)).to eq PacketLogWriter::OPENC3_FILE_HEADER.length
        capture_io do |stdout|
          plw.shutdown
          expect(stdout.string).to include("Log File Closed :")
          # No error even though no packets were written
          expect(stdout.string).to_not include("Error closing")
        end
        expect(@files.keys.length).to eq 0
        sleep 0.1
      end
    end
  end
end
