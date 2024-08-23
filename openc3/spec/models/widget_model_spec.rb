# encoding: ascii-8bit

# Copyright 2024 OpenC3, Inc.
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

require 'spec_helper'
require 'openc3/config/config_parser'
require 'openc3/models/widget_model'
require 'openc3/utilities/s3_autoload'

module OpenC3
  describe WidgetModel, type: :model do

    before(:all) do
      widget_path = File.join(SPEC_DIR, 'install', 'tools', 'widgets', 'DefaultWidget')
      FileUtils.mkdir_p(widget_path) unless File.exist?(widget_path)
      widget_file = File.join(widget_path, 'DefaultWidget.umd.min.js')
      FileUtils.touch(widget_file)
      FileUtils.touch(widget_file+'.map')
    end

    before(:each) do
      mock_redis()
      model = ScopeModel.new(name: "DEFAULT")
      model.create
    end

    describe "new" do
      it "creates a widget model instance" do
        model = WidgetModel.new(name: 'widget1', scope: 'scope')
        expect(model).to_not be_nil
        expect(model.name).to eq('widget1')
      end
    end

    describe "all_scopes" do
      it "exist" do
       model = WidgetModel.new(name: 'widget1', scope: 'scope')
       model.create
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

      it "only recognizes WIDGET" do
        #parser = double("ConfigParser").as_null_object
        expect(parser).to receive(:verify_num_parameters)
        WidgetModel.handle_config(parser, "WIDGET", ["TEST_INT"], scope: "DEFAULT")
        expect { WidgetModel.handle_config(parser, "DISABLE_ERB", ["TEST_INT"], scope: "DEFAULT") }.to raise_error(ConfigParser::Error)
      end

      it "self.handle_config" do
        # blows up
        # params = ['name', 'label']
        # model = WidgetModel.handle_config(parser, 'WIDGET', params, scope: 'scope')
        # expect(model).to be_a WidgetModel
        expect{
          WidgetModel.handle_config(parser, 'NOT_A_KEYWORD', ['some', 'params'], scope: 'scope')
        }.to raise_error(OpenC3::ConfigParser::Error)
      end

      it "handle_config" do
        model = WidgetModel.new(name: "DEFAULT", scope: 'scope')
        expect(model).to be_a WidgetModel
        model.handle_config(parser, 'DISABLE_ERB', ['aParm'])
        expect{
          model.handle_config(parser, 'NOT_A_KEYWORD', ['other', 'params'])
        }.to raise_error(OpenC3::ConfigParser::Error)
      end
    end

    describe "self.names" do
      it "returns all widget names" do
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
      it "returns all the parsed widgets" do
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
      it "the Widget's microservice and undeploy it" do
        s3 = instance_double("Aws::S3::Client")
        allow(Aws::S3::Client).to receive(:new).and_return(s3)
        options = OpenStruct.new
        options.key = "blah"
        objs = double("Object", :contents => [options], is_truncated: false)
        expect(s3).to receive(:put_bucket_policy)
        expect(s3).to receive(:put_object).twice

        dir = File.join(SPEC_DIR, "install")
        model = WidgetModel.new(name: "DEFAULT", scope: 'scope', updated_at: 12345)
        model.create
        model.deploy(dir, {})
        model.undeploy
      end
    end
  end
end
