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

require "spec_helper"
require "openc3/utilities/target_file"
require "openc3/utilities/aws_bucket"

module OpenC3
  describe TargetFile do
    # TargetFile.all marks a file that has a targets_modified copy by appending
    # '*' to its name. The marker is display-only, so it must not survive into a
    # bucket key -- body() strips it before looking a name up, so a '*'-suffixed
    # key can be written and then never read back.
    # See https://github.com/OpenC3/cosmos/issues/3780
    describe "self.strip_modified" do
      it "removes a trailing marker" do
        expect(TargetFile.strip_modified("TGT/procedures/test.rb*")).to eql "TGT/procedures/test.rb"
      end

      it "leaves an unmarked name alone" do
        expect(TargetFile.strip_modified("TGT/procedures/test.rb")).to eql "TGT/procedures/test.rb"
      end

      # '*' is a legal S3 object key character and FileOpenSaveDialog's filename
      # charset allows it, so files named this way exist and must stay
      # addressable
      it "keeps a '*' that is not the trailing marker" do
        expect(TargetFile.strip_modified("TGT/procedures/a*b.rb")).to eql "TGT/procedures/a*b.rb"
      end

      it "strips only the marker from a name that also contains a '*'" do
        expect(TargetFile.strip_modified("TGT/procedures/a*b.rb*")).to eql "TGT/procedures/a*b.rb"
      end
    end

    # The bucket normalizes '..' segments in keys, so a traversal name would
    # reach another scope's objects. Names are rejected before any bucket call.
    describe "name validation" do
      it "rejects traversal names on destroy and create without touching the bucket" do
        expect(Bucket).to_not receive(:getClient)
        name = "INST/../../OTHER/targets_modified/INST/procedures/x.rb"
        expect { TargetFile.destroy("DEFAULT", name) }.to raise_error(ArgumentError, /Invalid target file name/)
        expect { TargetFile.create("DEFAULT", name, "data") }.to raise_error(ArgumentError, /Invalid target file name/)
      end
    end

    describe "marker handling on bucket keys" do
      before(:each) do
        @fsys_s3 = ENV['OPENC3_CLOUD'].nil? || ENV['OPENC3_CLOUD'] == 'local'
        local_s3() if @fsys_s3
        ENV['OPENC3_CONFIG_BUCKET'] = "config"
        @bucket = Bucket.getClient.create("config")
      end

      after(:each) do
        Bucket.getClient.delete(@bucket) if @bucket
        local_s3_unset()
      end

      it "writes the unmarked key when create is handed a marked name" do
        expect(TargetFile.create("DEFAULT", "TGT/procedures/marked.rb*", "puts 'hi'")).to be true
        # The whole point: the file is readable afterwards, under either spelling
        expect(TargetFile.body("DEFAULT", "TGT/procedures/marked.rb")).to eql "puts 'hi'"
        expect(TargetFile.body("DEFAULT", "TGT/procedures/marked.rb*")).to eql "puts 'hi'"
        # And no stray '*' key was left behind
        expect(Bucket.getClient.check_object(
          bucket: "config", key: "DEFAULT/targets_modified/TGT/procedures/marked.rb*"
        )).to be false
      end

      it "deletes the unmarked key when destroy is handed a marked name" do
        TargetFile.create("DEFAULT", "TGT/procedures/gone.rb", "puts 'bye'")
        expect(TargetFile.body("DEFAULT", "TGT/procedures/gone.rb")).to eql "puts 'bye'"
        TargetFile.destroy("DEFAULT", "TGT/procedures/gone.rb*")
        expect(TargetFile.body("DEFAULT", "TGT/procedures/gone.rb")).to be_nil
      end

      it "round trips a name that legitimately contains a '*'" do
        expect(TargetFile.create("DEFAULT", "TGT/procedures/a*b.rb", "puts 'star'")).to be true
        expect(TargetFile.body("DEFAULT", "TGT/procedures/a*b.rb")).to eql "puts 'star'"
      end
    end

    describe "local only targets" do
      before(:each) do
        @fsys_s3 = ENV['OPENC3_CLOUD'].nil? || ENV['OPENC3_CLOUD'] == 'local'
        local_s3() if @fsys_s3
        ENV['OPENC3_CONFIG_BUCKET'] = "config"
        ENV['OPENC3_LOCAL_ONLY_TARGETS'] = "LOCAL"
        @bucket = Bucket.getClient.create("config")
        @tmp_dir = Dir.mktmpdir
        @saved_path = LocalMode::OPENC3_LOCAL_MODE_PATH
        saved_verbose = $VERBOSE; $VERBOSE = nil
        LocalMode.const_set(:OPENC3_LOCAL_MODE_PATH, @tmp_dir)
        $VERBOSE = saved_verbose
      end

      after(:each) do
        ENV['OPENC3_LOCAL_ONLY_TARGETS'] = nil
        saved_verbose = $VERBOSE; $VERBOSE = nil
        LocalMode.const_set(:OPENC3_LOCAL_MODE_PATH, @saved_path)
        $VERBOSE = saved_verbose
        FileUtils.rm_rf @tmp_dir if @tmp_dir
        Bucket.getClient.delete(@bucket) if @bucket
        local_s3_unset()
      end

      def bucket_put(key, body)
        Bucket.getClient.put_object(bucket: "config", key: key, body: body)
      end

      def bucket_has?(key)
        Bucket.getClient.check_object(bucket: "config", key: key, retries: false)
      end

      it "creates, reads and destroys files only in the local mode volume" do
        local_path = "#{@tmp_dir}/DEFAULT/targets_modified/LOCAL/procedures/test.rb"
        expect(TargetFile.create("DEFAULT", "LOCAL/procedures/test.rb", "puts 'local'")).to be true
        expect(File.read(local_path)).to eql "puts 'local'"
        expect(bucket_has?("DEFAULT/targets_modified/LOCAL/procedures/test.rb")).to be false
        expect(TargetFile.body("DEFAULT", "LOCAL/procedures/test.rb")).to eql "puts 'local'"
        TargetFile.destroy("DEFAULT", "LOCAL/procedures/test.rb")
        expect(File.exist?(local_path)).to be false
        expect(TargetFile.body("DEFAULT", "LOCAL/procedures/test.rb")).to be_nil
      end

      it "never reads local only target files from the bucket" do
        bucket_put("DEFAULT/targets/LOCAL/screens/orig.txt", "SCREEN")
        bucket_put("DEFAULT/targets_modified/LOCAL/screens/mod.txt", "SCREEN")
        expect(TargetFile.body("DEFAULT", "LOCAL/screens/orig.txt")).to be_nil
        expect(TargetFile.body("DEFAULT", "LOCAL/screens/mod.txt")).to be_nil
        # Other targets still use the bucket
        bucket_put("DEFAULT/targets/OTHER/screens/orig.txt", "OTHER")
        expect(TargetFile.body("DEFAULT", "OTHER/screens/orig.txt")).to eql "OTHER"
      end

      it "lists local only target files from the local mode volume without the modified marker" do
        bucket_put("DEFAULT/targets/LOCAL/screens/orig.txt", "SCREEN")
        bucket_put("DEFAULT/targets/OTHER/screens/other.txt", "OTHER")
        TargetFile.create("DEFAULT", "LOCAL/screens/local.txt", "LOCAL")
        expect(TargetFile.all("DEFAULT", ['screens'])).to eql ["LOCAL/screens/local.txt", "OTHER/screens/other.txt"]
        expect(TargetFile.all("DEFAULT", ['screens'], target: 'LOCAL')).to eql ["LOCAL/screens/local.txt"]
      end
    end
  end
end
