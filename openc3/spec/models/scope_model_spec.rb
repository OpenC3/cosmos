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
require 'openc3/models/scope_model'
module Aws
  autoload(:S3, 'openc3/utilities/s3_autoload.rb')
end

module OpenC3
  describe ScopeModel do
    before(:each) do
      mock_redis()
    end

    describe "self.get" do
      it "returns the specified scope" do
        default_time = Time.now.to_nsec_from_epoch
        model = ScopeModel.new(name: "DEFAULT")
        model.create
        sleep 0.1
        other_time = Time.now.to_nsec_from_epoch
        model = ScopeModel.new(name: "OTHER")
        model.create
        target = ScopeModel.get(name: "DEFAULT")
        expect(target["name"]).to eql "DEFAULT"
        expect(target["updated_at"]).to be_within(10_000_000).of(default_time)
        target = ScopeModel.get(name: "OTHER")
        expect(target["name"]).to eql "OTHER"
        expect(target["updated_at"]).to be_within(10_000_000).of(other_time)
      end
    end

    describe "self.names" do
      it "returns all scope names" do
        model = ScopeModel.new(name: "DEFAULT")
        model.create
        model = ScopeModel.new(name: "OTHER")
        model.create
        names = ScopeModel.names()
        # contain_exactly doesn't care about ordering and neither do we
        expect(names).to contain_exactly("DEFAULT", "OTHER")
      end
    end

    describe "self.all" do
      it "returns all the parsed scopes" do
        model = ScopeModel.new(name: "DEFAULT")
        model.create
        model = ScopeModel.new(name: "OTHER")
        model.create
        all = ScopeModel.all()
        expect(all.keys).to contain_exactly("DEFAULT", "OTHER")
      end
    end

    describe "as_json" do
      it "encodes all the input parameters" do
        model = ScopeModel.new(name: "DEFAULT", updated_at: 12345)
        json = model.as_json(:allow_nan => true)
        expect(json['name']).to eql "DEFAULT"
        expect(json['updated_at']).to eql 12345
      end
    end

    describe "deploy" do
      it "deploys the microservices" do
        dir = File.join(SPEC_DIR, "install")
        model = ScopeModel.new(name: "DEFAULT", updated_at: 12345)
        model.create
        model.deploy(dir, {})
        # Ensure scope_model creates the UNKNOWN target and streams
        target = TargetModel.get(name: "UNKNOWN", scope: "DEFAULT")
        expect(target["name"]).to eql "UNKNOWN"
      end
    end

    describe "destroy" do
      it "destroys the scope and all microservices" do
        s3 = instance_double("Aws::S3::Client")
        allow(Aws::S3::Client).to receive(:new).and_return(s3)
        options = OpenStruct.new
        options.key = "blah"
        objs = double("Object", :contents => [options], is_truncated: false)

        scope = "TEST"
        allow(s3).to receive(:list_objects_v2).and_return(objs)
        allow(s3).to receive(:delete_object).with(bucket: 'config', key: "blah")

        dir = File.join(SPEC_DIR, "install")
        model = ScopeModel.new(name: scope, updated_at: 12345)
        model.create
        model.deploy(dir, {})

        topics = EphemeralStore.scan_each(match: "#{scope}*", type: 'hash', count: 100).to_a.uniq.sort
        expect(topics).to eql(['TEST__TRIGGER__GROUP', 'TEST__openc3_targets'])
        topics = EphemeralStore.scan_each(match: "#{scope}*", type: 'stream', count: 100).to_a.uniq.sort
        expect(topics).to eql(['TEST__openc3_autonomic'])
        model.destroy
        topics = EphemeralStore.scan_each(match: "#{scope}*", type: 'hash', count: 100).to_a.uniq.sort
        expect(topics).to eql([])
        topics = EphemeralStore.scan_each(match: "#{scope}*", type: 'stream', count: 100).to_a.uniq.sort
        expect(topics).to eql([])
      end
    end
  end
end
