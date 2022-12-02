# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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
require 'openc3/api/stash_api'

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
    end

    describe "stash_set" do
      it "sets a value in the stash" do
        @api.stash_set('key', 'val')
        expect(@api.stash_get('key')).to eql 'val'
        # Override with binary data
        @api.stash_set('key', "\xDE\xAD\xBE\xEF")
        expect(@api.stash_get('key')).to eql "\xDE\xAD\xBE\xEF"
      end

      it "sets an array in the stash" do
        data = [1,2,[3,4]]
        @api.stash_set('key', data)
        expect(@api.stash_get('key')).to eql data
      end

      it "sets a hash in the stash" do
        data = { key: 'val', more: 1 }
        @api.stash_set('key', data)
        expect(@api.stash_get('key')).to eql({ 'key' => 'val', 'more' => 1 })
      end
    end

    describe "stash_get" do
      it "returns nil if the value doesn't exist" do
        expect(@api.stash_get('nope')).to be_nil
      end
    end

    describe "stash_delete" do
      it "deletes an existing key" do
        @api.stash_set('key', 'val')
        @api.stash_delete('key')
        expect(@api.stash_get('key')).to be_nil
      end

      it "ignores keys that do not exist" do
        @api.stash_delete('nope')
      end
    end

    describe "stash_keys" do
      it "returns empty array with no keys" do
        expect(@api.stash_keys()).to eql([])
      end

      it "returns all the stash keys as an array" do
        @api.stash_set('key1', 'val')
        @api.stash_set('key2', 'val')
        @api.stash_set('key3', 'val')
        expect(@api.stash_keys()).to eql %w(key1 key2 key3)
      end
    end

    describe "stash_all" do
      it "returns empty hash with no keys" do
        expect(@api.stash_all()).to eql({})
      end

      it "returns all stash values as a hash" do
        @api.stash_set('key1', 1)
        @api.stash_set('key2', 2)
        @api.stash_set('key3', 3)
        result = { 'key1' => 1, 'key2' => 2, 'key3' => 3 }
        expect(@api.stash_all()).to eql result
      end
    end
  end
end
