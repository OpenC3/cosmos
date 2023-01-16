# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc
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

require "spec_helper"
require "openc3/utilities/bucket_utilities"

module OpenC3
  describe BucketUtilities do
    let(:client) { Bucket.getClient() }

    def generate_files(client, tgt, pkt, start_time, end_time, interval = 600)
      dirs = []
      files = {}
      filenames = []
      while(start_time < end_time)
        dirs << start_time.strftime(BucketUtilities::DIRECTORY_TIMESTAMP_FORMAT)
        start_timestamp = start_time.strftime(BucketUtilities::FILE_TIMESTAMP_FORMAT)
        end_timestamp = (start_time + interval).strftime(BucketUtilities::FILE_TIMESTAMP_FORMAT)
        file = "DEFAULT/decom_logs/tlm/#{tgt}/#{dirs[-1]}/#{start_timestamp}__#{end_timestamp}__DEFAULT__#{tgt}__#{pkt}__rt__decom.bin.gz"
        filenames << file
        os = OpenStruct.new
        os.key = file
        # Store files by directory
        files[dirs[-1]] ||= []
        files[dirs[-1]] << os
        start_time += interval
      end
      allow(@client).to receive(:list_files).and_return(dirs.uniq)
      allow(@client).to receive(:list_objects) do |params|
        # Return the files for this directory
        # prefix looks like this: DEFAULT/decom_logs/tlm/UNITTEST/20200103
        files[params[:prefix].split('/')[-1]]
      end
      filenames
    end

    before(:each) do
      @client = double("getClient").as_null_object
      allow(@client).to receive(:exist?).and_return(true)
      allow(Bucket).to receive(:getClient).and_return(@client)
    end

    describe "files_between_time" do
      it "returns empty array for non-existant bucket" do
        allow(@client).to receive(:exist?).and_return(false)
        files = BucketUtilities.files_between_time('blah', "DEFAULT/decom_logs/tlm/UNITTEST", Time.now, Time.now)
        expect(files).to eql []
      end

      it "returns files between the times" do
        start_time = Time.utc(2020, 1, 2, 12, 00, 00)
        end_time = Time.utc(2020, 1, 3, 12, 00, 00) # 1 day later
        pkt1_files = generate_files(client, 'UNITTEST', 'PKT1', start_time, end_time, 3600)
        expect(pkt1_files.length).to eql 24

        files = BucketUtilities.files_between_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", start_time + 3600, end_time - 3600)
        expect(files.length).to eql 22

        files = BucketUtilities.files_between_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", start_time, start_time + 3600)
        expect(files.length).to eql 1

        files = BucketUtilities.files_between_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", start_time + 1, start_time + 3600)
        expect(files.length).to eql 0

        files = BucketUtilities.files_between_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", end_time - 3600, end_time)
        expect(files.length).to eql 1

        files = BucketUtilities.files_between_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", end_time - 3599, end_time)
        expect(files.length).to eql 0
      end

      it "returns files before the end time" do
        start_time = Time.utc(2020, 1, 2, 12, 00, 00)
        end_time = Time.utc(2020, 1, 3, 12, 00, 00) # 1 day later
        pkt1_files = generate_files(client, 'UNITTEST', 'PKT1', start_time, end_time, 3600)
        expect(pkt1_files.length).to eql 24

        files = BucketUtilities.files_between_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", nil, end_time)
        expect(files.length).to eql 24 # 24 hours in a day
        files = BucketUtilities.files_between_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", nil, end_time - 1)
        expect(files.length).to eql 23
        files = BucketUtilities.files_between_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", nil, end_time - 3600)
        expect(files.length).to eql 23
      end

      it "returns files after the start time" do
        start_time = Time.utc(2020, 1, 2, 12, 00, 00)
        end_time = Time.utc(2020, 1, 3, 12, 00, 00) # 1 day later
        pkt1_files = generate_files(client, 'UNITTEST', 'PKT1', start_time, end_time, 3600)
        expect(pkt1_files.length).to eql 24

        files = BucketUtilities.files_between_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", start_time, nil)
        expect(files.length).to eql 24 # 24 hours in a day
        files = BucketUtilities.files_between_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", start_time - 1, nil)
        expect(files.length).to eql 24
        files = BucketUtilities.files_between_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", start_time + 1, nil)
        expect(files.length).to eql 23
      end

      it "returns files between the times and overlapping the times" do
        start_time = Time.utc(2020, 1, 2, 12, 00, 00)
        end_time = Time.utc(2020, 1, 3, 12, 00, 00) # 1 day later
        pkt1_files = generate_files(client, 'UNITTEST', 'PKT1', start_time, end_time, 3600)
        expect(pkt1_files.length).to eql 24

        files = BucketUtilities.files_between_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", start_time + 100, end_time - 100, overlap: true)
        expect(files.length).to eql 24

        files = BucketUtilities.files_between_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", start_time, start_time + 100, overlap: true)
        expect(files.length).to eql 1

        files = BucketUtilities.files_between_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", end_time - 100, end_time, overlap: true)
        expect(files.length).to eql 1
      end
    end
  end
end
