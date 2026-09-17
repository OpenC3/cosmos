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
  end
end
