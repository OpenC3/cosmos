# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/api/settings_api'
require 'openc3/script/extract'
require 'openc3/utilities/authorization'

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

    describe "update_news" do
      it "raises AuthError without writing the news feed" do
        NewsModel.set('[]')
        saved = $openc3_authorize
        $openc3_authorize = true
        begin
          expect { @api.update_news(scope: 'DEFAULT', token: nil) }.to raise_error(AuthError, /Token is required/)
        ensure
          $openc3_authorize = saved
        end
        expect(NewsModel.all()).to eql '[]'
      end

      it "writes a news error if the feed can't be reached" do
        allow_any_instance_of(Faraday::Connection).to receive(:get).and_raise(Faraday::ConnectionFailed.new('no route'))
        @api.update_news(scope: 'DEFAULT')
        news = JSON.parse(NewsModel.all())
        expect(news[0]['title']).to eql 'News Error'
        expect(news[0]['body']).to include 'no route'
      end
    end
  end
end
