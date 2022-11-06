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
require "openc3/utilities/aws_bucket"

module OpenC3
  describe AwsBucket do
    before(:all) do |example|
      @bucket = Bucket.getClient.create("bucket#{rand(1000)}")
    # These tests only work if there's an actual MINIO service available to talk to
    # Thus we'll just skip them all if we get a networking error
    # To enable access to MINIO for testing change the compose.yaml file and add
    # the following to services: openc3-minio:
    #   ports:
    #     - "127.0.0.1:9000:9000"
    rescue Seahorse::Client::NetworkingError, Aws::Errors::NoSuchEndpointError => err
      example.skip err.message
    end

    after(:all) do
      Bucket.getClient.delete(@bucket) if @bucket
    end

    let(:client) { Bucket.getClient() }

    describe "create, exist?, delete" do
      it "creates, checks, and deletes a bucket" do
        expect(client.exist?(@bucket)).to be true
        # Calling create again does nothing
        client.create(@bucket)
        expect(client.exist?(@bucket)).to be true

        client.delete(@bucket)
        expect(client.exist?(@bucket)).to be false
        # Calling delete again does nothing
        client.delete(@bucket)
        expect(client.exist?(@bucket)).to be false

        # Recreate for the rest of the tests
        client.create(@bucket)
        expect(client.exist?(@bucket)).to be true
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
      it "raises if no object" do
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
    end

    describe 'check_object' do
      it "waits for an object to exist" do
        client.put_object(bucket: @bucket, key: 'test', body: 'contents')
        client.check_object(bucket: @bucket, key: 'test')
        client.delete_object(bucket: @bucket, key: 'test')
      end

      it "raises if check fails" do
        expect { client.check_object(bucket: @bucket, key: 'nope') }.to raise_error(Aws::Waiters::Errors::TooManyAttemptsError)
      end
    end

    describe 'list_objects' do
      it "returns an array of objects" do
        client.put_object(bucket: @bucket, key: 'test1', body: 'contents1')
        client.put_object(bucket: @bucket, key: 'test2', body: 'contents2')
        client.put_object(bucket: @bucket, key: 'test3', body: 'contents3')
        objects = client.list_objects(bucket: @bucket)
        expect(objects.length).to eql 3
        keys = objects.collect {|obj| obj.key }
        expect(keys).to eql %w(test1 test2 test3)
        client.delete_object(bucket: @bucket, key: 'test1')
        client.delete_object(bucket: @bucket, key: 'test2')
        client.delete_object(bucket: @bucket, key: 'test3')
      end
    end

    describe 'list_directories' do
      it "lists directories under a path" do
        client.put_object(bucket: @bucket, key: 'DEFAULT/targets_modified/root.txt', body: 'contents0')
        client.put_object(bucket: @bucket, key: 'DEFAULT/targets_modified/INST/file1.txt', body: 'contents1')
        client.put_object(bucket: @bucket, key: 'DEFAULT/targets_modified/INST/file2.txt', body: 'contents2')
        client.put_object(bucket: @bucket, key: 'DEFAULT/targets_modified/OTHER/file3.txt', body: 'contents3')
        dirs = client.list_directories(bucket: @bucket, path: "DEFAULT/targets_modified/")
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
