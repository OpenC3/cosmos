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
# All changes Copyright 2022,2024 OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/config/config_parser'
require 'openc3/models/widget_model'

module Aws
  autoload(:S3, 'openc3/utilities/s3_autoload.rb')
end

module OpenC3
  describe WidgetModel, type: :model do

    before(:each) do
      mock_redis()
      model = ScopeModel.new(name: "DEFAULT")
      model.create
    end

    describe "new" do
      it "creates a widget model instance" do
        model = WidgetModel.new(name: 'widget1', scope: 'scope')
        expect(model).to_not be_nil
      end
    end

    describe "all_scopes" do
      it "exist" do
       model = WidgetModel.new(name: 'widget1', scope: 'scope')
       expect(WidgetModel.all_scopes).to_not be_nil
      end
    end

    describe "self.get" do
      it "returns the specified scope" do
        default_time = Time.now.to_nsec_from_epoch
        model = WidgetModel.new(name: "DEFAULT", scope: 'scope')
        model.create
        sleep 0.1
        other_time = Time.now.to_nsec_from_epoch
        model = WidgetModel.new(name: "OTHER", scope: 'scope')
        model.create
        sleep 0.1
        target = WidgetModel.get(name: "DEFAULT", scope: 'scope')
        expect(target["name"]).to eql "DEFAULT"
        expect(target["updated_at"]).to be_within(10_000_000).of(default_time)
        target = WidgetModel.get(name: "OTHER", scope: 'scope')
        expect(target["name"]).to eql "OTHER"
        expect(target["updated_at"]).to be_within(10_000_000).of(other_time)
      end
    end

    describe "handle_config" do
      parser = OpenC3::ConfigParser.new("https://openc3.com")

      it "for the class" do
        # blows up
        #model = WidgetModel.handle_config(parser, 'WIDGET', ['DEFAULT', 'label'], scope: 'scope')
        #expect(model).to be_a WidgetModel
        expect{
          WidgetModel.handle_config(parser, 'NOT_A_KEYWORD', ['some', 'parms'], scope: 'scope')
        }.to raise_error(OpenC3::ConfigParser::Error)
      end

      it "for the instance" do
        model = WidgetModel.new(name: "DEFAULT", scope: 'scope')
        expect(model).to be_a WidgetModel
        model.handle_config(parser, 'DISABLE_ERB', ['aParm'])
        expect{
          model.handle_config(parser, 'NOT_A_KEYWORD', ['other', 'parms'])
        }.to raise_error(OpenC3::ConfigParser::Error)
      end
    end

    describe "self.names" do
      it "returns all scope names" do
        model = WidgetModel.new(name: "TEST", scope: 'DEFAULT')
        model.create
        model = WidgetModel.new(name: "OTHER", scope: 'DEFAULT')
        model.create
        names = WidgetModel.names(scope: 'DEFAULT')
        # contain_exactly doesn't care about ordering and neither do we
        expect(names).to contain_exactly("TEST", "OTHER")
      end
    end

    describe "self.all" do
      it "returns all the parsed scopes" do
        model = WidgetModel.new(name: "DEFAULT", scope: 'scope')
        model.create
        model = WidgetModel.new(name: "OTHER", scope: 'scope')
        model.create
        all = WidgetModel.all(scope: 'scope')
        expect(all.keys).to contain_exactly("DEFAULT", "OTHER")
      end
    end

    describe "as_json" do
      it "encodes all the input parameters" do
        model = WidgetModel.new(name: "DEFAULT", scope: 'scope', updated_at: 12345)
        json = model.as_json(:allow_nan => true)
        expect(json['name']).to eql "DEFAULT"
        expect(json['updated_at']).to eql 12345
      end
    end

    describe "deploy" do
      it "unless validate_only" do
        dir = File.join(SPEC_DIR, "install")
        model = WidgetModel.new(name: "DEFAULT", scope: 'scope', updated_at: 12346)
        model.create
        model.deploy(dir, {}, validate_only: true)
        # not sure how to validate this
      end

      xit "the Widget's microservice" do
        dir = File.join(SPEC_DIR, "install")
        model = WidgetModel.new(name: "DEFAULT", scope: 'DEFAULT', updated_at: 12345)
        model.create
        model.deploy(dir, {})
        # Ensure scope_model creates the UNKNOWN target and streams
        target = TargetModel.get(name: "UNKNOWN", scope: "DEFAULT")
        expect(target["name"]).to eql "UNKNOWN"
        # and undeploy
        model.undeploy
        # nor how to validate undeployemnt
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
        allow(s3).to receive(:put_bucket_policy)
        allow(s3).to receive(:put_object)
        allow(s3).to receive(:list_objects_v2).and_return(objs)
        allow(s3).to receive(:delete_object).with(bucket: 'config', key: "blah")

        dir = File.join(SPEC_DIR, "install")
        model = WidgetModel.new(name: "DEFAULT", scope: 'scope', updated_at: 12345)
        model.create
        model.deploy(dir, {})
=begin
        topics = EphemeralStore.scan_each(match: "#{scope}*", type: 'hash', count: 100).to_a.uniq.sort
        expect(topics).to eql(['TEST__TRIGGER__GROUP', 'TEST__openc3_targets'])
        topics = EphemeralStore.scan_each(match: "#{scope}*", type: 'stream', count: 100).to_a.uniq.sort
        expect(topics).to eql(['TEST__openc3_autonomic'])
        model.destroy
        topics = EphemeralStore.scan_each(match: "#{scope}*", type: 'hash', count: 100).to_a.uniq.sort
        expect(topics).to eql([])
        topics = EphemeralStore.scan_each(match: "#{scope}*", type: 'stream', count: 100).to_a.uniq.sort
        expect(topics).to eql([])
=end
      end
    end
  end
end
