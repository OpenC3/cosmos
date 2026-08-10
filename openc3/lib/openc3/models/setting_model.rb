# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'json'
require 'openc3/config/config_parser'
require 'openc3/models/model'

module OpenC3
  class SettingModel < Model
    PRIMARY_KEY = 'openc3__settings'

    # One environment variable per setting: OPENC3_SETTING_TIME_ZONE=UTC sets
    # the 'time_zone' setting. A prefix scan rather than an enumerated list, so
    # a setting added by a later release needs no change here. Deliberately not
    # a single JSON blob variable: embedding JSON in a compose environment
    # list, a Helm value and an ECS task definition each need different
    # escaping, and one variable per setting reads the same in all three.
    SETTING_ENV_PREFIX = 'OPENC3_SETTING_'

    # Set to 1/true/yes/on to write the values on every init rather than only
    # when the setting is missing. Use when the environment is the source of
    # truth and Admin Console edits should not survive a restart.
    #
    # Unlike the OPENC3_NO_* install flags, this is NOT enabled by presence:
    # it discards whatever an operator configured in the Admin Console, so
    # OPENC3_SETTINGS_OVERWRITE=0 and =false mean off, as they read. An
    # unrecognized value is an error rather than a silent guess.
    #
    # Note this does not start with SETTING_ENV_PREFIX, so the prefix scan
    # can't mistake it for a setting named 'overwrite'.
    OVERWRITE_ENV_VAR = 'OPENC3_SETTINGS_OVERWRITE'

    # Set to 1/true/yes/on to allow setting names that are not in
    # KNOWN_SETTINGS. Needed for a setting added by a newer tool than this
    # library knows about; without it a misspelled name aborts init.
    ALLOW_UNKNOWN_ENV_VAR = 'OPENC3_SETTINGS_ALLOW_UNKNOWN'


    # Every setting that can be seeded from the environment.
    #
    # An unknown name is rejected rather than written: nothing reads it, so the
    # result of a typo is a dead Redis key plus a setting the operator believes
    # they configured and did not. ALLOW_UNKNOWN_ENV_VAR opts out.
    #
    # TO ADD A SETTING, add a row here. The name is the string the Admin
    # Console component passes to loadSetting/saveSetting - find it in
    # openc3-cosmos-init/plugins/packages/openc3-vue-common/src/tools/admin/
    # tabs/settings/<Name>Settings.vue, e.g. TimeZoneSettings.vue has
    # `const settingName = 'time_zone'`. Then:
    #
    #   type:   :string or :boolean, matching what the component SAVES, not
    #           what it displays. A component that calls JSON.stringify before
    #           saveSetting and JSON.parse in parseSetting stores JSON *text*,
    #           so its type is :string - storing a parsed object instead would
    #           make its JSON.parse throw. See 'astro' below.
    #   values: the allowed values, or nil for free text (a URL, a subtitle).
    #           Copy them from the component's v-select items.
    #
    # Example, for a hypothetical LogLevelSettings.vue holding 'log_level':
    #
    #   'log_level' => { type: :string, values: ['DEBUG', 'INFO', 'WARN'] },
    #
    # No other change is needed - the env var (OPENC3_SETTING_LOG_LEVEL), the
    # validation and the `cli initsettings --help` listing all follow.
    KNOWN_SETTINGS = {
      # Booleans. The frontend treats the string "false" as truthy, so these
      # have to reach Redis as real booleans.
      'ai_chat' => { type: :boolean, values: nil },
      'news_feed' => { type: :boolean, values: nil },
      'script_runner_locking' => { type: :boolean, values: nil },
      'script_runner_lifecycle' => { type: :boolean, values: nil }, # Enterprise only
      # Fixed choice strings
      'time_zone' => { type: :string, values: ['local', 'UTC'] },
      'time_format' => { type: :string, values: ['ampm', '24hr'] },
      'theme' => { type: :string, values: ['cosmosDark', 'cosmosDarkCobalt', 'cosmosDarkIndigo',
                                           'cosmosDarkSlate', 'cosmosDarkEmerald'] },
      # Free text
      'subtitle' => { type: :string, values: nil },
      'source_url' => { type: :string, values: nil },
      'rubygems_url' => { type: :string, values: nil },
      'pypi_url' => { type: :string, values: nil },
      # JSON *text*: these components JSON.stringify before saving and
      # JSON.parse on load, so the stored value is a String, not an object
      'astro' => { type: :string, values: nil },
      'classification_banner' => { type: :string, values: nil },
      'context_tag' => { type: :string, values: nil },
    }

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    def self.get(name:, scope: nil)
      super(PRIMARY_KEY, name: name)
    end

    def self.names(scope: nil)
      super(PRIMARY_KEY)
    end

    def self.all(scope: nil)
      super(PRIMARY_KEY)
    end
    # END NOTE

    # Seed settings from OPENC3_SETTING_<NAME> environment variables. Called by
    # `openc3cli initsettings` during init container startup.
    #
    # By default a setting is only written when it does not already exist, so a
    # value changed in the Admin Console survives a container restart. Set
    # OPENC3_SETTINGS_OVERWRITE to write on every run instead.
    #
    # @param env [Hash] environment to read from, defaults to ENV
    # @param overwrite [Boolean, nil] nil reads OVERWRITE_ENV_VAR from env
    # @return [Array<String>] names of the settings that were written
    def self.apply_defaults(env: ENV, overwrite: nil)
      overwrite = truthy_env?(env, OVERWRITE_ENV_VAR) if overwrite.nil?
      allow_unknown = truthy_env?(env, ALLOW_UNKNOWN_ENV_VAR)
      settings = parse_defaults_env(env)
      return [] if settings.empty?

      written = []
      settings.each do |name, value|
        validate_setting!(name, value, allow_unknown: allow_unknown)
        existing = get(name: name)
        if existing and !overwrite
          unless seeded_value?(name, existing['data'])
            puts "Setting '#{name}' was changed from the seeded value - leaving as #{existing['data'].inspect}"
            next
          end
          if existing['data'] == value
            puts "Setting '#{name}' already matches #{value.inspect} - leaving unchanged"
            next
          end
          puts "Updating unedited setting '#{name}': #{existing['data'].inspect} -> #{value.inspect}"
        elsif existing and overwrite and existing['data'] != value
          # Overwrite discards an Admin Console edit, so say what was lost -
          # otherwise the log reads identically to a first-time seed
          puts "Overwriting setting '#{name}': #{existing['data'].inspect} -> #{value.inspect} " \
               "(#{OVERWRITE_ENV_VAR} is set)"
        else
          puts "Set default setting '#{name}' to: #{value.inspect}"
        end
        set({ name: name, data: value }, scope: nil)
        record_seeded(name, value)
        written << name
      end
      written
    end

    # Provenance for the values this seeder wrote, so a later init can tell an
    # untouched setting from one an operator changed in the Admin Console.
    # Without it the seeder has two bad options: never update (so editing the
    # env var does nothing) or always update (so Admin Console edits silently
    # revert on every restart).
    SEEDED_PRIMARY_KEY = 'openc3__settings_seeded'

    # @return [Boolean] true when the current value is the one we last seeded,
    #   meaning nobody has changed it since.
    #
    # An unrecorded setting is NOT treated as seeded. It was set by the Admin
    # Console, by seed_database, or by a release before this tracking existed,
    # and overwriting it is the silent clobber this mechanism exists to
    # prevent. The cost is that a deployment upgrading into this feature needs
    # one run with OVERWRITE_ENV_VAR before env changes take effect again.
    def self.seeded_value?(name, current)
      recorded = Store.hget(SEEDED_PRIMARY_KEY, name)
      return false if recorded.nil?
      JSON.parse(recorded, allow_nan: true, create_additions: true)['data'] == current
    rescue JSON::ParserError
      false
    end

    def self.record_seeded(name, value)
      Store.hset(SEEDED_PRIMARY_KEY, name, JSON.generate({ 'data' => value.as_json(allow_nan: true) }))
    end

    # Collect every OPENC3_SETTING_<NAME> variable into a name => value hash.
    #
    # @param env [Hash] environment to read from
    # @return [Hash] setting name => coerced value
    def self.parse_defaults_env(env)
      settings = {}
      env.each do |key, value|
        key = to_str(key)
        next unless key.start_with?(SETTING_ENV_PREFIX)
        name = key[SETTING_ENV_PREFIX.length..-1].downcase
        next if name.empty?
        settings[name] = coerce(name, to_str(value))
      end
      settings
    end

    # Environment variables and local mode files are always strings, but a
    # setting holds whatever the Admin Console stores - a boolean for 'ai_chat',
    # a String for everything else, including the settings whose String happens
    # to contain JSON.
    #
    # Driven by the declared type rather than by attempting JSON.parse on
    # everything: parse-and-see turns 'classification_banner' into a Hash and
    # the component's own JSON.parse then throws on it, and it would turn a
    # subtitle of "2024" into a number.
    #
    # @param name [String] setting name
    # @param value [String] raw value
    # @return [Object] value in the form the frontend expects
    def self.coerce(name, value)
      return value unless value.is_a?(String)
      return value unless KNOWN_SETTINGS.dig(name, :type) == :boolean
      ConfigParser.handle_true_false_strict(value, description: "setting '#{name}'")
    end

    # Largest value we will write. Settings are read into every browser tab, so
    # this is a guard against an env var that is a file by mistake rather than a
    # real limit - the biggest real setting is a few hundred bytes.
    MAX_VALUE_BYTES = 64 * 1024

    # Fail loudly on anything we can prove is wrong. The init container exits
    # non-zero and restarts, which is far easier to diagnose than a tool
    # silently falling back to its built-in default.
    def self.validate_setting!(name, value, allow_unknown: false)
      unless name =~ /\A[a-z0-9_]+\z/
        raise "Invalid setting name #{name.inspect}. Names must be lowercase letters, numbers and underscores"
      end

      unless KNOWN_SETTINGS.key?(name)
        unless allow_unknown
          message = "'#{name}' is not a known COSMOS setting"
          suggestion = KNOWN_SETTINGS.keys.find { |known| near_match?(known, name) }
          message += ". Did you mean '#{suggestion}'?" if suggestion
          message += " Set #{ALLOW_UNKNOWN_ENV_VAR} to apply it anyway."
          raise message
        end
        puts "WARNING: '#{name}' is not a known COSMOS setting - #{ALLOW_UNKNOWN_ENV_VAR} is set, applying anyway"
      end

      size = value.is_a?(String) ? value.bytesize : JSON.generate(value).bytesize
      if size > MAX_VALUE_BYTES
        raise "Value for setting '#{name}' is #{size} bytes, exceeds the #{MAX_VALUE_BYTES} byte limit"
      end

      allowed = KNOWN_SETTINGS.dig(name, :values)
      return if allowed.nil? or allowed.include?(value)
      # Report the coerced value so 'Local' vs 'local' is visible in the error
      raise "Invalid value #{value.inspect} for setting '#{name}'. Must be one of: #{allowed.map(&:inspect).join(', ')}"
    end

    # Every setting that can be seeded, with its allowed values, for the
    # `cli initsettings --help` listing.
    #
    # @return [Array<String>] one 'name: allowed values' line per setting
    def self.describe_settings
      KNOWN_SETTINGS.map do |name, details|
        allowed = if details[:values]
                    details[:values].join(', ')
                  elsif details[:type] == :boolean
                    '1, true, 0, false'
                  else
                    'any text'
                  end
        "#{name}: #{allowed}"
      end
    end

    # Cheap typo detection: same length with one character different, or one
    # character inserted / deleted. Enough to catch 'time_zones' and 'timezone'
    # without pulling in a Levenshtein dependency.
    def self.near_match?(known, name)
      return false if (known.length - name.length).abs > 1
      long, short = known.length >= name.length ? [known, name] : [name, known]
      i = 0
      i += 1 while i < short.length and long[i] == short[i]
      return true if i == short.length and long.length - short.length <= 1
      if long.length == short.length
        long[(i + 1)..-1] == short[(i + 1)..-1]
      else
        long[(i + 1)..-1] == short[i..-1]
      end
    end

    # Read a boolean control variable. Unset means false.
    #
    # The OPENC3_NO_* install flags are enabled by presence, so 'VAR=0' turns
    # them ON. That is fine for "skip installing a tool" and wrong here:
    # OVERWRITE_ENV_VAR discards what an operator configured in the Admin
    # Console, so '0' and 'false' have to mean off, as they read.
    #
    # @param env [Hash] environment to read from
    # @param name [String] variable name
    # @return [Boolean]
    def self.truthy_env?(env, name)
      ConfigParser.handle_true_false_strict(to_str(env[name]), description: name)
    end

    # ENV values are frozen Strings but a Hash passed in tests may hold symbols
    def self.to_str(value)
      value.nil? ? nil : value.to_s
    end

    def initialize(name:, scope: nil, data:)
      super(PRIMARY_KEY, name: name, scope: scope)
      @data = data
    end

    # @return [Hash] JSON encoding of this model
    def as_json(*a)
      {
        'name' => @name,
        'data' => @data.as_json(*a),
        'updated_at' => @updated_at
      }
    end
  end
end
