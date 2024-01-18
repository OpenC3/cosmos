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
require 'openc3'
require 'openc3/system/system'
require 'tempfile'
require 'fileutils'
require 'openc3/utilities/aws_bucket'

module OpenC3
  describe System do
    before(:each) do
      mock_redis()
      setup_system()
      dbl = double("AwsS3Client").as_null_object
      allow(Aws::S3::Client).to receive(:new).and_return(dbl)
      resp = OpenStruct.new
      resp.common_prefixes = []
      resp.contents = []
      resp.is_truncated = false
      resp.next_continuation_token = nil
      allow(dbl).to receive(:list_objects_v2).and_return(resp)
      entry = double("entry")
      allow(entry).to receive(:name).and_return("INST")
      zip = double("zip_file")
      allow(zip).to receive(:each).and_yield(entry)
      allow(zip).to receive(:extract) do |entry, path|
        FileUtils.mkdir_p(path)
      end
      allow(Zip::File).to receive(:open).and_yield(zip)
    end

    describe "self.limits_set" do
      it "returns DEFAULT by default" do
        expect(System.limits_set).to eql :DEFAULT
      end

      it "can be set" do
        System.limits_set = 'TVAC'
        expect(System.limits_set).to eql :TVAC
      end
    end

    describe "self.setup_targets" do
      it "does nothing if already initialized" do
        System.setup_targets(['INST'], File.join(SPEC_DIR, 'install'), scope: 'DEFAULT')
      end

      it "setups targets" do
        System.class_eval('@@instance = nil')
        dir = Dir.mktmpdir
        System.setup_targets(['INST'], dir, scope: 'DEFAULT')
        expect(System.instance.targets.keys).to eql ['INST']
      end
    end

    describe "instance" do
      it "initializes targets" do
        expect(System.instance.targets.keys).to include('SYSTEM', 'INST', 'EMPTY')
        expect(System.instance.targets['INST']).to be_a Target
        expect(System.instance.commands.target_names).to include('SYSTEM', 'INST')
        expect(System.instance.telemetry.target_names).to include('SYSTEM', 'INST')
        expect(System.instance.limits.sets).to include(:DEFAULT, :TVAC)
      end
    end
  end
end
