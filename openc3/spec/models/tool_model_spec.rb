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
require 'openc3/models/tool_model'
require 'openc3/utilities/aws_bucket'

module OpenC3
  describe ToolModel do
    before(:each) do
      mock_redis()
      local_s3()
      local_s3_unset()
    end

    describe "self.get" do
      it "returns the specified tool" do
        model = ToolModel.new(folder_name: "TEST", name: "TEST2", scope: "DEFAULT")
        model.create
        model = ToolModel.new(folder_name: "SPEC", name: "SPEC", scope: "DEFAULT")
        model.create
        target = ToolModel.get(name: "TEST2", scope: "DEFAULT")
        expect(target["name"]).to eql "TEST2"
        expect(target["folder_name"]).to eql "TEST"
      end
    end

    describe "self.names" do
      it "returns all tool names" do
        model = ToolModel.new(folder_name: "TEST", name: "TEST", scope: "DEFAULT")
        model.create
        model = ToolModel.new(folder_name: "SPEC", name: "SPEC", scope: "DEFAULT")
        model.create
        model = ToolModel.new(folder_name: "OTHER", name: "OTHER", scope: "OTHER")
        model.create
        names = ToolModel.names(scope: "DEFAULT")
        expect(names).to contain_exactly("TEST", "SPEC")
        names = ToolModel.names(scope: "OTHER")
        expect(names).to contain_exactly("OTHER")
      end
    end

    describe "create" do
      it "requires unique folder_name" do
        model = ToolModel.new(folder_name: "TEST", name: "TEST", scope: "DEFAULT")
        model.create
        model = ToolModel.new(folder_name: "TEST", name: "TEST2", scope: "DEFAULT")
        expect { model.create }.to raise_error(RuntimeError)
      end
    end

    describe "self.all" do
      it "returns all the parsed tools" do
        model = ToolModel.new(folder_name: "TEST", name: "TEST", scope: "DEFAULT")
        model.create
        model = ToolModel.new(folder_name: "SPEC", name: "SPEC", scope: "DEFAULT")
        model.create
        all = ToolModel.all(scope: "DEFAULT")
        expect(all.keys).to contain_exactly("TEST", "SPEC")
      end
    end

    describe "self.handle_config" do
      it "only recognizes TOOL" do
        parser = double("ConfigParser").as_null_object
        expect(parser).to receive(:verify_num_parameters)
        tool = ToolModel.handle_config(parser, "TOOL", ["FOLDER", "NAME"], scope: "DEFAULT")
        expect(tool.name).to eql("NAME")
        expect(tool.folder_name).to eql("FOLDER")
        expect { ToolModel.handle_config(parser, "TOOLS", ["FOLDER", "NAME"], scope: "DEFAULT") }.to raise_error(ConfigParser::Error)
      end
    end

    describe "self.set_position" do
      it "reorders the tools" do
        # Create a few tool models
        model = ToolModel.new(folder_name: "TEST0", name: "TEST0", scope: "DEFAULT")
        model.create
        expect(model.position).to eql 0
        model = ToolModel.new(folder_name: "TEST1", name: "TEST1", scope: "DEFAULT")
        model.create
        expect(model.position).to eql 1
        model = ToolModel.new(folder_name: "TEST2", name: "TEST2", scope: "DEFAULT")
        model.create
        expect(model.position).to eql 2
        model = ToolModel.new(folder_name: "TEST3", name: "TEST3", scope: "DEFAULT")
        model.create
        expect(model.position).to eql 3

        # Move TEST2 up
        ToolModel.set_position(name: "TEST2", position: 1, scope: "DEFAULT")
        model = ToolModel.get(name: "TEST0", scope: "DEFAULT")
        expect(model['position']).to eql 0
        server = ToolModel.get(name: "TEST2", scope: "DEFAULT")
        expect(server['position']).to eql 1
        model = ToolModel.get(name: "TEST1", scope: "DEFAULT")
        expect(model['position']).to eql 2
        model = ToolModel.get(name: "TEST3", scope: "DEFAULT")
        expect(model['position']).to eql 3

        # Move TEST2 back
        ToolModel.set_position(name: "TEST2", position: 2, scope: "DEFAULT")
        model = ToolModel.get(name: "TEST0", scope: "DEFAULT")
        expect(model['position']).to eql 0
        server = ToolModel.get(name: "TEST1", scope: "DEFAULT")
        expect(server['position']).to eql 1
        model = ToolModel.get(name: "TEST2", scope: "DEFAULT")
        expect(model['position']).to eql 2
        model = ToolModel.get(name: "TEST3", scope: "DEFAULT")
        expect(model['position']).to eql 3

        # Move TEST1 to the beginning
        ToolModel.set_position(name: "TEST1", position: 0, scope: "DEFAULT")
        model = ToolModel.get(name: "TEST1", scope: "DEFAULT")
        expect(model['position']).to eql 0
        server = ToolModel.get(name: "TEST0", scope: "DEFAULT")
        expect(server['position']).to eql 1
        model = ToolModel.get(name: "TEST2", scope: "DEFAULT")
        expect(model['position']).to eql 2
        model = ToolModel.get(name: "TEST3", scope: "DEFAULT")
        expect(model['position']).to eql 3

        # Move TEST0 to the end (currently in the middle)
        ToolModel.set_position(name: "TEST0", position: 3, scope: "DEFAULT")
        model = ToolModel.get(name: "TEST1", scope: "DEFAULT")
        expect(model['position']).to eql 0
        model = ToolModel.get(name: "TEST2", scope: "DEFAULT")
        expect(model['position']).to eql 1
        model = ToolModel.get(name: "TEST3", scope: "DEFAULT")
        expect(model['position']).to eql 2
        model = ToolModel.get(name: "TEST0", scope: "DEFAULT")
        expect(model['position']).to eql 3

        # Move TEST1 to the end (currently first)
        ToolModel.set_position(name: "TEST1", position: 3, scope: "DEFAULT")
        model = ToolModel.get(name: "TEST2", scope: "DEFAULT")
        expect(model['position']).to eql 0
        model = ToolModel.get(name: "TEST3", scope: "DEFAULT")
        expect(model['position']).to eql 1
        model = ToolModel.get(name: "TEST0", scope: "DEFAULT")
        expect(model['position']).to eql 2
        model = ToolModel.get(name: "TEST1", scope: "DEFAULT")
        expect(model['position']).to eql 3

        # Move TEST1 to the front (currently last)
        ToolModel.set_position(name: "TEST1", position: 0, scope: "DEFAULT")
        model = ToolModel.get(name: "TEST1", scope: "DEFAULT")
        expect(model['position']).to eql 0
        model = ToolModel.get(name: "TEST2", scope: "DEFAULT")
        expect(model['position']).to eql 1
        model = ToolModel.get(name: "TEST3", scope: "DEFAULT")
        expect(model['position']).to eql 2
        model = ToolModel.get(name: "TEST0", scope: "DEFAULT")
        expect(model['position']).to eql 3

        # Move TEST3 up
        ToolModel.set_position(name: "TEST3", position: 1, scope: "DEFAULT")
        model = ToolModel.get(name: "TEST1", scope: "DEFAULT")
        expect(model['position']).to eql 0
        model = ToolModel.get(name: "TEST3", scope: "DEFAULT")
        expect(model['position']).to eql 1
        model = ToolModel.get(name: "TEST2", scope: "DEFAULT")
        expect(model['position']).to eql 2
        model = ToolModel.get(name: "TEST0", scope: "DEFAULT")
        expect(model['position']).to eql 3
      end
    end

    describe "as_json" do
      it "encodes all the input parameters" do
        model = ToolModel.new(name: "TEST", scope: "DEFAULT")
        json = model.as_json(:allow_nan => true)
        expect(json['name']).to eq "TEST"
        params = model.method(:initialize).parameters
        params.each do |type, name|
          # Scope isn't included in as_json as it is part of the key used to get the model
          next if name == :scope

          expect(json.key?(name.to_s)).to be true
        end
      end
    end

    describe "handle_config" do
      it "parses tool specific keywords" do
        model = ToolModel.new(name: "TEST", scope: "DEFAULT")

        parser = ConfigParser.new
        tf = Tempfile.new
        tf.puts "URL myurl"
        tf.puts "ICON mdi-icon"
        tf.close
        parser.parse_file(tf.path) do |keyword, params|
          model.handle_config(parser, keyword, params)
        end
        json = model.as_json(:allow_nan => true)
        expect(json['url']).to eql 'myurl'
        expect(json['icon']).to eql 'mdi-icon'
        tf.unlink
      end
    end

    describe "create" do
      it "validates the url" do
        model = ToolModel.new(name: "TEST1", scope: "DEFAULT", url: "http://example.com")
        model.create
        expect(model.url).to eql "http://example.com"

        model = ToolModel.new(name: "TEST2", scope: "DEFAULT", url: "vscode://vscode-remote/")
        model.create
        expect(model.url).to eql "vscode://vscode-remote/"

        model = ToolModel.new(name: "TEST3", scope: "DEFAULT", url: "/relative/path")
        model.create
        expect(model.url).to eql "/relative/path"

        model = ToolModel.new(name: "TEST4", scope: "DEFAULT", url: "something")
        expect { model.create }.to raise_error(RuntimeError, "URL must be a full URL (http://domain.com/path) or a relative path (/path)")
      end
    end

    describe "deploy" do
      it "does nothing if folder_name is undefined" do
        model = ToolModel.new(name: "TEST", scope: "DEFAULT")
        model.create
        expect(Aws::S3::Client).not_to receive(:new)
        model.deploy(Dir.pwd, {})
      end

      it "creates and deploys a ToolModel" do
        s3 = instance_double("Aws::S3::Client")
        allow(Aws::S3::Client).to receive(:new).and_return(s3)

        scope = "DEFAULT"
        folder = "DEMO"
        name = "DEMO"
        dir = File.join(SPEC_DIR, "install")
        expect(s3).to receive(:put_object).with(bucket: 'tools', key: "#{name}/index.html", body: anything, cache_control: "no-store", content_type: "text/html", metadata: nil, checksum_algorithm: anything)

        model = ToolModel.new(folder_name: folder, name: name, scope: scope, plugin: 'PLUGIN')
        model.create
        model.deploy(dir, {})

        config = ConfigTopic.read(scope: 'DEFAULT')
        expect(config[0][1]['kind']).to eql 'created'
        expect(config[0][1]['type']).to eql 'tool'
        expect(config[0][1]['name']).to eql name
        expect(config[0][1]['plugin']).to eql 'PLUGIN'
      end
    end

    describe "undeploy" do
      it "calls destroy on a deployed ToolModel" do
        s3 = instance_double("Aws::S3::Client")
        allow(Aws::S3::Client).to receive(:new).and_return(s3)
        options = OpenStruct.new
        options.key = "blah"
        objs = double("Object", :contents => [options], is_truncated: false)

        scope = "DEFAULT"
        folder = "DEMO"
        name = "DEMO"
        expect(s3).to receive(:list_objects_v2).with({bucket: 'tools', max_keys: 1000, prefix: "#{name}/", continuation_token: nil}).and_return(objs)
        expect(s3).to receive(:delete_object).with(bucket: 'tools', key: "blah")

        model = ToolModel.new(folder_name: folder, name: name, scope: scope, plugin: 'PLUGIN')
        model.undeploy

        config = ConfigTopic.read(scope: 'DEFAULT')
        expect(config[0][1]['kind']).to eql 'deleted'
        expect(config[0][1]['type']).to eql 'tool'
        expect(config[0][1]['name']).to eql name
        expect(config[0][1]['plugin']).to eql 'PLUGIN'
      end
    end
  end
end
