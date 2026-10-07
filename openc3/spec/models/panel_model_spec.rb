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

require 'spec_helper'
require 'openc3/config/config_parser'
require 'openc3/models/panel_model'

module OpenC3
  describe PanelModel, type: :model do
    before(:each) do
      mock_redis()
    end

    describe "handle_config" do
      it "only recognizes PANEL and upcases the type" do
        parser = OpenC3::ConfigParser.new("https://openc3.com")
        allow(parser).to receive(:verify_num_parameters)
        model = PanelModel.handle_config(parser, "PANEL", ["map"], plugin: 'plugin', scope: "DEFAULT")
        expect(model.name).to eql 'MAP'
        expect(model.bucket_key).to eql 'panels/MAP/MAP.js'
        expect { PanelModel.handle_config(parser, "WIDGET", ["MAP"], scope: "DEFAULT") }.to raise_error(ConfigParser::Error)
      end
    end

    describe "names / as_json" do
      it "lists installed panels with their url" do
        PanelModel.new(name: 'MAP', plugin: 'plugin', scope: 'DEFAULT').create
        PanelModel.new(name: 'GAUGE', plugin: 'plugin', scope: 'DEFAULT').create
        expect(PanelModel.names(scope: 'DEFAULT')).to eql ['GAUGE', 'MAP']
        expect(PanelModel.get(name: 'MAP', scope: 'DEFAULT')['url']).to eql '/tools/panels/MAP/MAP.js'
      end
    end

    describe "deploy / undeploy" do
      before(:each) do
        @gem_path = Dir.mktmpdir
        dir = File.join(@gem_path, 'tools', 'panels', 'MAP')
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, 'MAP.js'), 'System.register([], function () { /* <% not erb %> */ })')
        File.write(File.join(dir, 'MAP.js.map'), '{}')
      end

      after(:each) do
        FileUtils.rm_rf(@gem_path)
      end

      it "uploads the bundle and its map without running ERB" do
        bucket = double('bucket')
        allow(Bucket).to receive(:getClient).and_return(bucket)
        expect(bucket).to receive(:put_object).with(hash_including(key: 'panels/MAP/MAP.js', body: /<% not erb %>/))
        expect(bucket).to receive(:put_object).with(hash_including(key: 'panels/MAP/MAP.js.map'))
        PanelModel.new(name: 'MAP', scope: 'DEFAULT').deploy(@gem_path, {})
      end

      it "only reads the bundle when validating" do
        expect(Bucket).not_to receive(:getClient)
        PanelModel.new(name: 'MAP', scope: 'DEFAULT').deploy(@gem_path, {}, validate_only: true)
      end

      it "removes the bundle on undeploy" do
        bucket = double('bucket')
        allow(Bucket).to receive(:getClient).and_return(bucket)
        expect(bucket).to receive(:delete_object).with(hash_including(key: 'panels/MAP/MAP.js'))
        expect(bucket).to receive(:delete_object).with(hash_including(key: 'panels/MAP/MAP.js.map'))
        PanelModel.new(name: 'MAP', scope: 'DEFAULT').undeploy
      end
    end
  end
end
