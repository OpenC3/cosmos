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
    before(:all) do |example|
    # These tests only work if there's an actual MINIO service available to talk to
    # Thus we'll just skip them all if we get a networking error
    # To enable access to MINIO for testing change the compose.yaml file and add
    # the following to services: open3-minio:
    #   ports:
    #     - "127.0.0.1:9000:9000"

    # checking for a port listener doesn't work right here, so force reset the Client double
      local_s3()
      local_s3_unset()

      @bucket = Bucket.getClient.create("bucket#{rand(1000)}")
    rescue Seahorse::Client::NetworkingError, Aws::Errors::NoSuchEndpointError => e
      example.skip e.message
    end

    after(:all) do
      Bucket.getClient.delete(@bucket) if @bucket
    end

    let(:client) { Bucket.getClient() }

    def generate_files(client, tgt, pkt, start_time, end_time, interval = 600)
      files = []
      date_folder = start_time.strftime(BucketUtilities::DIRECTORY_TIMESTAMP_FORMAT)
      while(start_time < end_time)
        start_timestamp = start_time.strftime(BucketUtilities::FILE_TIMESTAMP_FORMAT)
        end_timestamp = (start_time + interval).strftime(BucketUtilities::FILE_TIMESTAMP_FORMAT)
        file = "DEFAULT/decom_logs/tlm/#{tgt}/#{date_folder}/#{start_timestamp}__#{end_timestamp}__DEFAULT__#{tgt}__#{pkt}__rt__decom.bin.gz"
        client.put_object(bucket: 'logs', key: file, body: "\x00\x01\x02\03")
        files << file
        start_time += interval
      end
      files
    end

    describe "files_between_time" do
      it "lists all the files before a given time" do
        start_time = Time.utc(2020, 1, 2, 12, 00, 00)
        end_time = Time.utc(2020, 1, 2, 13, 00, 00)
        pkt1_files = generate_files(client, 'UNITTEST', 'PKT1', start_time, end_time)

        files = BucketUtilities.files_between_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", nil, start_time)
        expect(files).to eql []
        files = BucketUtilities.files_between_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", nil, start_time + 1201)
        expect(files.length).to eql 2
        files = BucketUtilities.files_between_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", nil, end_time + 1)
        expect(files.length).to eql 6
        expect(files).to eql pkt1_files

        pkt1_files.each do |file|
          client.delete_object(bucket: 'logs', key: file)
        end
      end
    end

    describe "move_log_file_to_bucket" do
      it "logs errors" do
        expect(Bucket).to receive(:getClient).and_raise('ERROR')
        expect(Logger).to receive(:error)
        thread = BucketUtilities.move_log_file_to_bucket('path', 'key')
        thread.join
      end

      it "moves a file to S3" do
        path = File.join(SPEC_DIR, 'test.txt')
        File.open(path, 'w') do |file|
          file.puts "This is a test"
        end
        s3_key = "filename.txt"
        thread = BucketUtilities.move_log_file_to_bucket(path, s3_key)
        thread.join
        object = client.get_object(bucket: 'logs', key: "#{s3_key}.gz")
        File.open('temp.bin.gz', 'w') do |file|
          file.write(object.body.read)
        end
        uncompress_file = BucketUtilities.uncompress_file("temp.bin.gz")
        expect(File.read(uncompress_file)).to eql "This is a test\n"
        client.delete_object(bucket: 'logs', key: s3_key)
      end
    end

    describe "get_cache_control" do
      it "returns nil for cacheable files" do
        # hash must start with period, be 20 chars, end with period
        cache = BucketUtilities.get_cache_control('myimage.ab325dc35dedfbd2343d.jpg')
        # versioned files
        cache = BucketUtilities.get_cache_control('myimage.3.2.1.jpg')
        cache = BucketUtilities.get_cache_control('myimage-3-2-1.jpg')
        cache = BucketUtilities.get_cache_control('myimage_3_2_1.jpg')
        expect(cache).to eql nil
      end

      it "returns 'no-store' for non-cacheable files" do
        cache = BucketUtilities.get_cache_control('123.js')
        expect(cache).to eql 'no-store'
      end
    end
  end
end
