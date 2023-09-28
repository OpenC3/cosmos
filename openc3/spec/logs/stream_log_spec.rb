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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/logs/stream_log'
require 'openc3/utilities/aws_bucket'

module OpenC3
  describe StreamLog do
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
      @stream_log.shutdown if @stream_log
      wait 0.01
    end

    describe "initialize" do
      it "complains with not enough arguments" do
        expect { StreamLog.new('MYINT') }.to raise_error(ArgumentError)
      end

      it "complains with an unknown log type" do
        expect { StreamLog.new('MYINT', :BOTH) }.to raise_error(/log_type must be :READ or :WRITE/)
      end

      it "creates a raw write log" do
        @stream_log = StreamLog.new('MYINT', :WRITE)
        @stream_log.write("\x00\x01\x02\x03")
        @stream_log.stop
        wait 0.1
        expect(@files.keys[0]).to match(/.*myint_stream_write.bin.gz/)
        io = StringIO.new(@files.values[0])
        gz = Zlib::GzipReader.new(io)
        bin = gz.read
        gz.close
        expect(bin).to eql "\x00\x01\x02\x03"
      end

      it "creates a raw read log" do
        @stream_log = StreamLog.new('MYINT', :READ)
        @stream_log.write("\x00\x01\x02\x03")
        @stream_log.stop
        wait 0.1
        expect(@files.keys[0]).to match(/.*myint_stream_read.bin.gz/)
        io = StringIO.new(@files.values[0])
        gz = Zlib::GzipReader.new(io)
        bin = gz.read
        expect(bin).to eql "\x00\x01\x02\x03"
      end
    end

    describe "write" do
      it "does not write data if logging is disabled" do
        @stream_log = StreamLog.new('MYINT', :WRITE)
        @stream_log.stop
        @stream_log.write("\x00\x01\x02\x03")
        expect(@stream_log.instance_variable_get(:@file_size)).to eql 0
        expect(@files).to be_empty
      end

      it "cycles the log when it a size" do
        @stream_log = StreamLog.new('MYINT', :WRITE, 300, 2000)
        @stream_log.write("\x00\x01\x02\x03" * 250) # size 1000
        @stream_log.write("\x00\x01\x02\x03" * 250) # size 2000
        expect(@files.keys.length).to eql 0 # hasn't cycled yet
        sleep 0.1
        @stream_log.write("\x00") # size 200001
        sleep 0.1
        expect(@files.keys.length).to eql 1
        @stream_log.stop
        sleep 0.1
        expect(@files.keys.length).to eql 2
      end

      it "handles errors creating the log file" do
        capture_io do |stdout|
          allow(File).to receive(:new) { raise "Error" }
          @stream_log = StreamLog.new('MYINT', :WRITE)
          @stream_log.write("\x00\x01\x02\x03")
          @stream_log.stop
          expect(stdout.string).to match("Error starting new log file")
        end
      end

      it "handles errors closing the log file" do
        capture_io do |stdout|
          allow(BucketUtilities).to receive(:move_log_file_to_bucket) { raise "Error" }
          @stream_log = StreamLog.new('MYINT', :WRITE)
          @stream_log.write("\x00\x01\x02\x03")
          @stream_log.stop
          expect(stdout.string).to match("Error closing")
        end
      end

      it "handles errors writing the log file" do
        capture_io do |stdout|
          @stream_log = StreamLog.new('MYINT', :WRITE)
          @stream_log.write("\x00\x01\x02\x03")
          allow(@stream_log.instance_variable_get(:@file)).to receive(:write) { raise "Error" }
          @stream_log.write("\x00\x01\x02\x03")
          @stream_log.shutdown
          expect(stdout.string).to match("Error writing")
        end
      end
    end

    describe "start and stop" do
      it "enables and disable logging" do
        @stream_log = StreamLog.new('MYINT', :WRITE)
        expect(@stream_log.logging_enabled).to be true
        @stream_log.write("\x00\x01\x02\x03")
        @stream_log.stop
        sleep 0.1
        expect(@stream_log.logging_enabled).to be false
        expect(@files.keys.length).to eql 1
        @stream_log.start
        expect(@stream_log.logging_enabled).to be true
        @stream_log.write("\x00\x01\x02\x03")
        @stream_log.stop
        sleep 0.1
        expect(@files.keys.length).to eql 2
      end
    end
  end
end
