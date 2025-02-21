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
require "openc3/utilities/aws_bucket"

module OpenC3
  describe AwsBucket do
    before(:all) do |example|
    # These tests work if there's a local S3 or a MINIO service available. To enable
    # access to MINIO for testing, change the compose.yaml services stanza to:
    #
    # services:
    #   openc3-minio:
    #     ports:
    #       - "127.0.0.1:9000:9000"
      begin
        sock = Socket.new(Socket::Constants::AF_INET, Socket::Constants::SOCK_STREAM, 0)
        sock.bind(Socket.pack_sockaddr_in(9000, '127.0.0.1')) #raise if listening
        sock.close
        local_s3()
        Logger.info("No S3 listener - using local_s3 client")
      rescue Errno::EADDRINUSE;
        Logger.info("Found listener on port 9000; presumably Minio")
      end

      @bucket = Bucket.getClient.create("bucket#{rand(1000)}")
    rescue Seahorse::Client::NetworkingError, Aws::Errors::NoSuchEndpointError => e
    # We'll just skip them all if we get a networking error.
      example.skip e.message
    end

    after(:all) do
      Bucket.getClient.delete(@bucket) if @bucket
      local_s3_unset()
    end

    let(:client) { Bucket.getClient() }

    describe "create, exist?, delete" do
      it "checks a bucket" do
        expect(client.exist?(@bucket)).to be true
      end
       # Calling create again does nothing
      it "creates and checks a bucket" do
        client.create(@bucket)
        expect(client.exist?(@bucket)).to be true
      end
      it "deletes and checks a bucket" do
        client.delete(@bucket)
        expect(client.exist?(@bucket)).to be false
      end
      it "deletes a deleted bucket" do
      # Calling delete again does nothing
        client.delete(@bucket)
        expect(client.exist?(@bucket)).to be false
      end
      it "creates and checks a bucket" do
        # Recreate for the rest of the tests
        client.create(@bucket)
        expect(client.exist?(@bucket)).to be true
      end
      it "ensures public" do
        expect{client.ensure_public(@bucket)}.not_to raise_error
      end
    end

    describe 'put_object' do
      it "creates an object" do
        client.put_object(bucket: @bucket, key: 'test', body: 'contents')
        object = client.get_object(bucket: @bucket, key: 'test')
        expect(object.body.read).to eql 'contents'
        client.delete_object(bucket: @bucket, key: 'test')
      end

      it "updates an object" do
        client.put_object(bucket: @bucket, key: 'test', body: 'contents')
        client.put_object(bucket: @bucket, key: 'test', body: 'new stuff')
        object = client.get_object(bucket: @bucket, key: 'test')
        expect(object.body.read).to eql 'new stuff'
        client.delete_object(bucket: @bucket, key: 'test')
      end
    end

    describe 'get_object' do
      # formerly read,       it "raises if no object" do
      it "returns nil if no object" do
        expect(client.get_object(bucket: @bucket, key: 'nope')).to eql nil
      end

      # Basic get_object is tested by put_object, it's the exact same test code

      it "downloads an object" do
        client.put_object(bucket: @bucket, key: 'test', body: 'contents')
        local_path = File.join(SPEC_DIR, 'local_test_file.txt')
        client.get_object(bucket: @bucket, key: 'test', path: local_path)
        expect(File.exist?(local_path)).to be true
        expect(File.read(local_path)).to eql 'contents'
        client.delete_object(bucket: @bucket, key: 'test')
      end

      it "internal presigned_request" do
        client.put_object(bucket: @bucket, key: 'test4', body: 'contents')
        expect{
          client.presigned_request(bucket: @bucket, key: 'test4', method: 'pre_sign', internal: true)
        }.to raise_error(NoMethodError, /undefined method `build_request'/ )
        client.delete_object(bucket: @bucket, key: 'test4')
      end

      it "external presigned_request" do
        client.put_object(bucket: @bucket, key: 'test5', body: 'contents')
        expect{
          client.presigned_request(bucket: @bucket, key: 'test5', method: 'pre_sign', internal: false)
        }.to raise_error(NoMethodError, /undefined method `build_request'/ )
        client.delete_object(bucket: @bucket, key: 'test5')
      end
    end

    describe 'check_object' do
      it "waits for an object to exist" do
        client.put_object(bucket: @bucket, key: 'test', body: 'contents')
        result = client.check_object(bucket: @bucket, key: 'test')
        expect(result).to be true
        client.delete_object(bucket: @bucket, key: 'test')
      end

      it "return false if check fails" do
        result = client.check_object(bucket: @bucket, key: 'nope')
        expect(result).to be false
      end

      it "immediately checks for an object to exist" do
        client.put_object(bucket: @bucket, key: 'test', body: 'contents')
        result = client.check_object(bucket: @bucket, key: 'test', retries: false)
        expect(result).to be true
        client.delete_object(bucket: @bucket, key: 'test')
      end

      it "immediately returns false if check fails" do
        result = client.check_object(bucket: @bucket, key: 'nope', retries: false)
        expect(result).to be false
      end
    end

    describe 'list_objects' do
      it "returns an array of objects" do
        client.put_object(bucket: @bucket, key: 'DEFAULT/test1', body: 'contents1')
        client.put_object(bucket: @bucket, key: 'DEFAULT/test2', body: 'contents2')
        client.put_object(bucket: @bucket, key: 'DEFAULT/folder/test3', body: 'contents3')
        objects = client.list_objects(bucket: @bucket)
        expect(objects.length).to eql 3
        keys = objects.collect {|obj| obj.key }
        expect(keys).to eql %w(DEFAULT/folder/test3 DEFAULT/test1 DEFAULT/test2)
        client.delete_object(bucket: @bucket, key: 'DEFAULT/test1')
        client.delete_object(bucket: @bucket, key: 'DEFAULT/test2')
        client.delete_object(bucket: @bucket, key: 'DEFAULT/folder/test3')
      end
    end

    describe 'list_files' do
      it "returns BucketNotFound if the bucket doesn't exist" do
        expect { client.list_files(bucket: "NOPE", path: "") }.to raise_error(Bucket::NotFound, "Bucket 'NOPE' does not exist.")
      end

      it "lists the root" do
        client.put_object(bucket: @bucket, key: 'DEFAULT/targets_modified/root.txt', body: 'contents0')
        dirs, files = client.list_files(bucket: @bucket, path: "") # Empty path
        expect(dirs.length).to eql 1
        expect(dirs).to eql %w(DEFAULT)
        expect(files.length).to eql 0
        dirs, files = client.list_files(bucket: @bucket, path: "/")
        expect(dirs.length).to eql 1
        expect(dirs).to eql %w(DEFAULT)
        expect(files.length).to eql 0
        client.delete_object(bucket: @bucket, key: 'DEFAULT/targets_modified/root.txt')
      end

      it "lists files under a path" do
        client.put_object(bucket: @bucket, key: 'DEFAULT/targets_modified/root.txt', body: 'contents0')
        client.put_object(bucket: @bucket, key: 'DEFAULT/targets_modified/INST/file1.txt', body: 'contents1')
        client.put_object(bucket: @bucket, key: 'DEFAULT/targets_modified/INST/file2.txt', body: 'contents2')
        client.put_object(bucket: @bucket, key: 'DEFAULT/targets_modified/OTHER/file3.txt', body: 'contents3')

        dirs, files = client.list_files(bucket: @bucket, path: "DEFAULT/targets_modified/")
        expect(dirs.length).to eql 2
        expect(dirs).to eql %w(INST OTHER)
        expect(files.length).to eql 1
        expect(files[0]['name']).to eql 'root.txt'
        expect(files[0]['size']).to eql 9
        expect(files[0]['modified']).to_not be_nil

        dirs, files = client.list_files(bucket: @bucket, path: "DEFAULT/targets_modified/INST")
        expect(dirs.length).to eql 0
        expect(files.length).to eql 2
        expect(files[0]['name']).to eql 'file1.txt'
        expect(files[0]['size']).to eql 9
        expect(files[0]['modified']).to_not be_nil
        expect(files[1]['name']).to eql 'file2.txt'
        expect(files[1]['size']).to eql 9
        expect(files[1]['modified']).to_not be_nil

        client.delete_object(bucket: @bucket, key: 'DEFAULT/targets_modified/root.txt')
        client.delete_object(bucket: @bucket, key: 'DEFAULT/targets_modified/INST/file1.txt')
        client.delete_object(bucket: @bucket, key: 'DEFAULT/targets_modified/INST/file2.txt')
        client.delete_object(bucket: @bucket, key: 'DEFAULT/targets_modified/OTHER/file3.txt')
      end

      it "lists only directories under a path" do
        client.put_object(bucket: @bucket, key: 'DEFAULT/targets_modified/root.txt', body: 'contents0')
        client.put_object(bucket: @bucket, key: 'DEFAULT/targets_modified/INST/file1.txt', body: 'contents1')
        client.put_object(bucket: @bucket, key: 'DEFAULT/targets_modified/INST/file2.txt', body: 'contents2')
        client.put_object(bucket: @bucket, key: 'DEFAULT/targets_modified/OTHER/file3.txt', body: 'contents3')
        dirs = client.list_files(bucket: @bucket, path: "DEFAULT/targets_modified/", only_directories: true)
        expect(dirs.length).to eql 2
        expect(dirs).to eql %w(INST OTHER)
        client.delete_object(bucket: @bucket, key: 'DEFAULT/targets_modified/root.txt')
        client.delete_object(bucket: @bucket, key: 'DEFAULT/targets_modified/INST/file1.txt')
        client.delete_object(bucket: @bucket, key: 'DEFAULT/targets_modified/INST/file2.txt')
        client.delete_object(bucket: @bucket, key: 'DEFAULT/targets_modified/OTHER/file3.txt')
      end
    end

    describe 'delete_objects' do
      it "deletes an array of object keys" do
        client.put_object(bucket: @bucket, key: 'test1', body: 'contents1')
        client.put_object(bucket: @bucket, key: 'test2', body: 'contents2')
        client.put_object(bucket: @bucket, key: 'test3', body: 'contents3')
        client.delete_objects(bucket: @bucket, keys: ['test1', 'test3'])
        objects = client.list_objects(bucket: @bucket)
        expect(objects.length).to eql 1
        keys = objects.collect {|obj| obj.key }
        expect(keys).to eql %w(test2)
        client.delete_object(bucket: @bucket, key: 'test2')
      end
    end
  end
end
