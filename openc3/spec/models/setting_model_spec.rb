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
require 'openc3/models/setting_model'

module OpenC3
  describe SettingModel do
    before(:each) do
      mock_redis()
      # apply_defaults reports what it did on stdout; keep the spec output clean
      allow($stdout).to receive(:puts)
    end

    describe "self.get / self.set" do
      it "round trips a setting" do
        SettingModel.set({ name: 'time_zone', data: 'UTC' }, scope: nil)
        expect(SettingModel.get(name: 'time_zone')['data']).to eql 'UTC'
      end

      it "returns nil for a setting that doesn't exist" do
        expect(SettingModel.get(name: 'nope')).to be_nil
      end
    end

    describe "self.names / self.all" do
      it "lists the settings" do
        SettingModel.set({ name: 'time_zone', data: 'UTC' }, scope: nil)
        SettingModel.set({ name: 'time_format', data: '24hr' }, scope: nil)
        expect(SettingModel.names()).to contain_exactly('time_zone', 'time_format')
        expect(SettingModel.all().keys).to contain_exactly('time_zone', 'time_format')
      end
    end

    describe "as_json" do
      it "encodes name, data and updated_at" do
        model = SettingModel.new(name: 'time_zone', data: 'UTC')
        model.create
        json = model.as_json
        expect(json['name']).to eql 'time_zone'
        expect(json['data']).to eql 'UTC'
        expect(json['updated_at']).to_not be_nil
      end
    end

    describe "self.coerce" do
      it "parses JSON so booleans keep their type" do
        expect(SettingModel.coerce('true')).to be true
        expect(SettingModel.coerce('false')).to be false
      end

      it "parses JSON numbers, arrays and objects" do
        expect(SettingModel.coerce('5')).to eql 5
        expect(SettingModel.coerce('[1,2]')).to eql [1, 2]
        expect(SettingModel.coerce('{"a":1}')).to eql({ 'a' => 1 })
      end

      it "falls back to the raw string when the value isn't JSON" do
        expect(SettingModel.coerce('UTC')).to eql 'UTC'
        expect(SettingModel.coerce('24hr')).to eql '24hr'
        expect(SettingModel.coerce('')).to eql ''
      end

      it "keeps a quoted string a string" do
        expect(SettingModel.coerce('"true"')).to eql 'true'
      end

      it "passes through a value that isn't a String" do
        expect(SettingModel.coerce(true)).to be true
        expect(SettingModel.coerce(nil)).to be_nil
      end
    end

    describe "self.truthy_env?" do
      it "is false when the variable isn't set" do
        expect(SettingModel.truthy_env?({}, 'OPENC3_SETTINGS_OVERWRITE')).to be false
      end

      it "is true for 1 and true in any case" do
        ['1', 'true', 'TRUE', 'True', ' true '].each do |value|
          expect(SettingModel.truthy_env?({ 'VAR' => value }, 'VAR')).to be true
        end
      end

      it "is false for 0, false and empty in any case" do
        # Unlike the OPENC3_NO_* flags, '0' means off rather than on
        ['0', 'false', 'FALSE', '', '  '].each do |value|
          expect(SettingModel.truthy_env?({ 'VAR' => value }, 'VAR')).to be false
        end
      end

      it "raises on a value that is neither, naming the variable" do
        expect { SettingModel.truthy_env?({ 'OPENC3_SETTINGS_OVERWRITE' => 'yes' }, 'OPENC3_SETTINGS_OVERWRITE') }
          .to raise_error(ArgumentError, /Invalid value "yes" for OPENC3_SETTINGS_OVERWRITE/)
      end

      it "handles a non-String value" do
        expect(SettingModel.truthy_env?({ 'VAR' => 1 }, 'VAR')).to be true
      end
    end

    describe "self.to_str" do
      it "returns nil for nil and a String otherwise" do
        expect(SettingModel.to_str(nil)).to be_nil
        expect(SettingModel.to_str(:sym)).to eql 'sym'
        expect(SettingModel.to_str('str')).to eql 'str'
      end
    end

    describe "self.near_match?" do
      it "matches a single substituted character" do
        expect(SettingModel.near_match?('time_zone', 'time_zome')).to be true
      end

      it "matches a single inserted or deleted character" do
        expect(SettingModel.near_match?('time_zone', 'time_zones')).to be true
        expect(SettingModel.near_match?('time_zone', 'time_zon')).to be true
      end

      it "matches an identical name" do
        expect(SettingModel.near_match?('time_zone', 'time_zone')).to be true
      end

      it "doesn't match when more than one character differs" do
        expect(SettingModel.near_match?('time_zone', 'timezones')).to be false
        expect(SettingModel.near_match?('time_zone', 'ai_chat')).to be false
      end

      it "doesn't match when the length differs by more than one" do
        expect(SettingModel.near_match?('time_zone', 'time')).to be false
      end
    end

    describe "self.parse_defaults_env" do
      it "returns an empty hash when nothing is set" do
        expect(SettingModel.parse_defaults_env({})).to eql({})
      end

      it "reads OPENC3_SETTING_* and downcases the name" do
        env = { 'OPENC3_SETTING_TIME_ZONE' => 'UTC' }
        expect(SettingModel.parse_defaults_env(env)).to eql({ 'time_zone' => 'UTC' })
      end

      it "coerces OPENC3_SETTING_* values" do
        env = { 'OPENC3_SETTING_AI_CHAT' => 'false' }
        expect(SettingModel.parse_defaults_env(env)).to eql({ 'ai_chat' => false })
      end

      it "ignores unrelated env vars and a bare prefix" do
        env = { 'PATH' => '/usr/bin', 'OPENC3_SETTING_' => 'UTC' }
        expect(SettingModel.parse_defaults_env(env)).to eql({})
      end

      it "doesn't mistake the control variables for settings" do
        # OPENC3_SETTINGS_* must not be caught by the OPENC3_SETTING_ scan
        env = {
          SettingModel::OVERWRITE_ENV_VAR => '1',
          SettingModel::ALLOW_UNKNOWN_ENV_VAR => '1',
        }
        expect(SettingModel.parse_defaults_env(env)).to eql({})
      end

      it "handles non-String keys and values" do
        env = { :OPENC3_SETTING_TIME_ZONE => :UTC }
        expect(SettingModel.parse_defaults_env(env)).to eql({ 'time_zone' => 'UTC' })
      end
    end

    describe "self.validate_setting!" do
      it "accepts a known name with an allowed value" do
        expect { SettingModel.validate_setting!('time_zone', 'UTC') }.to_not raise_error
        expect { SettingModel.validate_setting!('time_format', '24hr') }.to_not raise_error
        expect { SettingModel.validate_setting!('ai_chat', false) }.to_not raise_error
        expect { SettingModel.validate_setting!('news_feed', true) }.to_not raise_error
      end

      it "rejects a value outside the allowed list" do
        expect { SettingModel.validate_setting!('time_zone', 'Mars') }
          .to raise_error(/Invalid value "Mars" for setting 'time_zone'.*local.*UTC/)
      end

      it "rejects the string 'false' for a boolean setting" do
        # "false" is truthy in the frontend, so it must not be accepted
        expect { SettingModel.validate_setting!('ai_chat', 'false') }
          .to raise_error(/Invalid value "false" for setting 'ai_chat'/)
      end

      it "rejects a name with invalid characters" do
        expect { SettingModel.validate_setting!('Time Zone', 'UTC') }
          .to raise_error(/Invalid setting name/)
        expect { SettingModel.validate_setting!('', 'UTC') }
          .to raise_error(/Invalid setting name/)
      end

      it "rejects an unknown name by default" do
        expect { SettingModel.validate_setting!('whatever', 'x') }
          .to raise_error(/'whatever' is not a known COSMOS setting.*OPENC3_SETTINGS_ALLOW_UNKNOWN/m)
      end

      it "suggests the intended name on a near miss" do
        expect { SettingModel.validate_setting!('time_zones', 'UTC') }
          .to raise_error(/Did you mean 'time_zone'\?/)
      end

      it "accepts an unknown name when allow_unknown is set" do
        expect { SettingModel.validate_setting!('whatever', 'x', allow_unknown: true) }.to_not raise_error
      end

      it "rejects a value over the size limit" do
        expect { SettingModel.validate_setting!('big', 'x' * (SettingModel::MAX_VALUE_BYTES + 1), allow_unknown: true) }
          .to raise_error(/exceeds the #{SettingModel::MAX_VALUE_BYTES} byte limit/)
      end

      it "measures a non-String value as its JSON encoding" do
        expect { SettingModel.validate_setting!('big', ['x' * SettingModel::MAX_VALUE_BYTES], allow_unknown: true) }
          .to raise_error(/exceeds the #{SettingModel::MAX_VALUE_BYTES} byte limit/)
        expect { SettingModel.validate_setting!('small', { 'a' => 1 }, allow_unknown: true) }.to_not raise_error
      end
    end

    describe "self.apply_defaults" do
      it "does nothing when no env vars are set" do
        expect(SettingModel.apply_defaults(env: {})).to eql []
        expect(SettingModel.names()).to be_empty
      end

      it "writes settings from OPENC3_SETTING_* variables" do
        env = { 'OPENC3_SETTING_TIME_ZONE' => 'UTC', 'OPENC3_SETTING_TIME_FORMAT' => '24hr' }
        expect(SettingModel.apply_defaults(env: env)).to contain_exactly('time_zone', 'time_format')
        expect(SettingModel.get(name: 'time_zone')['data']).to eql 'UTC'
        expect(SettingModel.get(name: 'time_format')['data']).to eql '24hr'
      end

      it "stores a boolean as a boolean" do
        env = { 'OPENC3_SETTING_AI_CHAT' => 'false' }
        SettingModel.apply_defaults(env: env)
        expect(SettingModel.get(name: 'ai_chat')['data']).to be false
      end

      it "leaves an existing setting unchanged" do
        SettingModel.set({ name: 'time_zone', data: 'local' }, scope: nil)
        env = { 'OPENC3_SETTING_TIME_ZONE' => 'UTC' }
        expect(SettingModel.apply_defaults(env: env)).to eql []
        expect(SettingModel.get(name: 'time_zone')['data']).to eql 'local'
      end

      it "overwrites an existing setting when the env var is set" do
        SettingModel.set({ name: 'time_zone', data: 'local' }, scope: nil)
        env = {
          'OPENC3_SETTING_TIME_ZONE' => 'UTC',
          'OPENC3_SETTINGS_OVERWRITE' => '1',
        }
        expect(SettingModel.apply_defaults(env: env)).to eql ['time_zone']
        expect(SettingModel.get(name: 'time_zone')['data']).to eql 'UTC'
      end

      it "treats an empty or explicitly false overwrite env var as off" do
        ['', '0', 'false'].each do |value|
          SettingModel.set({ name: 'time_zone', data: 'local' }, scope: nil)
          env = {
            'OPENC3_SETTING_TIME_ZONE' => 'UTC',
            'OPENC3_SETTINGS_OVERWRITE' => value,
          }
          expect(SettingModel.apply_defaults(env: env)).to eql []
          expect(SettingModel.get(name: 'time_zone')['data']).to eql 'local'
        end
      end

      it "raises on an unparseable overwrite env var rather than guessing" do
        env = {
          'OPENC3_SETTING_TIME_ZONE' => 'UTC',
          'OPENC3_SETTINGS_OVERWRITE' => 'maybe',
        }
        expect { SettingModel.apply_defaults(env: env) }
          .to raise_error(ArgumentError, /Invalid value "maybe" for OPENC3_SETTINGS_OVERWRITE/)
        expect(SettingModel.get(name: 'time_zone')).to be_nil
      end

      it "raises on an unparseable allow unknown env var" do
        env = {
          'OPENC3_SETTING_TIME_ZONE' => 'UTC',
          'OPENC3_SETTINGS_ALLOW_UNKNOWN' => 'maybe',
        }
        expect { SettingModel.apply_defaults(env: env) }
          .to raise_error(ArgumentError, /Invalid value "maybe" for OPENC3_SETTINGS_ALLOW_UNKNOWN/)
      end

      it "honors an explicit overwrite argument over the env var" do
        SettingModel.set({ name: 'time_zone', data: 'local' }, scope: nil)
        env = { 'OPENC3_SETTING_TIME_ZONE' => 'UTC' }
        expect(SettingModel.apply_defaults(env: env, overwrite: true)).to eql ['time_zone']
        expect(SettingModel.get(name: 'time_zone')['data']).to eql 'UTC'
      end

      it "applies an unknown setting when ALLOW_UNKNOWN is set" do
        env = {
          'OPENC3_SETTING_BRAND_NEW' => 'x',
          'OPENC3_SETTINGS_ALLOW_UNKNOWN' => 'true',
        }
        expect(SettingModel.apply_defaults(env: env)).to eql ['brand_new']
        expect(SettingModel.get(name: 'brand_new')['data']).to eql 'x'
      end

      it "raises and writes nothing further on an invalid value" do
        env = { 'OPENC3_SETTING_TIME_ZONE' => 'Mars' }
        expect { SettingModel.apply_defaults(env: env) }.to raise_error(/Invalid value/)
        expect(SettingModel.get(name: 'time_zone')).to be_nil
      end

      it "reads from ENV by default" do
        expect(SettingModel).to receive(:parse_defaults_env).with(ENV).and_return({})
        SettingModel.apply_defaults()
      end
    end
  end
end
