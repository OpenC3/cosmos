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

require "spec_helper"
require "openc3/utilities/local_mode"
require "openc3/models/scope_model"
require "openc3/models/gem_model"
require "openc3/models/plugin_model"
require "openc3/utilities/aws_bucket"

$load_plugin_plugin_file_path = []
$load_plugin_scope = []
$load_plugin_plugin_hash_file = []

def load_plugin(plugin_file_path, scope:, plugin_hash_file: nil)
  $load_plugin_plugin_file_path << plugin_file_path
  $load_plugin_scope << scope
  $load_plugin_plugin_hash_file << plugin_hash_file
end

module OpenC3
  describe LocalMode do
    before(:each) do
      ENV['OPENC3_LOCAL_MODE'] = "1"
      @tmp_dir = Dir.mktmpdir
      saved_verbose = $VERBOSE; $VERBOSE = nil
      LocalMode.const_set(:OPENC3_LOCAL_MODE_PATH, @tmp_dir)
      $VERBOSE = saved_verbose
    end

    after(:each) do
      ENV['OPENC3_LOCAL_MODE'] = nil
      FileUtils.rm_rf @tmp_dir if @tmp_dir
    end

    def setup_sync_test
      rubys3_client = double()

      # Setup local catalog
      5.times do |index|
        key = "DEFAULT/targets_modified/INST/procedures/mod#{index}.rb"
        full_path = "#{@tmp_dir}/#{key}"
        FileUtils.mkdir_p(File.dirname(full_path))
        File.open(full_path, 'wb') {|file| file.write("Some data" + ("!" * index))}
        expect(File.exist?(full_path)).to be true
      end
      2.times do |index|
        key = "DEFAULT/targets_modified/ANOTHER/screens/mod#{index}.txt"
        full_path = "#{@tmp_dir}/#{key}"
        FileUtils.mkdir_p(File.dirname(full_path))
        File.open(full_path, 'wb') {|file| file.write("Some data" + ("!" * index))}
        expect(File.exist?(full_path)).to be true
      end
      3.times do |index|
        key = "DEFAULT/targets_modified/ANOTHER/tables/mod#{index}.bin"
        full_path = "#{@tmp_dir}/#{key}"
        FileUtils.mkdir_p(File.dirname(full_path))
        File.open(full_path, 'wb') {|file| file.write("!" * index)}
        expect(File.exist?(full_path)).to be true
      end
      4.times do |index|
        key = "DEFAULT/targets_modified/ANOTHER/something/mod#{index}.ext"
        full_path = "#{@tmp_dir}/#{key}"
        FileUtils.mkdir_p(File.dirname(full_path))
        File.open(full_path, 'wb') {|file| file.write("!" * index)}
        expect(File.exist?(full_path)).to be true
      end
      2.times do |index|
        key = "DEFAULT/targets_modified/__TEMP__/temp#{index}.rb"
        full_path = "#{@tmp_dir}/#{key}"
        FileUtils.mkdir_p(File.dirname(full_path))
        File.open(full_path, 'wb') {|file| file.write("!" * index)}
        expect(File.exist?(full_path)).to be true
      end
      @total_local_files = Dir[File.join @tmp_dir, '**', '*'].count &File.method(:file?)

      # Setup remote catalog
      resp = OpenStruct.new
      resp.contents = []
      6.times do |index|
        item = OpenStruct.new
        item.key = "DEFAULT/targets_modified/INST/screens/myscreen#{index}.txt"
        item.size = index * 10
        resp.contents << item
      end
      3.times do |index|
        item = OpenStruct.new
        item.key = "DEFAULT/targets_modified/ANOTHER/tables/mod#{index}.bin"
        item.size = index
        resp.contents << item
      end
      4.times do |index|
        item = OpenStruct.new
        item.key = "DEFAULT/targets_modified/ANOTHER/something/mod#{index}.ext"
        item.size = index + 1
        resp.contents << item
      end
      2.times do |index|
        item = OpenStruct.new
        item.key = "DEFAULT/targets_modified/__TEMP__/temp#{index}.rb"
        item.size = index
        resp.contents << item
      end
      return rubys3_client, resp
    end

    def setup_plugin_test(scope: 'DEFAULT')
      gems = []
      plugin_instances = []
      3.times do |index|
        count = index + 1
        key = "#{scope}/test-plugin-#{count}/test#{count}-0.0.0.gem"
        full_path = "#{@tmp_dir}/#{key}"
        FileUtils.mkdir_p(File.dirname(full_path))
        File.open(full_path, 'wb') {|file| file.write("I'm a gem! #{count}")}
        expect(File.exist?(full_path)).to be true
        gems << full_path

        key = "#{scope}/test-plugin-#{count}/plugin_instance.json"
        full_path = "#{@tmp_dir}/#{key}"
        FileUtils.mkdir_p(File.dirname(full_path))
        File.open(full_path, 'wb') {|file| file.write("{\"name\": \"test#{count}-0.0.0.gem__2022080810203\"}")}
        expect(File.exist?(full_path)).to be true
        plugin_instances << full_path
      end

      key = "#{scope}/test-plugin-4/test4-0.0.0.gem"
      full_path = "#{@tmp_dir}/#{key}"
      FileUtils.mkdir_p(File.dirname(full_path))
      File.open(full_path, 'wb') {|file| file.write("I'm a gem! 4")}
      expect(File.exist?(full_path)).to be true
      gems << full_path
      plugin_instances << nil

      key = "#{scope}/test-plugin-5/plugin_instance.json"
      full_path = "#{@tmp_dir}/#{key}"
      FileUtils.mkdir_p(File.dirname(full_path))
      File.open(full_path, 'wb') {|file| file.write('{"name": "test5-0.0.0.gem__2022080810203"}')}
      expect(File.exist?(full_path)).to be true
      gems << nil
      plugin_instances << full_path

      return gems, plugin_instances
    end

    describe "local_init" do
      it "should load plugins and sync targets modified if necessary" do
        mock_redis()
        ScopeModel.new(name: 'DEFAULT').create

        ENV['OPENC3_LOCAL_MODE_SECONDARY'] = nil
        ENV['OPENC3_LOCAL_MODE_FORCE_SYNC'] = nil
        ENV['OPENC3_LOCAL_MODE_SYNC_REMOVE'] = nil
        rubys3_client, resp = setup_sync_test()
        expect(Aws::S3::Client).to receive(:new).and_return(rubys3_client)
        expect(rubys3_client).to receive(:list_objects_v2).and_return(resp)

        gems, plugin_instances = setup_plugin_test()
        other_gems, other_plugin_instances = setup_plugin_test(scope: 'OTHER')

        FileUtils.mkdir_p("#{@tmp_dir}/OTHER/test-plugin-8/")
        File.write("#{@tmp_dir}/OTHER/test-plugin-8/test8-0.0.0.gem", 'wb') {|file| file.write("One gem")}
        File.write("#{@tmp_dir}/OTHER/test-plugin-8/test8-0.0.1.gem", 'wb') {|file| file.write("Two gem")}

        expect(rubys3_client).to receive(:put_object).exactly(11).times
        6.times do |index|
          key = "DEFAULT/targets_modified/INST/screens/myscreen#{index}.txt"
          full_path = "#{@tmp_dir}/#{key}"
          expect(rubys3_client).to receive(:get_object).with({bucket: 'config', key: key, response_target: full_path })
        end

        LocalMode.local_init

        expect($load_plugin_plugin_file_path.length).to eq 8
      end

      it "should handle not local mode" do
        ENV['OPENC3_LOCAL_MODE'] = nil
        LocalMode.local_init
      end
    end

    describe "analyze_local_mode" do
      it "should return nil if no known plugins registered" do
        test_gems, test_plugin_instances = setup_plugin_test()
        models = {}
        allow(OpenC3::PluginModel).to receive(:all).and_return(models)
        result = LocalMode.analyze_local_mode(plugin_name: "test1-0.0.0.gem", scope: 'DEFAULT')
        expect(result).to be_nil
      end

      it "should determine if a similar plugin already exists - test1" do
        test_gems, test_plugin_instances = setup_plugin_test()
        models = {}
        models['test3-0.0.0.gem__2022080810203'] = 1
        models['test3-0.0.0.gem__2022080810234'] = 2

        # We have two installed plugins and one local one that matches names
        # That leaves no local plugins so should return nil

        allow(OpenC3::PluginModel).to receive(:all).and_return(models)
        result = LocalMode.analyze_local_mode(plugin_name: "test3-0.0.0.gem", scope: 'DEFAULT')
        expect(result).to be_nil
      end

      it "should determine if a similar plugin already exists - test2" do
        test_gems, test_plugin_instances = setup_plugin_test()
        models = {}
        models['test2-0.0.0.gem__2022080810203'] = 1
        models['test3-0.0.0.gem__2022080810234'] = 2

        # We have two installed plugins and one local one that matches gems but not names
        # Therefore assume it is the same plugin instance

        allow(OpenC3::PluginModel).to receive(:all).and_return(models)
        result = LocalMode.analyze_local_mode(plugin_name: "test3-0.0.0.gem", scope: 'DEFAULT')
        expect(result).to be 2
      end

      it "should determine if a similar plugin already exists - test3" do
        test_gems, test_plugin_instances = setup_plugin_test()
        models = {}
        models['test2-0.0.0.gem__2022080810203'] = 1
        models['test3-0.0.0.gem__2022080810234'] = 2

        # We have two installed plugins and one local one that doesn't match them at all
        # Therefore return nil

        allow(OpenC3::PluginModel).to receive(:all).and_return(models)
        result = LocalMode.analyze_local_mode(plugin_name: "test4-0.0.0.gem", scope: 'DEFAULT')
        expect(result).to be_nil
      end

      it "should determine if a similar plugin already exists - test4" do
        test_gems, test_plugin_instances = setup_plugin_test()
        models = {}
        models['test2-0.0.0.gem__2022080810203'] = 2
        FileUtils.mkdir_p("#{@tmp_dir}/DEFAULT/test3")
        File.open("#{@tmp_dir}/DEFAULT/test3/test3-0.0.0.gem", 'wb') {|file| file.write("This is a gem!!!")}
        File.open("#{@tmp_dir}/DEFAULT/test3/plugin_instance.json", 'wb') {|file| file.write("{\"name\": \"test3-0.0.0.gem__2022070810204\"}")}

        # We have one installed plugins and two local ones - one matches name but not the other
        # Therefore return nil

        allow(OpenC3::PluginModel).to receive(:all).and_return(models)
        result = LocalMode.analyze_local_mode(plugin_name: "test3-0.0.0.gem", scope: 'DEFAULT')
        expect(result).to be_nil
      end
    end

    describe "update_local_plugin" do
      it "syncs a local plugin to a fully installed remote plugin - in local init" do
        test_gems, test_plugin_instances = setup_plugin_test()
        key = "DEFAULT/test-plugin-2/test2-0.0.0.gem"
        plugin_file_path = "#{@tmp_dir}/#{key}"
        plugin_hash = {}
        plugin_hash['variables'] = {"target_name" => "BOB", "microservice_name" => "FRED", "other" => "TED"}
        LocalMode.update_local_plugin(plugin_file_path, plugin_hash, old_plugin_name: nil, scope: 'DEFAULT')
        expect(plugin_hash['variables']).to eq({"other" => "TED"})
        expect(JSON.parse(File.read(test_plugin_instances[1]))).to eq({"variables" => {"other" => "TED"}})
      end

      it "syncs a local plugin to a fully installed remote plugin - online install - doesn't exist local" do
        other_tmp_dir = Dir.mktmpdir
        begin
          test_gems, test_plugin_instances = setup_plugin_test()
          plugin_file_path = "#{other_tmp_dir}/test7-0.0.0.gem"
          File.open(plugin_file_path, 'wb') {|file| file.write("This is a gem!!!")}
          plugin_hash = {}
          plugin_hash['variables'] = {"target_name" => "BOB", "microservice_name" => "FRED", "other" => "TED"}
          LocalMode.update_local_plugin(plugin_file_path, plugin_hash, old_plugin_name: nil, scope: 'DEFAULT')
          expect(plugin_hash['variables']).to eq({"other" => "TED"})
          expect(File.read("#{@tmp_dir}/DEFAULT/test7/test7-0.0.0.gem")).to eq "This is a gem!!!"
          expect(JSON.parse(File.read("#{@tmp_dir}/DEFAULT/test7/plugin_instance.json"))).to eq({"variables" => {"other" => "TED"}})
        ensure
          FileUtils.rm_rf other_tmp_dir if other_tmp_dir
        end
      end

      it "syncs a local plugin to a fully installed remote plugin - online install - does exist local - not upgrade" do
        other_tmp_dir = Dir.mktmpdir
        begin
          test_gems, test_plugin_instances = setup_plugin_test()
          FileUtils.mkdir_p("#{@tmp_dir}/DEFAULT/test3")
          plugin_file_path = "#{other_tmp_dir}/test3-0.0.0.gem"
          File.open(plugin_file_path, 'wb') {|file| file.write("This is a gem!!!")}
          plugin_hash = {}
          plugin_hash['variables'] = {"target_name" => "BOB", "microservice_name" => "FRED", "other" => "TED"}
          LocalMode.update_local_plugin(plugin_file_path, plugin_hash, old_plugin_name: nil, scope: 'DEFAULT')
          expect(plugin_hash['variables']).to eq({"other" => "TED"})
          expect(File.read("#{@tmp_dir}/DEFAULT/test3-1/test3-0.0.0.gem")).to eq "This is a gem!!!"
          expect(JSON.parse(File.read("#{@tmp_dir}/DEFAULT/test3-1/plugin_instance.json"))).to eq({"variables" => {"other" => "TED"}})
        ensure
          FileUtils.rm_rf other_tmp_dir if other_tmp_dir
        end
      end

      it "syncs a local plugin to a fully installed remote plugin - online install - does exist local - not upgrade - just gem local" do
        other_tmp_dir = Dir.mktmpdir
        begin
          test_gems, test_plugin_instances = setup_plugin_test()
          File.delete(test_plugin_instances[2])
          plugin_file_path = "#{other_tmp_dir}/test3-0.0.0.gem"
          File.open(plugin_file_path, 'wb') {|file| file.write("This is a gem!!!")}
          plugin_hash = {}
          plugin_hash['variables'] = {"target_name" => "BOB", "microservice_name" => "FRED", "other" => "TED"}
          LocalMode.update_local_plugin(plugin_file_path, plugin_hash, old_plugin_name: nil, scope: 'DEFAULT')
          expect(plugin_hash['variables']).to eq({"other" => "TED"})
          expect(File.read("#{@tmp_dir}/DEFAULT/test-plugin-3/test3-0.0.0.gem")).to eq "This is a gem!!!"
          expect(JSON.parse(File.read("#{@tmp_dir}/DEFAULT/test-plugin-3/plugin_instance.json"))).to eq({"variables" => {"other" => "TED"}})
        ensure
          FileUtils.rm_rf other_tmp_dir if other_tmp_dir
        end
      end

      it "syncs a local plugin to a fully installed remote plugin - online install - does exist local - upgrade" do
        other_tmp_dir = Dir.mktmpdir
        begin
          test_gems, test_plugin_instances = setup_plugin_test()
          plugin_file_path = "#{other_tmp_dir}/test3-0.0.0.gem"
          File.open(plugin_file_path, 'wb') {|file| file.write("This is a gem!!!")}
          plugin_hash = {}
          plugin_hash['variables'] = {"target_name" => "BOB", "microservice_name" => "FRED", "other" => "TED"}
          LocalMode.update_local_plugin(plugin_file_path, plugin_hash, old_plugin_name: "test3-0.0.0.gem__2022080810203", scope: 'DEFAULT')
          expect(plugin_hash['variables']).to eq({"other" => "TED"})
          expect(File.read("#{@tmp_dir}/DEFAULT/test-plugin-3/test3-0.0.0.gem")).to eq "This is a gem!!!"
          expect(JSON.parse(File.read("#{@tmp_dir}/DEFAULT/test-plugin-3/plugin_instance.json"))).to eq({"variables" => {"other" => "TED"}})
        ensure
          FileUtils.rm_rf other_tmp_dir if other_tmp_dir
        end
      end

      it "syncs a local plugin to a fully installed remote plugin - online install - doesn't exist local - upgrade" do
        other_tmp_dir = Dir.mktmpdir
        begin
          test_gems, test_plugin_instances = setup_plugin_test()
          plugin_file_path = "#{other_tmp_dir}/test7-0.0.0.gem"
          File.open(plugin_file_path, 'wb') {|file| file.write("This is a gem!!!")}
          plugin_hash = {}
          plugin_hash['variables'] = {"target_name" => "BOB", "microservice_name" => "FRED", "other" => "TED"}
          LocalMode.update_local_plugin(plugin_file_path, plugin_hash, old_plugin_name: "test7-0.0.0.gem__2022080810203", scope: 'DEFAULT')
          expect(plugin_hash['variables']).to eq({"other" => "TED"})
          expect(File.read("#{@tmp_dir}/DEFAULT/test7/test7-0.0.0.gem")).to eq "This is a gem!!!"
          expect(JSON.parse(File.read("#{@tmp_dir}/DEFAULT/test7/plugin_instance.json"))).to eq({"variables" => {"other" => "TED"}})
        ensure
          FileUtils.rm_rf other_tmp_dir if other_tmp_dir
        end
      end
    end

    describe "update_local_plugin_files" do
      it "puts the correct gem and plugin_instance.json into a plugin path" do
        test_gems, test_plugin_instances = setup_plugin_test()
        allow(OpenC3::GemModel).to receive(:get).and_return(test_gems[1])
        full_folder_path = File.dirname(test_gems[0])
        plugin_file_path = "test1-0.0.0.gem"
        plugin_hash = {"name": "test2-0.0.0.gem__2022080810203"}
        gem_name = "test1"
        expect(File.read(test_gems[0])).to eq "I'm a gem! 1"
        expect(JSON.parse(File.read(test_plugin_instances[0]))).to eq({"name" => "test1-0.0.0.gem__2022080810203"})
        LocalMode.update_local_plugin_files(full_folder_path, plugin_file_path, plugin_hash, gem_name)
        expect(File.read(File.dirname(test_gems[0]) + "/test2-0.0.0.gem")).to eq "I'm a gem! 2"
        expect(JSON.parse(File.read(test_plugin_instances[0]))).to eq({"name" => "test2-0.0.0.gem__2022080810203"})
      end

      it "puts the correct gem and plugin_instance.json into a plugin path with existing local gem" do
        test_gems, test_plugin_instances = setup_plugin_test()
        allow(OpenC3::GemModel).to receive(:get).and_return(test_gems[1])
        full_folder_path = File.dirname(test_gems[0])
        plugin_file_path = test_gems[2]
        plugin_hash = {"name": "test2-0.0.0.gem__2022080810203"}
        gem_name = "test1"
        expect(File.read(test_gems[0])).to eq "I'm a gem! 1"
        expect(JSON.parse(File.read(test_plugin_instances[0]))).to eq({"name" => "test1-0.0.0.gem__2022080810203"})
        LocalMode.update_local_plugin_files(full_folder_path, plugin_file_path, plugin_hash, gem_name)
        expect(File.read(File.dirname(test_gems[0]) + "/test3-0.0.0.gem")).to eq "I'm a gem! 3"
        expect(JSON.parse(File.read(test_plugin_instances[0]))).to eq({"name" => "test2-0.0.0.gem__2022080810203"})
      end
    end

    describe "scan_plugin_dir" do
      it "should scan a plugin dir" do
        test_gems, test_plugin_instances = setup_plugin_test()
        full_path = File.dirname(test_gems[0])
        gems, plugin_instance = LocalMode.scan_plugin_dir(full_path)
        expect(gems.length).to be 1
        expect(plugin_instance).to_not be_nil
      end
    end

    describe "scan_local_mode" do
      it "discovers all the local plugins" do
        gems, plugin_instances = setup_plugin_test()
        gems_other, plugin_instances_other = setup_plugin_test(scope: 'OTHER')
        local_plugins = LocalMode.scan_local_mode
        expect(local_plugins.length).to be 2
        expect(local_plugins['DEFAULT'].length).to be 5
        5.times do |index|
          count = index + 1
          key = "DEFAULT/test-plugin-#{count}"
          full_path = "#{@tmp_dir}/#{key}"
          expect(local_plugins['DEFAULT'][full_path][:gems]).to eq ["#{full_path}/test#{count}-0.0.0.gem"] if count != 5
          expect(local_plugins['DEFAULT'][full_path][:plugin_instance]).to eq "#{full_path}/plugin_instance.json" if count != 4
          expect(local_plugins['DEFAULT'][full_path][:gems]).to eq [] if count == 5
          expect(local_plugins['DEFAULT'][full_path][:plugin_instance]).to eq nil if count == 4
        end
        expect(local_plugins['OTHER'].length).to be 5
        5.times do |index|
          count = index + 1
          key = "OTHER/test-plugin-#{count}"
          full_path = "#{@tmp_dir}/#{key}"
          expect(local_plugins['OTHER'][full_path][:gems]).to eq ["#{full_path}/test#{count}-0.0.0.gem"] if count != 5
          expect(local_plugins['OTHER'][full_path][:plugin_instance]).to eq "#{full_path}/plugin_instance.json" if count != 4
          expect(local_plugins['OTHER'][full_path][:gems]).to eq [] if count == 5
          expect(local_plugins['OTHER'][full_path][:plugin_instance]).to eq nil if count == 4
        end
      end

      it "handles not local mode" do
        ENV['OPENC3_LOCAL_MODE'] = nil
        result = LocalMode.scan_local_mode
        expect(result).to eq({})
      end
    end

    describe "remove_local_plugin" do
      it "removes the gem and plugin_instance.json file from a local plugin" do
        gems, plugin_instances = setup_plugin_test()
        gems_other, plugin_instances_other = setup_plugin_test(scope: 'OTHER')
        name = JSON.parse(File.read(plugin_instances[0]))['name']
        LocalMode.remove_local_plugin(name, scope: 'ANOTHER')
        expect(File.exist?(gems[0])).to be true
        expect(File.exist?(plugin_instances[0])).to be true
        expect(File.exist?(gems[1])).to be true
        expect(File.exist?(plugin_instances[1])).to be true
        expect(File.exist?(gems_other[0])).to be true
        expect(File.exist?(plugin_instances_other[0])).to be true
        LocalMode.remove_local_plugin(name, scope: 'DEFAULT')
        expect(File.exist?(gems[0])).to be false
        expect(File.exist?(plugin_instances[0])).to be false
        expect(File.exist?(gems[1])).to be true
        expect(File.exist?(plugin_instances[1])).to be true
        expect(File.exist?(gems_other[0])).to be true
        expect(File.exist?(plugin_instances_other[0])).to be true
        LocalMode.remove_local_plugin(name, scope: 'OTHER')
        expect(File.exist?(gems[0])).to be false
        expect(File.exist?(plugin_instances[0])).to be false
        expect(File.exist?(gems[1])).to be true
        expect(File.exist?(plugin_instances[1])).to be true
        expect(File.exist?(gems_other[0])).to be false
        expect(File.exist?(plugin_instances_other[0])).to be false
      end

      it "ignores incomplete local plugins" do
        gems, plugin_instances = setup_plugin_test()
        name = JSON.parse(File.read(plugin_instances[4]))['name']
        LocalMode.remove_local_plugin(name, scope: 'DEFAULT')
        expect(File.exist?(plugin_instances[4])).to be true
        LocalMode.remove_local_plugin('test4-0.0.0.gem__2022080810203', scope: 'DEFAULT')
        expect(File.exist?(gems[3])).to be true
      end
    end

    describe "modified_targets" do
      it "lists all local targets with existing files" do
        setup_sync_test()
        modified = LocalMode.modified_targets(scope: 'DEFAULT')
        expect(modified[0]).to eq 'ANOTHER'
        expect(modified[1]).to eq 'INST'
        expect(modified[2]).to eq '__TEMP__'
        expect(modified.length).to be 3
      end
    end

    describe "modified_files" do
      it "lists local modified files for a target" do
        setup_sync_test()
        modified = LocalMode.modified_files('INST', scope: 'DEFAULT')
        5.times do |index|
          key = "procedures/mod#{index}.rb"
          expect(modified[index]).to eq key
        end
      end
    end

    describe "delete_modified" do
      it "deletes all local modified files for a target" do
        setup_sync_test()
        LocalMode.delete_modified('ANOTHER', scope: 'DEFAULT')
        5.times do |index|
          key = "DEFAULT/targets_modified/INST/procedures/mod#{index}.rb"
          full_path = "#{@tmp_dir}/#{key}"
          expect(File.exist?(full_path)).to be true
        end
        2.times do |index|
          key = "DEFAULT/targets_modified/ANOTHER/screens/mod#{index}.txt"
          full_path = "#{@tmp_dir}/#{key}"
          expect(File.exist?(full_path)).to be false
        end
        3.times do |index|
          key = "DEFAULT/targets_modified/ANOTHER/tables/mod#{index}.bin"
          full_path = "#{@tmp_dir}/#{key}"
          expect(File.exist?(full_path)).to be false
        end
        4.times do |index|
          key = "DEFAULT/targets_modified/ANOTHER/something/mod#{index}.ext"
          full_path = "#{@tmp_dir}/#{key}"
          expect(File.exist?(full_path)).to be false
        end
      end
    end

    describe "zip_target" do
      it "Adds local modified files to zip archive" do
        setup_sync_test()
        Zip.continue_on_exists_proc = true
        zip_filename = "#{@tmp_dir}/test.zip"
        zip = Zip::File.open(zip_filename, Zip::File::CREATE)
        LocalMode.zip_target('INST', zip, scope: 'DEFAULT')
        zip.close
        expect(File.exist?(zip_filename)).to be true
        expect(File.size(zip_filename)).to be > 20
      end
    end

    describe "delete_local" do
      it "deletes a local version of a file" do
        key = "DEFAULT/targets_modified/INST/procedures/mod.rb"
        full_path = "#{@tmp_dir}/#{key}"
        FileUtils.mkdir_p(File.dirname(full_path))
        File.open(full_path, 'wb') {|file| file.write("Some data")}
        expect(File.exist?(full_path)).to be true
        LocalMode.delete_local(key)
        expect(File.exist?(full_path)).to be false
      end
    end

    describe "delete_remote" do
      it "deletes a remote version of a file" do
        key = "DEFAULT/targets_modified/INST/procedures/mod.rb"
        rubys3_client = double()
        expect(rubys3_client).to receive(:delete_object).with({bucket: 'config', key: key})
        expect(Aws::S3::Client).to receive(:new).and_return(rubys3_client)
        LocalMode.delete_remote(Bucket.getClient, key)
      end
    end

    describe "sync_remote_to_local" do
      it "copies a remote file to local" do
        key = "DEFAULT/targets_modified/INST/procedures/mod.rb"
        full_path = "#{@tmp_dir}/#{key}"
        rubys3_client = double()
        expect(rubys3_client).to receive(:get_object).with({bucket: 'config', key: key, response_target: full_path })
        expect(Aws::S3::Client).to receive(:new).and_return(rubys3_client)
        LocalMode.sync_remote_to_local(Bucket.getClient, key)
      end
    end

    describe "sync_local_to_remote" do
      it "copies a local file to remote" do
        key = "DEFAULT/targets_modified/INST/procedures/mod.rb"
        full_path = "#{@tmp_dir}/#{key}"
        FileUtils.mkdir_p(File.dirname(full_path))
        File.open(full_path, 'wb') {|file| file.write("Some data")}
        expect(File.exist?(full_path)).to be true
        rubys3_client = double()
        expect(rubys3_client).to receive(:put_object)
        expect(Aws::S3::Client).to receive(:new).and_return(rubys3_client)
        LocalMode.sync_local_to_remote(Bucket.getClient, key)
      end
    end

    describe "build_local_catalog" do
      it "builds scoped local catalogs" do
        10.times do |index|
          key = "DEFAULT/targets_modified/INST/procedures/mod#{index}.rb"
          full_path = "#{@tmp_dir}/#{key}"
          FileUtils.mkdir_p(File.dirname(full_path))
          File.open(full_path, 'wb') {|file| file.write("Some data" + ("!" * index))}
          expect(File.exist?(full_path)).to be true
        end
        5.times do |index|
          key = "OTHER/targets_modified/ANOTHER/procedures/mod#{index}.rb"
          full_path = "#{@tmp_dir}/#{key}"
          FileUtils.mkdir_p(File.dirname(full_path))
          File.open(full_path, 'wb') {|file| file.write("Some data" + ("!" * index))}
          expect(File.exist?(full_path)).to be true
        end
        catalog = LocalMode.build_local_catalog(scope: 'NONEXISTANT')
        expect(catalog.length).to be 0
        catalog = LocalMode.build_local_catalog(scope: 'DEFAULT')
        expect(catalog.length).to be 10
        10.times do |index|
          expect(catalog["DEFAULT/targets_modified/INST/procedures/mod#{index}.rb"]).to be 9 + index
        end
        catalog = LocalMode.build_local_catalog(scope: 'OTHER')
        expect(catalog.length).to be 5
        5.times do |index|
          expect(catalog["OTHER/targets_modified/ANOTHER/procedures/mod#{index}.rb"]).to be 9 + index
        end
      end
    end

    describe "build_remote_catalog" do
      it "builds scoped local catalogs" do
        resp = OpenStruct.new
        resp.contents = []
        rubys3_client = double()
        prefix = 'NONEXISTANT/targets_modified'
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix}).and_return(resp)
        expect(Aws::S3::Client).to receive(:new).and_return(rubys3_client)
        catalog = LocalMode.build_remote_catalog(Bucket.getClient, scope: 'NONEXISTANT')
        expect(catalog.length).to eql 0

        resp = OpenStruct.new
        resp.contents = []
        6.times do |index|
          item = OpenStruct.new
          item.key = "DEFAULT/targets_modified/INST/screens/myscreen#{index}.txt"
          item.size = index * 10
          resp.contents << item
        end
        rubys3_client = double()
        prefix = 'DEFAULT/targets_modified'
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix}).and_return(resp)
        expect(Aws::S3::Client).to receive(:new).and_return(rubys3_client)
        catalog = LocalMode.build_remote_catalog(Bucket.getClient, scope: 'DEFAULT')
        expect(catalog.length).to eql 6
        6.times do |index|
          expect(catalog["DEFAULT/targets_modified/INST/screens/myscreen#{index}.txt"]).to be (index * 10)
        end

        resp = OpenStruct.new
        resp.contents = []
        3.times do |index|
          item = OpenStruct.new
          item.key = "OTHER/targets_modified/INST/screens/myscreen#{index}.txt"
          item.size = index * 10
          resp.contents << item
        end
        rubys3_client = double()
        prefix = 'OTHER/targets_modified'
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix}).and_return(resp)
        expect(Aws::S3::Client).to receive(:new).and_return(rubys3_client)
        catalog = LocalMode.build_remote_catalog(Bucket.getClient, scope: 'OTHER')
        expect(catalog.length).to eql 3
        3.times do |index|
          expect(catalog["OTHER/targets_modified/INST/screens/myscreen#{index}.txt"]).to be (index * 10)
        end
      end
    end

    describe "sync_with_bucket" do
      it "should sync local and remote targets_modified files with local primary" do
        ENV['OPENC3_LOCAL_MODE_SECONDARY'] = nil
        ENV['OPENC3_LOCAL_MODE_FORCE_SYNC'] = nil
        ENV['OPENC3_LOCAL_MODE_SYNC_REMOVE'] = nil
        rubys3_client, resp = setup_sync_test()
        expect(Aws::S3::Client).to receive(:new).and_return(rubys3_client)

        prefix = 'DEFAULT/targets_modified'
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix}).and_return(resp)

        expect(rubys3_client).to receive(:put_object).exactly(11).times
        6.times do |index|
          key = "DEFAULT/targets_modified/INST/screens/myscreen#{index}.txt"
          full_path = "#{@tmp_dir}/#{key}"
          expect(rubys3_client).to receive(:get_object).with({bucket: 'config', key: key, response_target: full_path })
        end
        LocalMode.sync_with_bucket(Bucket.getClient, scope: 'DEFAULT')
      end

      it "should sync local and remote targets_modified files with local secondary" do
        ENV['OPENC3_LOCAL_MODE_SECONDARY'] = "1"
        ENV['OPENC3_LOCAL_MODE_FORCE_SYNC'] = nil
        ENV['OPENC3_LOCAL_MODE_SYNC_REMOVE'] = nil
        rubys3_client, resp = setup_sync_test()
        expect(Aws::S3::Client).to receive(:new).and_return(rubys3_client)

        prefix = 'DEFAULT/targets_modified'
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix}).and_return(resp)

        expect(rubys3_client).to receive(:put_object).exactly(7).times
        6.times do |index|
          key = "DEFAULT/targets_modified/INST/screens/myscreen#{index}.txt"
          full_path = "#{@tmp_dir}/#{key}"
          expect(rubys3_client).to receive(:get_object).with({bucket: 'config', key: key, response_target: full_path })
        end
        4.times do |index|
          key = "DEFAULT/targets_modified/ANOTHER/something/mod#{index}.ext"
          full_path = "#{@tmp_dir}/#{key}"
          expect(rubys3_client).to receive(:get_object).with({bucket: 'config', key: key, response_target: full_path })
        end
        LocalMode.sync_with_bucket(Bucket.getClient, scope: 'DEFAULT')
      end

      it "should sync local and remote targets_modified files with local primary and force" do
        ENV['OPENC3_LOCAL_MODE_SECONDARY'] = nil
        ENV['OPENC3_LOCAL_MODE_FORCE_SYNC'] = "1"
        ENV['OPENC3_LOCAL_MODE_SYNC_REMOVE'] = nil
        rubys3_client, resp = setup_sync_test()
        expect(Aws::S3::Client).to receive(:new).and_return(rubys3_client)

        prefix = 'DEFAULT/targets_modified'
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix}).and_return(resp)

        expect(rubys3_client).to receive(:put_object).exactly(@total_local_files).times
        6.times do |index|
          key = "DEFAULT/targets_modified/INST/screens/myscreen#{index}.txt"
          full_path = "#{@tmp_dir}/#{key}"
          expect(rubys3_client).to receive(:get_object).with({bucket: 'config', key: key, response_target: full_path })
        end
        LocalMode.sync_with_bucket(Bucket.getClient, scope: 'DEFAULT')
      end

      it "should sync local and remote targets_modified files with local secondary and force" do
        ENV['OPENC3_LOCAL_MODE_SECONDARY'] = "1"
        ENV['OPENC3_LOCAL_MODE_FORCE_SYNC'] = "1"
        ENV['OPENC3_LOCAL_MODE_SYNC_REMOVE'] = nil
        rubys3_client, resp = setup_sync_test()
        expect(Aws::S3::Client).to receive(:new).and_return(rubys3_client)

        prefix = 'DEFAULT/targets_modified'
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix}).and_return(resp)

        expect(rubys3_client).to receive(:put_object).exactly(7).times
        6.times do |index|
          key = "DEFAULT/targets_modified/INST/screens/myscreen#{index}.txt"
          full_path = "#{@tmp_dir}/#{key}"
          expect(rubys3_client).to receive(:get_object).with({bucket: 'config', key: key, response_target: full_path })
        end
        3.times do |index|
          key = "DEFAULT/targets_modified/ANOTHER/tables/mod#{index}.bin"
          full_path = "#{@tmp_dir}/#{key}"
          expect(rubys3_client).to receive(:get_object).with({bucket: 'config', key: key, response_target: full_path })
        end
        4.times do |index|
          key = "DEFAULT/targets_modified/ANOTHER/something/mod#{index}.ext"
          full_path = "#{@tmp_dir}/#{key}"
          expect(rubys3_client).to receive(:get_object).with({bucket: 'config', key: key, response_target: full_path })
        end
        2.times do |index|
          key = "DEFAULT/targets_modified/__TEMP__/temp#{index}.rb"
          full_path = "#{@tmp_dir}/#{key}"
          expect(rubys3_client).to receive(:get_object).with({bucket: 'config', key: key, response_target: full_path })
        end
        LocalMode.sync_with_bucket(Bucket.getClient, scope: 'DEFAULT')
      end

      it "should sync local and remote targets_modified files with local primary and remove" do
        ENV['OPENC3_LOCAL_MODE_SECONDARY'] = nil
        ENV['OPENC3_LOCAL_MODE_FORCE_SYNC'] = nil
        ENV['OPENC3_LOCAL_MODE_SYNC_REMOVE'] = "1"
        rubys3_client, resp = setup_sync_test()
        expect(Aws::S3::Client).to receive(:new).and_return(rubys3_client)

        prefix = 'DEFAULT/targets_modified'
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix}).and_return(resp)

        expect(rubys3_client).to receive(:put_object).exactly(11).times
        6.times do |index|
          key = "DEFAULT/targets_modified/INST/screens/myscreen#{index}.txt"
          full_path = "#{@tmp_dir}/#{key}"
          expect(rubys3_client).to receive(:delete_object).with({bucket: 'config', key: key })
        end
        LocalMode.sync_with_bucket(Bucket.getClient, scope: 'DEFAULT')
      end

      it "should sync local and remote targets_modified files with local secondary and remove" do
        ENV['OPENC3_LOCAL_MODE_SECONDARY'] = "1"
        ENV['OPENC3_LOCAL_MODE_FORCE_SYNC'] = nil
        ENV['OPENC3_LOCAL_MODE_SYNC_REMOVE'] = "1"
        rubys3_client, resp = setup_sync_test()
        expect(Aws::S3::Client).to receive(:new).and_return(rubys3_client)

        prefix = 'DEFAULT/targets_modified'
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix}).and_return(resp)

        expect(rubys3_client).to receive(:put_object).exactly(0).times
        6.times do |index|
          key = "DEFAULT/targets_modified/INST/screens/myscreen#{index}.txt"
          full_path = "#{@tmp_dir}/#{key}"
          expect(rubys3_client).to receive(:get_object).with({bucket: 'config', key: key, response_target: full_path })
        end
        4.times do |index|
          key = "DEFAULT/targets_modified/ANOTHER/something/mod#{index}.ext"
          full_path = "#{@tmp_dir}/#{key}"
          expect(rubys3_client).to receive(:get_object).with({bucket: 'config', key: key, response_target: full_path })
        end
        LocalMode.sync_with_bucket(Bucket.getClient, scope: 'DEFAULT')
        5.times do |index|
          key = "DEFAULT/targets_modified/INST/procedures/mod#{index}.rb"
          full_path = "#{@tmp_dir}/#{key}"
          expect(File.exist?(full_path)).to be false
        end
        2.times do |index|
          key = "DEFAULT/targets_modified/ANOTHER/screens/mod#{index}.txt"
          full_path = "#{@tmp_dir}/#{key}"
          expect(File.exist?(full_path)).to be false
        end
      end
    end

    describe "sync_targets_modified" do
      it "should sync the scope" do
        mock_redis()
        ScopeModel.new(name: 'DEFAULT').create

        ENV['OPENC3_LOCAL_MODE_SECONDARY'] = nil
        ENV['OPENC3_LOCAL_MODE_FORCE_SYNC'] = nil
        ENV['OPENC3_LOCAL_MODE_SYNC_REMOVE'] = nil
        rubys3_client, resp = setup_sync_test()
        expect(Aws::S3::Client).to receive(:new).and_return(rubys3_client)

        prefix = 'DEFAULT/targets_modified'
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix}).and_return(resp)

        expect(rubys3_client).to receive(:put_object).exactly(11).times
        6.times do |index|
          key = "DEFAULT/targets_modified/INST/screens/myscreen#{index}.txt"
          full_path = "#{@tmp_dir}/#{key}"
          expect(rubys3_client).to receive(:get_object).with({bucket: 'config', key: key, response_target: full_path })
        end
        LocalMode.sync_targets_modified
      end
    end

    describe "local_target_files" do
      it "lists all the local files in a specified path for all targets" do
        setup_sync_test()
        result = LocalMode.local_target_files(scope: 'DEFAULT', path_matchers: ['screens'])
        expect(result.length).to be 2
        2.times do |index|
          key = "ANOTHER/screens/mod#{index}.txt"
          expect(result[index]).to eq key
        end

        result = LocalMode.local_target_files(scope: 'DEFAULT', path_matchers: ['procedures'])
        expect(result.length).to be 5
        5.times do |index|
          key = "INST/procedures/mod#{index}.rb"
          expect(result[index]).to eq key
        end

        result = LocalMode.local_target_files(scope: 'DEFAULT', path_matchers: ['tables', 'something'])
        expect(result.length).to be 7
        4.times do |index|
          key = "ANOTHER/something/mod#{index}.ext"
          expect(result[index]).to eq key
        end
        3.times do |index|
          key = "ANOTHER/tables/mod#{index}.bin"
          expect(result[index + 4]).to eq key
        end
      end

      it "optionally includes temp files" do
        setup_sync_test()
        result = LocalMode.local_target_files(scope: 'DEFAULT', path_matchers: ['screens'], include_temp: true)
        expect(result.length).to be 4
        2.times do |index|
          key = "ANOTHER/screens/mod#{index}.txt"
          expect(result[index]).to eq key
        end
        2.times do |index|
          key = "__TEMP__/temp#{index}.rb"
          expect(result[index + 2]).to eq key
        end
      end
    end

    describe "open_local_file" do
      it "opens local files" do
        setup_sync_test()
        key = "ANOTHER/something/mod0.ext"
        file = LocalMode.open_local_file(key, scope: 'DEFAULT')
        expect(file).to be_a File
        file.close
        file = LocalMode.open_local_file("fake", scope: 'DEFAULT')
        expect(file).to be_nil
      end

      it "responds to delete" do
        setup_sync_test()
        key = "ANOTHER/something/mod0.ext"
        file = LocalMode.open_local_file(key, scope: 'DEFAULT')
        expect(File.exist?(file.path)).to be true
        file.delete
        expect(File.exist?(file.path)).to be false
      end
    end

    describe "put_target_file" do
      it "puts a target file locally" do
        path = "DEFAULT/demo-plugin/afile.rb"
        string = "Some data for the file"
        LocalMode.put_target_file(path, string, scope: 'DEFAULT')
        full_path = "#{@tmp_dir}/#{path}"
        expect(File.exist?(full_path)).to be true
        expect(File.read(full_path)).to eq string

        path = "DEFAULT/demo-plugin/bfile.rb"
        stringio = StringIO.new("Some data for the file again")
        LocalMode.put_target_file(path, stringio, scope: 'DEFAULT')
        full_path = "#{@tmp_dir}/#{path}"
        expect(File.exist?(full_path)).to be true
        stringio.rewind
        expect(File.read(full_path)).to eq stringio.read
      end
    end
  end
end
