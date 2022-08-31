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

require "spec_helper"
require "openc3/utilities/local_mode"
require "openc3/models/scope_model"

module OpenC3
  describe LocalMode do
    before(:each) do
      @tmp_dir = Dir.mktmpdir
      saved_verbose = $VERBOSE; $VERBOSE = nil
      LocalMode.const_set(:OPENC3_LOCAL_MODE_PATH, @tmp_dir)
      $VERBOSE = saved_verbose
    end

    after(:each) do
      FileUtils.rm_rf @tmp_dir if @tmp_dir
    end

    describe "delete_modified" do
      it "deletes all local modified files for a target" do
        rubys3_client, resp = setup_sync_test()
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
        rubys3_client, resp = setup_sync_test()
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
        LocalMode.delete_remote(rubys3_client, key)
      end
    end

    describe "sync_remote_to_local" do
      it "copies a remote file to local" do
        key = "DEFAULT/targets_modified/INST/procedures/mod.rb"
        full_path = "#{@tmp_dir}/#{key}"
        rubys3_client = double()
        expect(rubys3_client).to receive(:get_object).with({bucket: 'config', key: key, response_target: full_path })
        LocalMode.sync_remote_to_local(rubys3_client, key)
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
        LocalMode.sync_local_to_remote(rubys3_client, key)
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
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix, continuation_token: nil}).and_return(resp)
        catalog = LocalMode.build_remote_catalog(rubys3_client, scope: 'NONEXISTANT')
        expect(catalog.length).to be 0

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
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix, continuation_token: nil}).and_return(resp)
        catalog = LocalMode.build_remote_catalog(rubys3_client, scope: 'DEFAULT')
        expect(catalog.length).to be 6
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
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix, continuation_token: nil}).and_return(resp)
        catalog = LocalMode.build_remote_catalog(rubys3_client, scope: 'OTHER')
        expect(catalog.length).to be 3
        3.times do |index|
          expect(catalog["OTHER/targets_modified/INST/screens/myscreen#{index}.txt"]).to be (index * 10)
        end
      end
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
      return rubys3_client, resp
    end

    describe "sync_with_minio" do
      it "should sync local and remote targets_modified files with local primary" do
        ENV['OPENC3_LOCAL_MODE_SECONDARY'] = nil
        ENV['OPENC3_LOCAL_MODE_FORCE_SYNC'] = nil
        ENV['OPENC3_LOCAL_MODE_SYNC_REMOVE'] = nil
        rubys3_client, resp = setup_sync_test()

        prefix = 'DEFAULT/targets_modified'
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix, continuation_token: nil}).and_return(resp)

        expect(rubys3_client).to receive(:put_object).exactly(11).times
        6.times do |index|
          key = "DEFAULT/targets_modified/INST/screens/myscreen#{index}.txt"
          full_path = "#{@tmp_dir}/#{key}"
          expect(rubys3_client).to receive(:get_object).with({bucket: 'config', key: key, response_target: full_path })
        end
        LocalMode.sync_with_minio(rubys3_client, scope: 'DEFAULT')
      end

      it "should sync local and remote targets_modified files with local secondary" do
        ENV['OPENC3_LOCAL_MODE_SECONDARY'] = "1"
        ENV['OPENC3_LOCAL_MODE_FORCE_SYNC'] = nil
        ENV['OPENC3_LOCAL_MODE_SYNC_REMOVE'] = nil
        rubys3_client, resp = setup_sync_test()

        prefix = 'DEFAULT/targets_modified'
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix, continuation_token: nil}).and_return(resp)

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
        LocalMode.sync_with_minio(rubys3_client, scope: 'DEFAULT')
      end

      it "should sync local and remote targets_modified files with local primary and force" do
        ENV['OPENC3_LOCAL_MODE_SECONDARY'] = nil
        ENV['OPENC3_LOCAL_MODE_FORCE_SYNC'] = "1"
        ENV['OPENC3_LOCAL_MODE_SYNC_REMOVE'] = nil
        rubys3_client, resp = setup_sync_test()

        prefix = 'DEFAULT/targets_modified'
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix, continuation_token: nil}).and_return(resp)

        expect(rubys3_client).to receive(:put_object).exactly(14).times
        6.times do |index|
          key = "DEFAULT/targets_modified/INST/screens/myscreen#{index}.txt"
          full_path = "#{@tmp_dir}/#{key}"
          expect(rubys3_client).to receive(:get_object).with({bucket: 'config', key: key, response_target: full_path })
        end
        LocalMode.sync_with_minio(rubys3_client, scope: 'DEFAULT')
      end

      it "should sync local and remote targets_modified files with local secondary and force" do
        ENV['OPENC3_LOCAL_MODE_SECONDARY'] = "1"
        ENV['OPENC3_LOCAL_MODE_FORCE_SYNC'] = "1"
        ENV['OPENC3_LOCAL_MODE_SYNC_REMOVE'] = nil
        rubys3_client, resp = setup_sync_test()

        prefix = 'DEFAULT/targets_modified'
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix, continuation_token: nil}).and_return(resp)

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
        LocalMode.sync_with_minio(rubys3_client, scope: 'DEFAULT')
      end

      it "should sync local and remote targets_modified files with local primary and remove" do
        ENV['OPENC3_LOCAL_MODE_SECONDARY'] = nil
        ENV['OPENC3_LOCAL_MODE_FORCE_SYNC'] = nil
        ENV['OPENC3_LOCAL_MODE_SYNC_REMOVE'] = "1"
        rubys3_client, resp = setup_sync_test()

        prefix = 'DEFAULT/targets_modified'
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix, continuation_token: nil}).and_return(resp)

        expect(rubys3_client).to receive(:put_object).exactly(11).times
        6.times do |index|
          key = "DEFAULT/targets_modified/INST/screens/myscreen#{index}.txt"
          full_path = "#{@tmp_dir}/#{key}"
          expect(rubys3_client).to receive(:delete_object).with({bucket: 'config', key: key })
        end
        LocalMode.sync_with_minio(rubys3_client, scope: 'DEFAULT')
      end

      it "should sync local and remote targets_modified files with local secondary and remove" do
        ENV['OPENC3_LOCAL_MODE_SECONDARY'] = "1"
        ENV['OPENC3_LOCAL_MODE_FORCE_SYNC'] = nil
        ENV['OPENC3_LOCAL_MODE_SYNC_REMOVE'] = "1"
        rubys3_client, resp = setup_sync_test()

        prefix = 'DEFAULT/targets_modified'
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix, continuation_token: nil}).and_return(resp)

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
        LocalMode.sync_with_minio(rubys3_client, scope: 'DEFAULT')
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

        ENV['OPENC3_LOCAL_MODE'] = "1"
        ENV['OPENC3_LOCAL_MODE_SECONDARY'] = nil
        ENV['OPENC3_LOCAL_MODE_FORCE_SYNC'] = nil
        ENV['OPENC3_LOCAL_MODE_SYNC_REMOVE'] = nil
        rubys3_client, resp = setup_sync_test()
        expect(Aws::S3::Client).to receive(:new).and_return(rubys3_client)
        expect(rubys3_client).to receive(:head_bucket).with({bucket: 'config'}).and_raise(Aws::S3::Errors::NotFound.new(nil, "error"))
        expect(rubys3_client).to receive(:create_bucket).with({bucket: 'config'})

        prefix = 'DEFAULT/targets_modified'
        expect(rubys3_client).to receive(:list_objects_v2).with({bucket: 'config', max_keys: 1000, prefix: prefix, continuation_token: nil}).and_return(resp)

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
        rubys3_client, resp = setup_sync_test()
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
    end

    describe "open_local_file" do
      it "opens local files" do
        rubys3_client, resp = setup_sync_test()
        key = "ANOTHER/something/mod0.ext"
        file = LocalMode.open_local_file(key, scope: 'DEFAULT')
        expect(file).to_not be_nil
        file.close
        file = LocalMode.open_local_file("fake", scope: 'DEFAULT')
        expect(file).to be_nil
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
