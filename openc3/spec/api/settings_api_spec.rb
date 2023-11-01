# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/api/settings_api'

module OpenC3
  describe Api do
    class ApiTest
      include Extract
      include Api
      include Authorization
    end

    before(:each) do
      mock_redis()
      @api = ApiTest.new
      ENV['OPENC3_LOCAL_MODE'] = "1"
      @tmp_dir = Dir.mktmpdir
      saved_verbose = $VERBOSE; $VERBOSE = nil
      LocalMode.const_set(:OPENC3_LOCAL_MODE_PATH, @tmp_dir)
      $VERBOSE = saved_verbose
    end

    describe "set_setting" do
      it "sets a value in the stash" do
        @api.set_setting('key', 'val')
        expect(@api.get_setting('key')).to eql 'val'
      end

      it "sets an array in the stash" do
        data = [1,2,[3,4]]
        @api.set_setting('key', data)
        expect(@api.get_setting('key')).to eql data
      end

      it "sets a hash in the stash" do
        data = { key: 'val', more: 1 }
        @api.set_setting('key', data)
        expect(@api.get_setting('key')).to eql({ 'key' => 'val', 'more' => 1 })
      end
    end

    describe "get_setting" do
      it "returns nil if the value doesn't exist" do
        expect(@api.get_setting('nope')).to be_nil
      end
    end

    describe "list_settings" do
      it "returns empty array with no keys" do
        expect(@api.list_settings()).to eql([])
      end

      it "returns all the setting keys as an array" do
        @api.set_setting('key1', 'val')
        @api.set_setting('key2', 'val')
        @api.set_setting('key3', 'val')
        expect(@api.list_settings()).to eql %w(key1 key2 key3)
      end
    end

    describe "get_all_settings" do
      it "returns empty hash with no keys" do
        expect(@api.get_all_settings()).to eql({})
      end

      it "returns all setting values as a hash" do
        @api.set_setting('key1', 1)
        @api.set_setting('key2', 2)
        @api.set_setting('key3', 3)
        result = { 'key1' => 1, 'key2' => 2, 'key3' => 3 }
        expect(@api.get_all_settings().keys).to eql result.keys
        expect(@api.get_all_settings()['key1']['name']).to eql 'key1'
        expect(@api.get_all_settings()['key1']['data']).to eql 1
        expect(@api.get_all_settings()['key2']['name']).to eql 'key2'
        expect(@api.get_all_settings()['key2']['data']).to eql 2
        expect(@api.get_all_settings()['key3']['name']).to eql 'key3'
        expect(@api.get_all_settings()['key3']['data']).to eql 3
      end
    end

    describe "get_settings" do
      it "returns empty array with no keys" do
        expect(@api.get_settings()).to eql([])
      end

      it "returns specified settings as an array of results" do
        @api.set_setting('key1', 'string')
        @api.set_setting('key2', 2)
        @api.set_setting('key3', 3)
        expect(@api.get_settings('key1','key3')).to eql ["string", 3]
      end
    end
  end
end
