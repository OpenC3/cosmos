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

    # A valid env var value for a KNOWN_SETTINGS row, derived only from the row
    # itself so a newly added setting needs no test change
    def example_value(details)
      case details[:type]
      when :boolean then 'true'
      when :json, :json_text
        JSON.generate((details[:require_keys] || ['key']).to_h { |key| [key, {}] })
      else details[:values] ? details[:values].first : 'x'
      end
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

      it "strips whitespace for a boolean but keeps it for text" do
        # handle_true_false_strict strips, so ' true ' from a compose file still
        # reads as on. Text is stored exactly as given - trimming a subtitle or
        # a URL would be guessing at what the operator meant
        expect(SettingModel.coerce('ai_chat', ' true ')).to be true
        expect(SettingModel.coerce('subtitle', ' Ops ')).to eql ' Ops '
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
        # These components JSON.parse the value, so a parsed Hash would throw.
        # classification_banner declares require_keys, so the whole object.
        json = '{"text":"UNCLASSIFIED","fontColor":"#ffffff","backgroundColor":"#00cc00","topHeight":20,"bottomHeight":0}'
        expect(SettingModel.coerce('classification_banner', json)).to eql json
        expect(SettingModel.coerce('astro', '{"hideClock":true}')).to eql '{"hideClock":true}'
        expect(SettingModel.coerce('context_tag', '{"text":"DEV"}')).to eql '{"text":"DEV"}'
      end

      it "parses a :json setting into an object" do
        # AiChatConfig.load ignores a String, so text would be silently dropped
        expect(SettingModel.coerce('ai_chat_config', '{"provider":"openai"}'))
          .to eql({ 'provider' => 'openai' })
      end

      it "raises on a :json setting that isn't valid JSON" do
        expect { SettingModel.coerce('ai_chat_config', 'provider=openai') }
          .to raise_error(/Value for setting 'ai_chat_config' is not valid JSON/)
      end

      it "raises on a :json setting that isn't an object" do
        expect { SettingModel.coerce('ai_chat_config', '["openai"]') }
          .to raise_error(/must be a JSON object, got Array/)
      end

      it "raises on malformed JSON text rather than storing it" do
        # The component that JSON.parses this has no way to report a failure
        expect { SettingModel.coerce('classification_banner', '{"text":') }
          .to raise_error(/Value for setting 'classification_banner' is not valid JSON/)
      end

      it "keeps a require_keys setting as text once every key is present" do
        blob = JSON.generate({ 'cpu' => {}, 'memory' => {}, 'disk' => {}, 'global' => {} })
        expect(SettingModel.coerce('system_health', blob)).to eql blob
      end

      it "raises on a require_keys setting missing a key" do
        # log_thresholds does data['global']['enableAlerts'] and passes
        # data[metric_name] on unchecked, so a partial blob raises there instead
        expect { SettingModel.coerce('system_health', '{"global":{"enableAlerts":false}}') }
          .to raise_error(/missing required key\(s\): cpu, memory, disk/)
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
        expect(lines).to include('ai_chat: true, false (1, 0 also work)')
        expect(lines).to include('subtitle: any text')
        expect(lines).to include('ai_chat_config: JSON object')
        expect(lines).to include('system_health: JSON object with keys: cpu, memory, disk, global')
      end
    end

    describe "self.describe_json_settings" do
      it "gives an example for every JSON setting" do
        json_names = SettingModel::KNOWN_SETTINGS.select { |_n, d|
          [:json, :json_text].include?(d[:type])
        }.keys
        described = SettingModel.describe_json_settings.to_h
        expect(described.keys).to match_array(json_names)
        # Without an example an operator has no way to learn the shape short of
        # reading the component source
        expect(described.values).to all(be_a(String))
      end

      it "gives an example that actually validates" do
        SettingModel.describe_json_settings.each do |name, example|
          expect { SettingModel.coerce(name, example) }
            .to_not raise_error, "#{name}'s example is not a valid value"
        end
      end
    end

    describe "self.export_lines" do
      it "is empty when nothing is stored" do
        expect(SettingModel.export_lines).to eql []
      end

      it "reports Redis being unreachable through redis_available?" do
        # openc3cli gates --export on this so a stopped COSMOS produces an
        # actionable message instead of "Bad file descriptor (redis://...)"
        expect(SettingModel.redis_available?).to be true
        allow(SettingModel).to receive(:names).and_raise(Errno::EBADF)
        expect(SettingModel.redis_available?).to be false
      end

      it "emits a paste-ready line per stored setting" do
        SettingModel.set({ name: 'time_zone', data: 'UTC' }, scope: nil)
        expect(SettingModel.export_lines).to eql ['- OPENC3_SETTING_TIME_ZONE=UTC']
      end

      it "skips a setting with no value stored" do
        SettingModel.set({ name: 'time_zone', data: 'UTC' }, scope: nil)
        expect(SettingModel.export_lines.length).to eql 1
      end

      it "quotes JSON so YAML doesn't read it as a mapping" do
        json = '{"hideClock":false}'
        SettingModel.set({ name: 'astro', data: json }, scope: nil)
        expect(SettingModel.export_lines)
          .to eql ['- "OPENC3_SETTING_ASTRO={\\"hideClock\\":false}"']
      end

      it "serializes a :json setting stored as an object" do
        SettingModel.set({ name: 'ai_chat_config', data: { 'provider' => 'openai' } }, scope: nil)
        expect(SettingModel.export_lines)
          .to eql ['- "OPENC3_SETTING_AI_CHAT_CONFIG={\\"provider\\":\\"openai\\"}"']
      end

      it "emits a boolean unquoted" do
        SettingModel.set({ name: 'ai_chat', data: false }, scope: nil)
        expect(SettingModel.export_lines).to eql ['- OPENC3_SETTING_AI_CHAT=false']
      end

      it "round trips every setting back through the seeder" do
        # The point of --export is that pasting the output seeds the same values
        stored = SettingModel::KNOWN_SETTINGS.to_h do |name, details|
          value = SettingModel.coerce(name, example_value(details))
          SettingModel.set({ name: name, data: value }, scope: nil)
          [name, value]
        end
        env = YAML.load("e:\n" + SettingModel.export_lines.map { |l| "  #{l}" }.join("\n"))['e']
                  .to_h { |entry| entry.split('=', 2) }
        expect(env.length).to eql SettingModel::KNOWN_SETTINGS.length
        SettingModel.names().each { |name| SettingModel.get(name: name) }
        reseeded = SettingModel.parse_defaults_env(env)
        expect(reseeded).to eql stored
      end

      it "survives YAML for text that would otherwise break the line" do
        # The round trip above only feeds each row's declared example, so the
        # escaping of a comment marker, a quote, a backslash and a trailing
        # space is only exercised here
        hostile = {
          'subtitle' => 'Bay #3 "hot" c:\\logs',
          'source_url' => ' https://example.com/a#b ',
        }
        hostile.each { |name, data| SettingModel.set({ name: name, data: data }, scope: nil) }
        env = YAML.load("e:\n" + SettingModel.export_lines.map { |line| "  #{line}" }.join("\n"))['e']
                  .to_h { |entry| entry.split('=', 2) }
        expect(SettingModel.parse_defaults_env(env)).to eql hostile
      end
    end

    describe "KNOWN_SETTINGS vs the Admin Console" do
      # KNOWN_SETTINGS is hand maintained, and a name missing from it is not a
      # harmless omission: an unknown name is rejected, so a setting the Admin
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
      #   saveSetting(NAME, JSON.stringify({...}))  -> JSON text, so :json_text
      #   saveSetting(NAME, this.saveObj)           -> ditto, via a method
      #   saveSetting(NAME, this.someFlag)          -> the data() initial value
      # Anything else yields nil and is not asserted on.
      def infer_type(source, token, prop_source)
        index = source =~ /saveSetting\(\s*#{Regexp.escape(token)}\s*,/
        return nil unless index
        argument = call_args(source, source.index('(', index))[1].to_s.strip
        # JSON.stringify is the signal that the component stores JSON *text*
        return :json_text if argument.include?('JSON.stringify')
        prop = argument[/this\.(\w+)/, 1]
        return nil unless prop
        body = prop_source[/#{prop}:\s*function[^\n]*\n(.*?)\n\s{4}\},/m, 1]
        return :json_text if body&.include?('JSON.stringify')
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
        # NO_ADMIN_TAB settings are read by code rather than an Admin Console
        # tab, so they are legitimately absent from the Vue components
        stale = SettingModel::KNOWN_SETTINGS.keys - admin_console_setting_names - SettingModel::NO_ADMIN_TAB
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
          expect([:string, :boolean, :json, :json_text]).to include(details[:type]),
                                                            "#{name} has an invalid type"
          expect(name).to match(/\A[a-z0-9_]+\z/)
        end
      end

      it "only lists allowed values for string settings" do
        # A boolean's or a JSON blob's allowed values aren't an enumerable list,
        # so a values list would be dead
        SettingModel::KNOWN_SETTINGS.each do |name, details|
          next if details[:type] == :string
          expect(details[:values]).to be_nil, "#{name} is #{details[:type]} and shouldn't list values"
        end
      end

      it "only requires keys on a JSON setting" do
        SettingModel::KNOWN_SETTINGS.each do |name, details|
          next unless details[:require_keys]
          expect([:json, :json_text]).to include(details[:type]),
                                        "#{name} requires keys but isn't JSON"
        end
      end

      it "declares NO_ADMIN_TAB settings it actually lists" do
        expect(SettingModel::NO_ADMIN_TAB - SettingModel::KNOWN_SETTINGS.keys).to be_empty
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

      it "doesn't match a transposition" do
        # Documented limit of the one-character check: a swap reads as two
        # substitutions, so no suggestion is offered rather than a wrong one
        expect(SettingModel.near_match?('time_zone', 'tiem_zone')).to be false
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
          SettingModel::STRICT_ENV_VAR => '1',
        }
        expect(SettingModel.parse_defaults_env(env)).to eql({})
      end

      it "handles non-String keys and values" do
        env = { :OPENC3_SETTING_TIME_ZONE => :UTC }
        expect(SettingModel.parse_defaults_env(env)).to eql({ 'time_zone' => 'UTC' })
      end

      it "ignores a lowercase prefix" do
        # The scan is case sensitive. Nothing reads a lowercase variable, so
        # pinning it here says the silence is deliberate
        expect(SettingModel.parse_defaults_env({ 'openc3_setting_time_zone' => 'UTC' })).to eql({})
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

      it "accepts a value exactly at the size limit" do
        expect { SettingModel.validate_setting!('big', 'x' * SettingModel::MAX_VALUE_BYTES, allow_unknown: true) }
          .to_not raise_error
      end

      it "doesn't trim whitespace from a string value" do
        # A stray space from `- OPENC3_SETTING_TIME_ZONE= UTC` is rejected rather
        # than guessed at, and the error shows the space
        expect { SettingModel.validate_setting!('time_zone', SettingModel.coerce('time_zone', ' UTC')) }
          .to raise_error(/Invalid value " UTC"/)
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

    describe "self.plan_setting" do
      it "writes a setting that doesn't exist" do
        expect(SettingModel.plan_setting('time_zone', 'UTC', nil, false).first).to eql :write
      end

      it "records rather than writes when OVERWRITE finds a matching value" do
        existing = { 'data' => 'UTC' }
        action, message = SettingModel.plan_setting('time_zone', 'UTC', existing, true)
        expect(action).to eql :record
        expect(message).to match(/already matches "UTC"/)
      end

      it "writes when OVERWRITE finds a different value" do
        existing = { 'data' => 'local' }
        action, message = SettingModel.plan_setting('time_zone', 'UTC', existing, true)
        expect(action).to eql :write
        expect(message).to match(/Overwriting setting 'time_zone': "local" -> "UTC"/)
      end

      it "skips a value this seeder didn't write, without claiming it changed" do
        # No provenance record is the normal state on a deployment upgrading into
        # this feature, so the message can't assert an operator edited anything
        action, message = SettingModel.plan_setting('time_zone', 'UTC', { 'data' => 'local' }, false)
        expect(action).to eql :skip
        expect(message).to match(/holds a value initsettings didn't write - leaving as "local"/)
        expect(message).to match(/set #{SettingModel::OVERWRITE_ENV_VAR} to replace it/)
      end

      it "skips a seeded setting that already matches" do
        SettingModel.record_seeded('time_zone', 'UTC')
        action, message = SettingModel.plan_setting('time_zone', 'UTC', { 'data' => 'UTC' }, false)
        expect(action).to eql :skip
        expect(message).to match(/already matches "UTC" - leaving unchanged/)
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
        json = '{"text":"UNCLASSIFIED","fontColor":"#ffffff","backgroundColor":"#00cc00","topHeight":20,"bottomHeight":0}'
        SettingModel.apply_defaults(env: { 'OPENC3_SETTING_CLASSIFICATION_BANNER' => json })
        expect(SettingModel.get(name: 'classification_banner')['data']).to eql json
      end

      it "seeds every setting" do
        # Every declared setting must be seedable with a value built purely from
        # its own row - if a new type needs special handling to be settable,
        # that is worth failing on here
        env = SettingModel::KNOWN_SETTINGS.to_h do |name, details|
          ["OPENC3_SETTING_#{name.upcase}", example_value(details)]
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

      it "reports an unparsable overwrite env var and treats it as off" do
        # Off is the safe reading - the alternative is discarding an Admin
        # Console edit on the strength of a value we couldn't parse
        SettingModel.set({ name: 'time_format', data: 'ampm' }, scope: nil)
        env = {
          'OPENC3_SETTING_TIME_FORMAT' => '24hr',
          'OPENC3_SETTINGS_OVERWRITE' => 'maybe',
        }
        expect($stdout).to receive(:puts)
          .with(/ERROR: Invalid value "maybe" for OPENC3_SETTINGS_OVERWRITE.*treating OPENC3_SETTINGS_OVERWRITE as off/)
        allow($stdout).to receive(:puts)
        expect { SettingModel.apply_defaults(env: env) }.to_not raise_error
        expect(SettingModel.get(name: 'time_format')['data']).to eql 'ampm'
      end

      it "reports an unparsable allow unknown env var and treats it as off" do
        env = {
          'OPENC3_SETTING_BRAND_NEW' => 'x',
          'OPENC3_SETTINGS_ALLOW_UNKNOWN' => 'maybe',
        }
        expect($stdout).to receive(:puts)
          .with(/ERROR: Invalid value "maybe" for OPENC3_SETTINGS_ALLOW_UNKNOWN/)
        expect($stdout).to receive(:puts).with(/ERROR: 'brand_new' is not a known/)
        allow($stdout).to receive(:puts)
        expect(SettingModel.apply_defaults(env: env)).to eql []
        expect(SettingModel.get(name: 'brand_new')).to be_nil
      end

      it "still seeds the good settings when a control variable is malformed" do
        env = {
          'OPENC3_SETTING_TIME_ZONE' => 'UTC',
          'OPENC3_SETTINGS_OVERWRITE' => 'maybe',
        }
        expect(SettingModel.apply_defaults(env: env)).to eql ['time_zone']
        expect(SettingModel.get(name: 'time_zone')['data']).to eql 'UTC'
      end

      it "reports an uncoercible boolean value instead of aborting" do
        # OPENC3_SETTING_AI_CHAT=nope used to escape as an ArgumentError from
        # coerce, taking init down with it
        env = { 'OPENC3_SETTING_AI_CHAT' => 'nope', 'OPENC3_SETTING_TIME_ZONE' => 'UTC' }
        expect($stdout).to receive(:puts).with(/ERROR: Invalid value "nope" for setting 'ai_chat'/)
        allow($stdout).to receive(:puts)
        expect(SettingModel.apply_defaults(env: env)).to eql ['time_zone']
        expect(SettingModel.get(name: 'ai_chat')).to be_nil
        expect(SettingModel.get(name: 'time_zone')['data']).to eql 'UTC'
      end

      context "OPENC3_SETTINGS_STRICT" do
        it "fails when a setting is rejected" do
          env = { 'OPENC3_SETTING_TIME_ZONE' => 'Mars', 'OPENC3_SETTINGS_STRICT' => '1' }
          expect { SettingModel.apply_defaults(env: env) }
            .to raise_error(/1 OPENC3_SETTING_\* configuration problem\(s\).*Invalid value "Mars"/)
        end

        it "fails on an unknown name" do
          env = { 'OPENC3_SETTING_TIME_ZONES' => 'UTC', 'OPENC3_SETTINGS_STRICT' => 'true' }
          expect { SettingModel.apply_defaults(env: env) }
            .to raise_error(/'time_zones' is not a known COSMOS setting/)
        end

        it "still writes the settings that were fine before failing" do
          env = { 'OPENC3_SETTING_TIME_ZONE' => 'Mars', 'OPENC3_SETTING_TIME_FORMAT' => 'ampm',
                  'OPENC3_SETTINGS_STRICT' => '1' }
          expect { SettingModel.apply_defaults(env: env) }.to raise_error(/configuration problem\(s\)/)
          expect(SettingModel.get(name: 'time_format')['data']).to eql 'ampm'
        end

        it "doesn't fail when nothing is wrong" do
          env = { 'OPENC3_SETTING_TIME_ZONE' => 'UTC', 'OPENC3_SETTINGS_STRICT' => '1' }
          expect(SettingModel.apply_defaults(env: env)).to eql ['time_zone']
        end

        it "is off by default" do
          env = { 'OPENC3_SETTING_TIME_ZONE' => 'Mars' }
          expect { SettingModel.apply_defaults(env: env) }.to_not raise_error
        end

        it "is off for 0, false and empty" do
          ['0', 'false', ''].each do |value|
            env = { 'OPENC3_SETTING_TIME_ZONE' => 'Mars', 'OPENC3_SETTINGS_STRICT' => value }
            expect { SettingModel.apply_defaults(env: env) }.to_not raise_error
          end
        end

        it "honors an explicit strict argument over the env var" do
          env = { 'OPENC3_SETTING_TIME_ZONE' => 'Mars', 'OPENC3_SETTINGS_STRICT' => '0' }
          expect { SettingModel.apply_defaults(env: env, strict: true) }
            .to raise_error(/configuration problem\(s\)/)
        end

        it "reports an unparsable value and stays off" do
          env = { 'OPENC3_SETTING_TIME_ZONE' => 'UTC', 'OPENC3_SETTINGS_STRICT' => 'maybe' }
          expect($stdout).to receive(:puts)
            .with(/ERROR: Invalid value "maybe" for OPENC3_SETTINGS_STRICT.*treating OPENC3_SETTINGS_STRICT as off/)
          allow($stdout).to receive(:puts)
          expect { SettingModel.apply_defaults(env: env) }.to_not raise_error
        end

        it "isn't mistaken for a setting by the prefix scan" do
          expect(SettingModel.parse_defaults_env({ SettingModel::STRICT_ENV_VAR => '1' })).to eql({})
        end
      end

      it "tells the operator how to make errors fail init" do
        expect($stdout).to receive(:puts).with(/Set OPENC3_SETTINGS_STRICT to fail init on these/)
        allow($stdout).to receive(:puts)
        SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_ZONE' => 'Mars' })
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

      it "skips an invalid value instead of aborting init" do
        # The init container restarts on failure, so raising here would crash
        # loop COSMOS over a cosmetic setting
        env = { 'OPENC3_SETTING_TIME_ZONE' => 'Mars' }
        expect { SettingModel.apply_defaults(env: env) }.to_not raise_error
        expect(SettingModel.get(name: 'time_zone')).to be_nil
      end

      it "still applies the good settings when one is invalid" do
        env = { 'OPENC3_SETTING_TIME_ZONE' => 'Mars', 'OPENC3_SETTING_TIME_FORMAT' => 'ampm' }
        expect(SettingModel.apply_defaults(env: env)).to eql ['time_format']
        expect(SettingModel.get(name: 'time_format')['data']).to eql 'ampm'
      end

      it "reports every skipped setting and says the default is used" do
        env = { 'OPENC3_SETTING_TIME_ZONE' => 'Mars', 'OPENC3_SETTING_TIME_ZONES' => 'UTC' }
        expect($stdout).to receive(:puts).with(/ERROR: Invalid value "Mars"/)
        expect($stdout).to receive(:puts).with(/ERROR: 'time_zones' is not a known/)
        expect($stdout).to receive(:puts).with(/2 OPENC3_SETTING_\* configuration problem\(s\)/)
        allow($stdout).to receive(:puts)
        SettingModel.apply_defaults(env: env)
      end

      it "fails only in a dry run, so a preflight check can gate on it" do
        env = { 'OPENC3_SETTING_TIME_ZONE' => 'Mars' }
        expect { SettingModel.apply_defaults(env: env, dry_run: true) }
          .to raise_error(/1 OPENC3_SETTING_\* configuration problem\(s\)/)
      end

      it "writes nothing in a dry run" do
        env = { 'OPENC3_SETTING_TIME_ZONE' => 'UTC' }
        expect(SettingModel.apply_defaults(env: env, dry_run: true)).to eql ['time_zone']
        expect(SettingModel.get(name: 'time_zone')).to be_nil
      end

      it "reports the planned action for each setting in a dry run" do
        SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => '24hr' })
        SettingModel.set({ name: 'time_zone', data: 'local' }, scope: nil)
        expect($stdout).to receive(:puts).with(/\[dry run\] Updating unedited setting 'time_format'/)
        expect($stdout).to receive(:puts)
          .with(/\[dry run\] Setting 'time_zone' holds a value initsettings didn't write/)
        allow($stdout).to receive(:puts)
        SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => 'ampm',
                                           'OPENC3_SETTING_TIME_ZONE' => 'UTC' }, dry_run: true)
      end

      it "is a no-op when OVERWRITE is set and the value already matches" do
        env = { 'OPENC3_SETTING_TIME_ZONE' => 'UTC', 'OPENC3_SETTINGS_OVERWRITE' => '1' }
        SettingModel.apply_defaults(env: env)
        expect($stdout).to receive(:puts).with(/Setting 'time_zone' already matches "UTC"/)
        allow($stdout).to receive(:puts)
        # Nothing to write, so nothing is reported as written - rewriting the same
        # value would bump updated_at on every init
        expect(SettingModel.apply_defaults(env: env)).to eql []
      end

      it "records provenance when OVERWRITE finds the value already correct" do
        # The upgrade path where the operator had already set the value by hand
        # to what the env says: OVERWRITE has nothing to write but must still
        # take ownership, or the env stays locked out on the next run
        SettingModel.set({ name: 'time_format', data: 'ampm' }, scope: nil)
        expect(SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => 'ampm',
                                                 'OPENC3_SETTINGS_OVERWRITE' => '1' })).to eql []
        expect(SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => '24hr' }))
          .to eql ['time_format']
        expect(SettingModel.get(name: 'time_format')['data']).to eql '24hr'
      end

      it "doesn't record provenance for a dry run" do
        SettingModel.set({ name: 'time_format', data: 'ampm' }, scope: nil)
        SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => 'ampm',
                                          'OPENC3_SETTINGS_OVERWRITE' => '1' }, dry_run: true)
        expect(SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_FORMAT' => '24hr' })).to eql []
        expect(SettingModel.get(name: 'time_format')['data']).to eql 'ampm'
      end

      it "falls back to name and value checks when Redis is unreachable" do
        allow(SettingModel).to receive(:names).and_raise(StandardError, 'no redis')
        expect($stdout).to receive(:puts).with(/Redis is not reachable/)
        allow($stdout).to receive(:puts)
        expect(SettingModel.apply_defaults(env: { 'OPENC3_SETTING_TIME_ZONE' => 'UTC' }, dry_run: true))
          .to eql ['time_zone']
      end

      it "says so when nothing is set" do
        expect($stdout).to receive(:puts).with(/No OPENC3_SETTING_\* environment variables set/)
        expect(SettingModel.apply_defaults(env: {}, dry_run: true)).to eql []
      end

      it "doesn't claim nothing was set when every value failed to coerce" do
        # settings ends up empty either way, but the operator did set one
        expect($stdout).to_not receive(:puts).with(/No OPENC3_SETTING_\* environment variables set/)
        allow($stdout).to receive(:puts)
        expect { SettingModel.apply_defaults(env: { 'OPENC3_SETTING_AI_CHAT' => 'nope' }) }
          .to_not raise_error
      end

      it "reads from ENV by default" do
        expect(SettingModel).to receive(:parse_defaults_env).with(ENV, anything).and_return({})
        SettingModel.apply_defaults()
      end
    end
  end
end
