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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/io/raw_logger'
require 'openc3/utilities/aws_bucket'

module OpenC3
  describe RawLogger do
    before(:each) do
      @files = {}
      s3 = double("AwsS3Client").as_null_object
      allow(Aws::S3::Client).to receive(:new).and_return(s3)
      allow(s3).to receive(:put_object) do |args|
        @files[File.basename(args[:key])] = args[:body].read
      end
    end

    after(:each) do
      # Clean after each so we can check for single log files
      clean_config()
    end

    describe "initialize" do
      it "complains with not enough arguments" do
        expect { RawLogger.new('MYINT') }.to raise_error(ArgumentError)
      end

      it "complains with an unknown log type" do
        expect { RawLogger.new('MYINT', :BOTH) }.to raise_error(/log_type must be :READ or :WRITE/)
      end

      it "creates a raw write log" do
        raw_logger = RawLogger.new('MYINT', :WRITE, true, 100000)
        raw_logger.write("\x00\x01\x02\x03")
        raw_logger.stop

        expect(@files.keys[0]).to match(/.*myint_stream_write.bin.gz/)
        io = StringIO.new(@files.values[0])
        gz = Zlib::GzipReader.new(io)
        bin = gz.read
        expect(bin).to eql "\x00\x01\x02\x03"
      end

      it "creates a raw read log" do
        raw_logger = RawLogger.new('MYINT', :READ, true, 100000)
        raw_logger.write("\x00\x01\x02\x03")
        raw_logger.stop

        expect(@files.keys[0]).to match(/.*myint_stream_read.bin.gz/)
        io = StringIO.new(@files.values[0])
        gz = Zlib::GzipReader.new(io)
        bin = gz.read
        expect(bin).to eql "\x00\x01\x02\x03"
      end
    end

    describe "write" do
      it "does not write data if logging is disabled" do
        raw_logger = RawLogger.new('MYINT', :WRITE, false, 100000)
        raw_logger.write("\x00\x01\x02\x03")
        expect(@files).to be_empty
      end

      it "cycles the log when it a size" do
        raw_logger = RawLogger.new('MYINT', :WRITE, true, 200000)
        raw_logger.write("\x00\x01\x02\x03" * 25000) # size 100000
        raw_logger.write("\x00\x01\x02\x03" * 25000) # size 200000
        expect(@files.keys.length).to eql 0 # hasn't cycled yet
        sleep(1) # allow copy to happen
        raw_logger.write("\x00") # size 200001
        expect(@files.keys.length).to eql 1
        raw_logger.stop
        sleep(1) # allow copy to happen
        expect(@files.keys.length).to eql 2
      end

      it "handles errors creating the log file" do
        capture_io do |stdout|
          allow(File).to receive(:new) { raise "Error" }
          raw_logger = RawLogger.new('MYINT', :WRITE, true, 200)
          raw_logger.write("\x00\x01\x02\x03")
          raw_logger.stop
          expect(stdout.string).to match("Error opening")
        end
      end

      it "handles errors closing the log file" do
        capture_io do |stdout|
          allow(BucketUtilities).to receive(:move_log_file_to_bucket) { raise "Error" }
          raw_logger = RawLogger.new('MYINT', :WRITE, true, 200)
          raw_logger.write("\x00\x01\x02\x03")
          raw_logger.stop
          expect(stdout.string).to match("Error closing")
        end
      end

      it "handles errors writing the log file" do
        capture_io do |stdout|
          raw_logger = RawLogger.new('MYINT', :WRITE, true, 200)
          raw_logger.write("\x00\x01\x02\x03")
          allow(raw_logger.instance_variable_get(:@file)).to receive(:write) { raise "Error" }
          raw_logger.write("\x00\x01\x02\x03")
          raw_logger.stop
          expect(stdout.string).to match("Error writing")
        end
      end
    end

    describe "start and stop" do
      it "enables and disable logging" do
        raw_logger = RawLogger.new('MYINT', :WRITE, false, 200)
        expect(raw_logger.logging_enabled).to be false
        raw_logger.start
        expect(raw_logger.logging_enabled).to be true
        raw_logger.write("\x00\x01\x02\x03")
        raw_logger.stop
        expect(raw_logger.logging_enabled).to be false
        expect(@files.keys.length).to eql 1
      end
    end
  end
end
