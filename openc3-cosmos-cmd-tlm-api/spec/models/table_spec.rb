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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'rails_helper'
require 'openc3/utilities/aws_bucket'

RSpec.describe Table, :type => :model do
  before(:each) do
    ENV.delete('OPENC3_LOCAL_MODE')
    @targets = OpenStruct.new
    @targets.contents = []
    @targets_modified = OpenStruct.new
    @targets_modified.contents = []
    @get_object = OpenStruct.new
    @put_object = {}
    @s3 = double("AwsS3Client").as_null_object
    allow(Aws::S3::Client).to receive(:new).and_return(@s3)
    allow(@s3).to receive(:list_objects_v2) do |args|
      if args[:prefix].include?("targets_modified")
        @targets_modified
      else
        @targets
      end
    end
    @s3_miss = false
    @count = 0
    allow(@s3).to receive(:get_object) do |args|
      if args[:key].include?('nope')
        raise Aws::S3::Errors::NoSuchKey.new('context','message')
      else
        if @s3_miss and @count < @s3_miss and args[:key].include?('config')
          @count += 1
          nil
        else
          @get_object
        end
      end
    end
    allow(@s3).to receive(:put_object) do |args|
      @put_object[args[:key]] = args[:body]
    end
  end

  def add_table(table_name)
    key_struct = OpenStruct.new
    key_struct.key = table_name
    if table_name.include?("targets_modified")
      @targets_modified.contents << key_struct
    else
      @targets.contents << key_struct
    end
  end

  describe "all" do
    it "successfully returns an empty array" do
      all = Table.all('DEFAULT')
      expect(all).to eql []
    end

    it "returns all the tables in the scope" do
      # Scopes are differentiated in the S3 query now, so can't mix in the @resp
      add_table('DEFAULT/targets/INST/tables/bin/TEST1.bin')
      all = Table.all('DEFAULT')
      expect(all).to eql ['INST/tables/bin/TEST1.bin']
    end

    it "de-duplicates modified tables and marks modified with *" do
      add_table('DEFAULT/targets/INST/tables/bin/TEST1.bin')
      add_table('DEFAULT/targets_modified/INST/tables/bin/TEST1.bin')
      add_table('DEFAULT/targets_modified/INST/tables/bin/TEST2.bin')
      all = Table.all('DEFAULT')
      # Note no modified on a modified that doesn't have original
      expect(all).to eql ['INST/tables/bin/TEST1.bin*', 'INST/tables/bin/TEST2.bin']
    end

    it "sorts the output" do
      add_table('DEFAULT/targets/INST/tables/bin/delta.bin')
      add_table('DEFAULT/targets/INST/tables/bin/alfa.bin')
      add_table('DEFAULT/targets/INST/tables/bin/charlie.bin')
      add_table('DEFAULT/targets/INST/tables/bin/bravo.bin')
      all = Table.all('DEFAULT')
      expect(all).to eql ['INST/tables/bin/alfa.bin', 'INST/tables/bin/bravo.bin',
        'INST/tables/bin/charlie.bin', 'INST/tables/bin/delta.bin']
    end
  end

  describe "binary" do
    it "returns the binary file" do
      # Simulate what S3 get_object returns
      @get_object.body = OpenStruct.new
      @get_object.body.read = 'the file'
      file = Table.binary('DEFAULT', 'INST/tables/bin/table.bin', 'INST/tables/bin/table_def.txt')
      expect(file.filename).to eql 'table.bin'
      expect(file.contents).to eql 'the file'
    end

    it "returns all table definition files if parsing a table" do
      # Simulate what S3 get_object returns
      @get_object.body = OpenStruct.new
      # Create an additional TABLEFILE that we have to retrieve
      @get_object.body.read = 'TABLEFILE "tablefile.txt"'
      allow(OpenC3::TableManagerCore).to receive(:binary).and_return('data')
      tmp_dir = File.join(SPEC_DIR, 'tmp1')
      Dir.mkdir(tmp_dir) unless File.exist?(tmp_dir)
      allow(Dir).to receive(:mktmpdir).and_return(tmp_dir)
      file = Table.binary('DEFAULT', 'INST/tables/bin/table.bin', 'INST/tables/config/table_def.txt', 'MY_TABLE')
      expect(file.filename).to eql 'MyTable.bin'
      expect(file.contents).to eql 'data' # Check the simple stub
      # Real test is did we create the definition files
      files = Dir.glob("#{tmp_dir}/**/*").map {|file| File.basename(file) }
      expect(files).to include('table_def.txt')
      expect(files).to include('tablefile.txt')
      FileUtils.rm_rf(tmp_dir)
    end

    it "raises an exception of table definition file can't be found" do
      @get_object.body = OpenStruct.new
      # Simulate a TABLEFILE that won't exist 'nope'
      @get_object.body.read = 'TABLEFILE "nope.txt"'
      allow(OpenC3::TableManagerCore).to receive(:binary).and_return('data')
      tmp_dir = File.join(SPEC_DIR, 'tmp2')
      Dir.mkdir(tmp_dir) unless File.exist?(tmp_dir)
      allow(Dir).to receive(:mktmpdir).and_return(tmp_dir)
      expect { Table.binary('DEFAULT', 'INST/tables/bin/table.bin', 'INST/tables/config/table_def.txt', 'MY_TABLE') }.to \
        raise_error("Could not find file INST/tables/config/nope.txt")
      # Real test is did we create the definition files
      files = Dir.glob("#{tmp_dir}/**/*").map {|file| File.basename(file) }
      expect(files).to include('table_def.txt')
      expect(files).not_to include('nope.txt')
      FileUtils.rm_rf(tmp_dir)
    end
  end

  describe "definition" do
    it "returns the definition file" do
      # Simulate what S3 get_object returns
      @get_object.body = OpenStruct.new
      @get_object.body.read = 'the file'
      file = Table.definition('DEFAULT', 'INST/tables/config/table_def.txt')
      expect(file.filename).to eql 'table_def.txt'
      expect(file.contents).to eql 'the file'
    end

    it "calls table manager to parse a definition" do
      # Simulate what S3 get_object returns
      @get_object.body = OpenStruct.new
      # Create an additional TABLEFILE that we have to retrieve
      @get_object.body.read = 'TABLEFILE "tablefile.txt"'
      allow(OpenC3::TableManagerCore).to receive(:definition).and_return(['tablefile.txt', 'data'])
      tmp_dir = File.join(SPEC_DIR, 'tmp3')
      Dir.mkdir(tmp_dir) unless File.exist?(tmp_dir)
      allow(Dir).to receive(:mktmpdir).and_return(tmp_dir)
      file = Table.definition('DEFAULT', 'INST/tables/config/table_def.txt', 'MY_TABLE')
      expect(file.filename).to eql 'tablefile.txt' # Ensure we get the right name
      expect(file.contents).to eql 'data' # Check the simple stub
      # Real test is did we create the definition files
      files = Dir.glob("#{tmp_dir}/**/*").map {|file| File.basename(file) }
      expect(files).to include('table_def.txt')
      expect(files).to include('tablefile.txt')
      FileUtils.rm_rf(tmp_dir)
    end
  end

  describe "report" do
    it "creates and returns the report" do
      # Simulate what S3 get_object returns
      @get_object.body = OpenStruct.new
      @get_object.body.read = 'definition'
      allow(OpenC3::TableManagerCore).to receive(:report).and_return('report')
      file = Table.report('DEFAULT', 'INST/tables/bin/table.bin', 'INST/tables/config/table_def.txt')
      expect(file.filename).to eql 'INST/tables/bin/table.csv'
      expect(file.contents).to eql 'report'
      expect(@put_object['DEFAULT/targets_modified/INST/tables/bin/table.csv']).to eql "report"
    end

    it "calls table manager to parse a definition" do
      # Simulate what S3 get_object returns
      @get_object.body = OpenStruct.new
      # Create an additional TABLEFILE that we have to retrieve
      @get_object.body.read = 'TABLEFILE "tablefile.txt"'
      allow(OpenC3::TableManagerCore).to receive(:report).and_return('report')
      tmp_dir = File.join(SPEC_DIR, 'tmp4')
      Dir.mkdir(tmp_dir) unless File.exist?(tmp_dir)
      allow(Dir).to receive(:mktmpdir).and_return(tmp_dir)
      file = Table.report('DEFAULT', 'INST/tables/bin/table.bin', 'INST/tables/config/table_def.txt', 'MY_TABLE')
      expect(file.filename).to eql 'INST/tables/bin/MyTable.csv'
      expect(file.contents).to eql 'report' # Check the simple stub
      expect(@put_object['DEFAULT/targets_modified/INST/tables/bin/MyTable.csv']).to eql "report"
      # Real test is did we create the definition files
      files = Dir.glob("#{tmp_dir}/**/*").map {|file| File.basename(file) }
      expect(files).to include('table_def.txt')
      expect(files).to include('tablefile.txt')
      FileUtils.rm_rf(tmp_dir)
    end
  end

  describe "save" do
    it "saves the tables to file" do
      # Simulate what S3 get_object returns
      @get_object.body = OpenStruct.new
      @get_object.body.read = 'definition'
      allow(OpenC3::TableManagerCore).to receive(:save).and_return("\x01\x02\x03\x04")
      Table.save('DEFAULT', 'INST/tables/bin/table.bin', 'INST/tables/config/table_def.txt', '{}')
      expect(@put_object['DEFAULT/targets_modified/INST/tables/bin/table.bin']).to eql "\x01\x02\x03\x04"
    end
  end

  describe "save_as" do
    it "renames an existing file" do
      # Simulate what S3 get_object returns
      @get_object.body = OpenStruct.new
      @get_object.body.read = 'data'
      Table.save_as('DEFAULT', 'INST/tables/bin/table.bin', 'INST/tables/bin/table2.bin')
      expect(@put_object['DEFAULT/targets_modified/INST/tables/bin/table2.bin']).to eql "data"
    end
  end

  describe "lock" do
    before(:each) do
      mock_redis()
    end

    it "locks a table to a user" do
      user = Table.locked?('DEFAULT', 'INST/tables/bin/table.bin')
      expect(user).to be false

      # Test with modified '*'
      Table.lock('DEFAULT', 'INST/tables/bin/table.bin*', 'jmthomas')
      user = Table.locked?('DEFAULT', 'INST/tables/bin/table.bin')
      expect(user).to eql 'jmthomas'
      user = Table.locked?('DEFAULT', 'INST/tables/bin/table.bin*')
      expect(user).to eql 'jmthomas'

      # No modified '*'
      Table.lock('DEFAULT', 'INST/tables/bin/table2.bin', 'jmthomas')
      user = Table.locked?('DEFAULT', 'INST/tables/bin/table2.bin')
      expect(user).to eql 'jmthomas'
      user = Table.locked?('DEFAULT', 'INST/tables/bin/table2.bin*')
      expect(user).to eql 'jmthomas'
    end
  end

  describe "unlock" do
    before(:each) do
      mock_redis()
    end

    it "unlocks a table" do
      # Test with modified '*'
      Table.lock('DEFAULT', 'INST/tables/bin/table.bin*', 'jmthomas')
      Table.unlock('DEFAULT', 'INST/tables/bin/table.bin*')
      user = Table.locked?('DEFAULT', 'INST/tables/bin/table.bin')
      expect(user).to be false

      Table.lock('DEFAULT', 'INST/tables/bin/table.bin*', 'jmthomas')
      Table.unlock('DEFAULT', 'INST/tables/bin/table.bin')
      user = Table.locked?('DEFAULT', 'INST/tables/bin/table.bin')
      expect(user).to be false

      # No modified '*'
      Table.lock('DEFAULT', 'INST/tables/bin/table2.bin', 'jmthomas')
      Table.unlock('DEFAULT', 'INST/tables/bin/table2.bin*')
      user = Table.locked?('DEFAULT', 'INST/tables/bin/table2.bin')
      expect(user).to be false

      Table.lock('DEFAULT', 'INST/tables/bin/table2.bin', 'jmthomas')
      Table.unlock('DEFAULT', 'INST/tables/bin/table2.bin')
      user = Table.locked?('DEFAULT', 'INST/tables/bin/table2.bin')
      expect(user).to be false
    end
  end

  describe "generate" do
    it "generate a binary based on definitions" do
      # Simulate what S3 get_object returns
      @get_object.body = OpenStruct.new
      @get_object.body.read = 'definition'
      allow(OpenC3::TableManagerCore).to receive(:generate).and_return("\x01\x02\x03\x04")
      filename = Table.generate('DEFAULT', 'INST/tables/config/table_def.txt')
      expect(filename).to eql 'INST/tables/bin/table.bin'
      expect(@put_object['DEFAULT/targets_modified/INST/tables/bin/table.bin']).to eql "\x01\x02\x03\x04"
    end
  end

  describe "load" do
    it "generates json for the frontend" do
      # Simulate what S3 get_object returns
      @get_object.body = OpenStruct.new
      @get_object.body.read = 'definition'
      allow(OpenC3::TableManagerCore).to receive(:build_json_hash).and_return({'tables' => []})
      json = Table.load('DEFAULT', 'INST/tables/bin/table.bin', 'INST/tables/config/table_def.txt')
      expect(json).to eql "{\"tables\":[],\"definition\":\"INST/tables/config/table_def.txt\"}"
    end

    it "searches for a close match if definition not found" do
      # Add some configs that don't match
      add_table('DEFAULT/targets/INST/tables/bin/Other.bin')
      add_table('DEFAULT/targets/INST/tables/config/DataTable_def.txt')
      add_table('DEFAULT/targets/INST/tables/config/OtherConfigTable_def.txt')
      add_table('DEFAULT/targets/INST/tables/config/ConfigurationTable_def.txt')
      add_table('DEFAULT/targets/INST/tables/config/ConfigTableNew_def.txt')
      # Add a config which does
      add_table('DEFAULT/targets/INST/tables/config/ConfigTable_def.txt')
      @s3_miss = 2 # Cause S3 to miss the original and modified versions of the ConfigTable_def.txt
      @get_object.body = OpenStruct.new
      @get_object.body.read = 'definition'
      allow(OpenC3::TableManagerCore).to receive(:build_json_hash).and_return({'tables' => []})
      json = Table.load('DEFAULT', 'INST/tables/bin/ConfigTable2.bin', 'INST/tables/config/ConfigTable_def.txt')
      expect(json).to eql "{\"tables\":[],\"definition\":\"INST/tables/config/ConfigTable_def.txt\"}"
    end

    it "raises if definition not found" do
      # Add some configs that don't match
      add_table('DEFAULT/targets/INST/tables/bin/Other.bin')
      add_table('DEFAULT/targets/INST/tables/config/DataTable_def.txt')
      add_table('DEFAULT/targets/INST/tables/config/OtherConfigTable_def.txt')
      add_table('DEFAULT/targets/INST/tables/config/ConfigurationTable_def.txt')
      add_table('DEFAULT/targets/INST/tables/config/ConfigTableNew_def.txt')
      @s3_miss = 2 # Cause S3 to miss the original and modified versions of the ConfigTable_def.txt
      @get_object.body = OpenStruct.new
      @get_object.body.read = 'definition'
      # Now we're searching for something that matches and can't find it
      expect { Table.load('DEFAULT', 'INST/tables/bin/ConfigTable2.bin', 'INST/tables/config/ConfigTable_def.txt') }.to raise_error(Table::NotFound, "Definition file 'INST/tables/config/ConfigTable_def.txt' not found")
    end
  end

  describe "get_definitions" do
    it "looks up a definition file based on a binary filename" do
      add_table('DEFAULT/targets/INST/tables/config/table_data.txt')
      add_table('DEFAULT/targets/INST/tables/config/table_binary.txt')
      add_table('DEFAULT/targets/INST/tables/config/table_data_2.txt')
      @s3_miss = 2 # Cause S3 to miss the original and modified versions
      @get_object.body = OpenStruct.new
      @get_object.body.read = 'definition'
      root_definition, definition_filename = Table.get_definitions('DEFAULT', 'INST/tables/config/table_data.txt', 'INST/tables/bin/table_data.bin')
      expect(definition_filename).to eql 'INST/tables/config/table_data.txt'
      @count = 0
      root_definition, definition_filename = Table.get_definitions('DEFAULT', 'INST/tables/config/table_data.txt', 'INST/tables/bin/table_data_2.bin')
      expect(definition_filename).to eql 'INST/tables/config/table_data_2.txt'
      @count = 0
      root_definition, definition_filename = Table.get_definitions('DEFAULT', 'INST/tables/config/table_data.txt', 'INST/tables/bin/table_binary.bin')
      expect(definition_filename).to eql 'INST/tables/config/table_binary.txt'
      @count = 0
      root_definition, definition_filename = Table.get_definitions('DEFAULT', 'INST/tables/config/table_data.txt', 'INST/tables/bin/table_binary_additional.bin')
      expect(definition_filename).to eql 'INST/tables/config/table_binary.txt'
    end

    it "looks up a definition file with _def based on a binary filename" do
      add_table('DEFAULT/targets/INST/tables/config/table_data_def.txt')
      add_table('DEFAULT/targets/INST/tables/config/table_binary_def.txt')
      add_table('DEFAULT/targets/INST/tables/config/table_data_2_def.txt')
      @s3_miss = 2 # Cause S3 to miss the original and modified versions
      @get_object.body = OpenStruct.new
      @get_object.body.read = 'definition'
      root_definition, definition_filename = Table.get_definitions('DEFAULT', 'INST/tables/config/table_data.txt', 'INST/tables/bin/table_data.tbl')
      expect(definition_filename).to eql 'INST/tables/config/table_data_def.txt'
      @count = 0
      root_definition, definition_filename = Table.get_definitions('DEFAULT', 'INST/tables/config/table_data.txt', 'INST/tables/bin/table_data_2.tbl')
      expect(definition_filename).to eql 'INST/tables/config/table_data_2_def.txt'
      @count = 0
      root_definition, definition_filename = Table.get_definitions('DEFAULT', 'INST/tables/config/table_data.txt', 'INST/tables/bin/table_binary.tbl')
      expect(definition_filename).to eql 'INST/tables/config/table_binary_def.txt'
      @count = 0
      root_definition, definition_filename = Table.get_definitions('DEFAULT', 'INST/tables/config/table_data.txt', 'INST/tables/bin/table_binary_additional.tbl')
      expect(definition_filename).to eql 'INST/tables/config/table_binary_def.txt'
    end
  end
end
