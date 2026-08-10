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
      it "converts a boolean setting to a real boolean" do
        expect(SettingModel.coerce('ai_chat', 'true')).to be true
        expect(SettingModel.coerce('ai_chat', 'false')).to be false
        expect(SettingModel.coerce('news_feed', '1')).to be true
        expect(SettingModel.coerce('script_runner_locking', '0')).to be false
      end

      it "raises on a boolean setting that isn't a boolean" do
        expect { SettingModel.coerce('ai_chat', 'nope') }
          .to raise_error(ArgumentError, /Invalid value "nope" for setting 'ai_chat'/)
      end

      it "leaves a string setting as the text given" do
        expect(SettingModel.coerce('time_zone', 'UTC')).to eql 'UTC'
        expect(SettingModel.coerce('time_format', '24hr')).to eql '24hr'
        expect(SettingModel.coerce('subtitle', '')).to eql ''
      end

      it "doesn't turn a numeric looking string into a number" do
        # A subtitle of "2024" is a subtitle, not the number 2024
        expect(SettingModel.coerce('subtitle', '2024')).to eql '2024'
      end

      it "keeps a JSON text setting as text" do
        # These components JSON.parse the value, so a parsed Hash would throw
        json = '{"text":"UNCLASSIFIED"}'
        expect(SettingModel.coerce('classification_banner', json)).to eql json
        expect(SettingModel.coerce('astro', '{"hideClock":true}')).to eql '{"hideClock":true}'
        expect(SettingModel.coerce('context_tag', '{"text":"DEV"}')).to eql '{"text":"DEV"}'
      end

      it "leaves an unknown setting as the text given" do
        expect(SettingModel.coerce('brand_new', 'true')).to eql 'true'
      end

      it "passes through a value that isn't a String" do
        expect(SettingModel.coerce('ai_chat', true)).to be true
        expect(SettingModel.coerce('ai_chat', nil)).to be_nil
      end
    end

    describe "self.describe_settings" do
      it "lists every setting with its allowed values" do
        lines = SettingModel.describe_settings
        expect(lines.length).to eql SettingModel::KNOWN_SETTINGS.length
        expect(lines).to include('time_zone: local, UTC')
        expect(lines).to include('ai_chat: 1, true, 0, false')
        expect(lines).to include('subtitle: any text')
      end
    end

    describe "KNOWN_SETTINGS" do
      it "declares a valid type for every setting" do
        SettingModel::KNOWN_SETTINGS.each do |name, details|
          expect([:string, :boolean]).to include(details[:type]), "#{name} has an invalid type"
          expect(name).to match(/\A[a-z0-9_]+\z/)
        end
      end

      it "only lists allowed values for string settings" do
        # A boolean's allowed values are fixed, so a values list would be dead
        SettingModel::KNOWN_SETTINGS.each do |name, details|
          next unless details[:type] == :boolean
          expect(details[:values]).to be_nil, "#{name} is a boolean and shouldn't list values"
        end
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

      it "coerces OPENC3_SETTING_* values by the setting's declared type" do
        env = { 'OPENC3_SETTING_AI_CHAT' => 'false', 'OPENC3_SETTING_SUBTITLE' => '2024' }
        expect(SettingModel.parse_defaults_env(env)).to eql({ 'ai_chat' => false, 'subtitle' => '2024' })
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
        expect { SettingModel.validate_setting!('theme', 'cosmosDarkSlate') }.to_not raise_error
        expect { SettingModel.validate_setting!('subtitle', 'anything at all') }.to_not raise_error
      end

      it "rejects a value outside the allowed list" do
        expect { SettingModel.validate_setting!('time_zone', 'Mars') }
          .to raise_error(/Invalid value "Mars" for setting 'time_zone'.*local.*UTC/)
      end

      it "rejects a value outside a theme's allowed list" do
        expect { SettingModel.validate_setting!('theme', 'cosmosLight') }
          .to raise_error(/Invalid value "cosmosLight" for setting 'theme'/)
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

      it "stores a JSON text setting as the text given" do
        json = '{"text":"UNCLASSIFIED","topHeight":20}'
        SettingModel.apply_defaults(env: { 'OPENC3_SETTING_CLASSIFICATION_BANNER' => json })
        expect(SettingModel.get(name: 'classification_banner')['data']).to eql json
      end

      it "seeds every setting the Admin Console exposes" do
        env = SettingModel::KNOWN_SETTINGS.to_h do |name, details|
          value = if details[:values]
                    details[:values].first
                  elsif details[:type] == :boolean
                    'true'
                  else
                    'x'
                  end
          ["OPENC3_SETTING_#{name.upcase}", value]
        end
        expect(SettingModel.apply_defaults(env: env)).to match_array(SettingModel::KNOWN_SETTINGS.keys)
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
