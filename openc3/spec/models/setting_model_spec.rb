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

    describe "KNOWN_SETTINGS vs the Admin Console" do
      # KNOWN_SETTINGS is hand maintained, and a name missing from it is not a
      # harmless omission: an unknown name aborts init, so a setting the Admin
      # Console offers but the table doesn't list can't be seeded at all. This
      # reads the setting names straight out of the Vue components so the two
      # can't drift. The path is repo-only, not shipped in the gem.
      SETTINGS_VUE_DIR = File.expand_path(
        '../../../openc3-cosmos-init/plugins/packages/openc3-vue-common/src/tools/admin/tabs/settings',
        __dir__
      )

      # Names the components pass to loadSetting / saveSetting, resolving the
      # `const settingName = 'time_zone'` indirection those files use.
      def admin_console_setting_names
        Dir["#{SETTINGS_VUE_DIR}/*Settings.vue"].flat_map do |file|
          source = File.read(file)
          consts = source.scan(/(?:const|let)\s+(\w+)\s*=\s*'([a-z0-9_]+)'/).to_h
          source.scan(/(?:load|save)Setting\(\s*([A-Za-z_]\w*|'[a-z0-9_]+')/).flatten.map do |token|
            token.start_with?("'") ? token.delete("'") : consts[token]
          end
        end.compact.uniq
      end

      # Text of the arguments of the call whose opening paren is at `index`,
      # scanning balanced parens so a multi-line JSON.stringify({ ... })
      # argument comes back whole rather than truncated at its first comma.
      def call_args(source, index)
        depth = 0
        buffer = +''
        args = []
        source[index..-1].each_char do |char|
          case char
          when '(' then depth += 1; next if depth == 1
          when ')' then depth -= 1; return args << buffer if depth.zero?
          when ',' then (args << buffer; buffer = +''; next) if depth == 1
          else nil # ordinary character, appended below like a nested ( ) or ,
          end
          buffer << char
        end
        args
      end

      # What the component passes to saveSetting, which is what ends up in
      # Redis - the declared type has to match this, not what the control
      # displays. Three shapes appear in these files:
      #   saveSetting(NAME, JSON.stringify({...}))  -> JSON text, so :string
      #   saveSetting(NAME, this.saveObj)           -> ditto, via a method
      #   saveSetting(NAME, this.someFlag)          -> the data() initial value
      # Anything else yields nil and is not asserted on.
      def infer_type(source, token, prop_source)
        index = source =~ /saveSetting\(\s*#{Regexp.escape(token)}\s*,/
        return nil unless index
        argument = call_args(source, source.index('(', index))[1].to_s.strip
        return :string if argument.include?('JSON.stringify')
        prop = argument[/this\.(\w+)/, 1]
        return nil unless prop
        body = prop_source[/#{prop}:\s*function[^\n]*\n(.*?)\n\s{4}\},/m, 1]
        return :string if body&.include?('JSON.stringify')
        case prop_source[/^\s+#{prop}:\s*(.+?),?\s*$/, 1]
        when 'true', 'false' then :boolean
        when /\A'.*'\z/, /\A".*"\z/ then :string
        else nil # unrecognized shape - the caller reports it as unresolved
        end
      end

      # @return [Hash] setting name => type the component saves
      def admin_console_setting_types
        Dir["#{SETTINGS_VUE_DIR}/*Settings.vue"].each_with_object({}) do |file, types|
          source = File.read(file)
          consts = source.scan(/(?:const|let)\s+(\w+)\s*=\s*'([a-z0-9_]+)'/).to_h
          source.scan(/saveSetting\(\s*([A-Za-z_]\w*|'[a-z0-9_]+')/).flatten.uniq.each do |token|
            name = token.start_with?("'") ? token.delete("'") : consts[token]
            next unless name
            type = infer_type(source, token, source)
            types[name] = type if type
          end
        end
      end

      it "lists every setting the Admin Console reads or writes" do
        skip "Vue sources not present" unless Dir.exist?(SETTINGS_VUE_DIR)
        found = admin_console_setting_names
        expect(found).to_not be_empty, "extracted no setting names - the regex needs updating"
        missing = found - SettingModel::KNOWN_SETTINGS.keys
        expect(missing).to be_empty,
                           "Admin Console settings missing from KNOWN_SETTINGS: #{missing.join(', ')}. " \
                           "Add a row for each - see the comment above KNOWN_SETTINGS."
      end

      it "doesn't list a setting the Admin Console no longer has" do
        skip "Vue sources not present" unless Dir.exist?(SETTINGS_VUE_DIR)
        stale = SettingModel::KNOWN_SETTINGS.keys - admin_console_setting_names
        expect(stale).to be_empty, "KNOWN_SETTINGS lists settings no component uses: #{stale.join(', ')}"
      end

      it "declares the type each component actually saves" do
        skip "Vue sources not present" unless Dir.exist?(SETTINGS_VUE_DIR)
        inferred = admin_console_setting_types
        # Require full coverage, not just agreement on what was inferred - a
        # component written in a shape infer_type doesn't handle would
        # otherwise quietly shrink this check instead of failing
        unresolved = admin_console_setting_names - inferred.keys
        expect(unresolved).to be_empty,
                              "couldn't infer the saved type for: #{unresolved.join(', ')}. " \
                              "Teach infer_type the shape those components use."
        wrong = inferred.reject { |name, type| SettingModel::KNOWN_SETTINGS.dig(name, :type) == type }
        expect(wrong).to be_empty, wrong.map { |name, type|
          "'#{name}' is declared #{SettingModel::KNOWN_SETTINGS.dig(name, :type).inspect} " \
          "but the component saves #{type.inspect}"
        }.join('; ')
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

      it "applies a changed env value while the setting is untouched" do
        # The whole point of tracking provenance: editing the env var and
        # restarting works, which plain skip-if-exists could never do
        SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => '24hr' })
        expect(SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => 'ampm' }))
          .to eql ['time_format']
        expect(SettingModel.get(name: 'time_format')['data']).to eql 'ampm'
      end

      it "leaves a setting an operator changed, even when the env differs" do
        SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => '24hr' })
        # Admin Console edit
        SettingModel.set({ name: 'time_format', data: 'ampm' }, scope: nil)
        expect(SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => '24hr' })).to eql []
        expect(SettingModel.get(name: 'time_format')['data']).to eql 'ampm'
      end

      it "keeps leaving an edited setting alone on later inits" do
        SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => '24hr' })
        SettingModel.set({ name: 'time_format', data: 'ampm' }, scope: nil)
        3.times { SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => '24hr' }) }
        expect(SettingModel.get(name: 'time_format')['data']).to eql 'ampm'
      end

      it "is a no-op when the env value already matches" do
        env = { 'OPENC3_SETTING_TIME_FORMAT' => '24hr' }
        SettingModel.apply_defaults(env: env)
        expect(SettingModel.apply_defaults(env: env)).to eql []
      end

      it "tracks provenance for boolean settings too" do
        SettingModel.apply_defaults(env: { 'OPENC3_SETTING_AI_CHAT' => 'true' })
        expect(SettingModel.apply_defaults(env: { 'OPENC3_SETTING_AI_CHAT' => 'false' }))
          .to eql ['ai_chat']
        expect(SettingModel.get(name: 'ai_chat')['data']).to be false
        SettingModel.set({ name: 'ai_chat', data: true }, scope: nil)
        expect(SettingModel.apply_defaults(env: { 'OPENC3_SETTING_AI_CHAT' => 'false' })).to eql []
        expect(SettingModel.get(name: 'ai_chat')['data']).to be true
      end

      it "leaves a setting with no provenance record alone" do
        # Set by the Admin Console, seed_database, or a release before this
        # tracking existed - clobbering it is the exact failure being prevented
        SettingModel.set({ name: 'time_format', data: '24hr' }, scope: nil)
        expect(SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => 'ampm' })).to eql []
        expect(SettingModel.get(name: 'time_format')['data']).to eql '24hr'
      end

      it "treats a corrupt provenance record as operator owned" do
        SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => '24hr' })
        Store.hset(SettingModel::SEEDED_PRIMARY_KEY, 'time_format', 'not json')
        expect(SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => 'ampm' })).to eql []
        expect(SettingModel.get(name: 'time_format')['data']).to eql '24hr'
      end

      it "lets OVERWRITE recover a setting that has no provenance record" do
        # The upgrade path: one run with OVERWRITE and the env is back in charge
        SettingModel.set({ name: 'time_format', data: '24hr' }, scope: nil)
        SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => 'ampm',
                                           'OPENC3_SETTINGS_OVERWRITE' => '1' })
        expect(SettingModel.get(name: 'time_format')['data']).to eql 'ampm'
        # provenance now recorded, so a later env change applies without OVERWRITE
        expect(SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => '24hr' }))
          .to eql ['time_format']
      end

      it "overwrites an operator edit when OVERWRITE is set" do
        SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => '24hr' })
        SettingModel.set({ name: 'time_format', data: 'ampm' }, scope: nil)
        env = { 'OPENC3_SETTING_TIME_FORMAT' => '24hr', 'OPENC3_SETTINGS_OVERWRITE' => '1' }
        expect(SettingModel.apply_defaults(env: env)).to eql ['time_format']
        expect(SettingModel.get(name: 'time_format')['data']).to eql '24hr'
      end

      it "reports what an overwrite destroyed" do
        SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => '24hr' })
        SettingModel.set({ name: 'time_format', data: 'ampm' }, scope: nil)
        expect($stdout).to receive(:puts).with(/Overwriting setting 'time_format': "ampm" -> "24hr"/)
        SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => '24hr',
                                           'OPENC3_SETTINGS_OVERWRITE' => '1' })
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

      it "raises on an unparsable overwrite env var rather than guessing" do
        env = {
          'OPENC3_SETTING_TIME_ZONE' => 'UTC',
          'OPENC3_SETTINGS_OVERWRITE' => 'maybe',
        }
        expect { SettingModel.apply_defaults(env: env) }
          .to raise_error(ArgumentError, /Invalid value "maybe" for OPENC3_SETTINGS_OVERWRITE/)
        expect(SettingModel.get(name: 'time_zone')).to be_nil
      end

      it "raises on an unparsable allow unknown env var" do
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
