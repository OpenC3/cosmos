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

require "spec_helper"
require "openc3/utilities/bucket_utilities"

module OpenC3
  describe BucketUtilities do
    before(:all) do |example|
      @bucket = Bucket.getClient.create("bucket#{rand(1000)}")
    # These tests only work if there's an actual MINIO service avaiable to talk to
    # Thus we'll just skip them all if we get a networking error
    # To enable access to MINIO for testing change the compose.yaml file and add
    # the following to services: open3-minio:
    #   ports:
    #     - "127.0.0.1:9000:9000"
    rescue Seahorse::Client::NetworkingError, Aws::Errors::NoSuchEndpointError => err
      example.skip err.message
    end

    after(:all) do
      Bucket.getClient.delete(@bucket) if @bucket
    end

    let(:client) { Bucket.getClient() }

    def generate_files(client, tgt, pkt, start_time, end_time, interval = 600)
      files = []
      date_folder = start_time.strftime('%Y%m%d')
      while(start_time < end_time)
        file = "DEFAULT/decom_logs/tlm/#{tgt}/#{pkt}/#{date_folder}/#{start_time.to_timestamp}__#{(start_time + interval).to_timestamp}__DEFAULT__#{tgt}__#{pkt}__rt__decom.bin"
        client.put_object(bucket: 'logs', key: file, body: "\x00\x01\x02\03")
        files << file
        start_time += interval
      end
      files
    end

    describe "list_files_before_time" do
      it "returns empty array for non-existant bucket" do
        files = BucketUtilities.list_files_before_time('blah', "DEFAULT/decom_logs/tlm/UNITTEST", Time.now)
        expect(files).to eql []
      end

      it "lists all the files before a given time" do
        start_time = Time.utc(2020, 1, 2, 12, 00, 00)
        end_time = Time.utc(2020, 1, 2, 13, 00, 00)
        pkt1_files = generate_files(client, 'UNITTEST', 'PKT1', start_time, end_time)

        files = BucketUtilities.list_files_before_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", start_time)
        expect(files).to eql []
        files = BucketUtilities.list_files_before_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", start_time + 1201)
        expect(files.length).to eql 2
        files = BucketUtilities.list_files_before_time('logs', "DEFAULT/decom_logs/tlm/UNITTEST", end_time + 1)
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
        object = client.get_object(bucket: 'logs', key: s3_key)
        expect(object.body.read).to eql "This is a test\n"
        client.delete_object(bucket: 'logs', key: s3_key)
      end
    end

    describe "get_cache_control" do
      it "returns nil for cachable files" do
        # hash must start with period, be 20 chars, end with period
        cache = BucketUtilities.get_cache_control('myimage.ab325dc35dedfbd2343d.jpg')
        # versioned files
        cache = BucketUtilities.get_cache_control('myimage.3.2.1.jpg')
        cache = BucketUtilities.get_cache_control('myimage-3-2-1.jpg')
        cache = BucketUtilities.get_cache_control('myimage_3_2_1.jpg')
        expect(cache).to eql nil
      end

      it "returns 'no-cache' for non-cachable files" do
        cache = BucketUtilities.get_cache_control('123.js')
        expect(cache).to eql 'no-cache'
      end
    end
  end
end
