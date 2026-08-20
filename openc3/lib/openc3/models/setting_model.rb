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

    # Set to 1/true to allow setting names that are not in KNOWN_SETTINGS.
    # Needed for a setting added by a newer tool than this library knows about;
    # without it a misspelled name is reported and skipped.
    ALLOW_UNKNOWN_ENV_VAR = 'OPENC3_SETTINGS_ALLOW_UNKNOWN'

    # Set to 1/true to make a rejected setting fail init instead of being
    # reported and skipped. Off by default: the init container restarts on
    # failure, so a typo in a cosmetic setting would otherwise crash loop COSMOS
    # with the cause buried in restarting container logs, and the operator ends
    # up with no COSMOS rather than COSMOS with one default time zone. Turn it on
    # for a deployment that would rather not come up than come up misconfigured.
    #
    # `initsettings --dry-run` fails regardless - a preflight check exists to.
    STRICT_ENV_VAR = 'OPENC3_SETTINGS_STRICT'


    # Every setting that can be seeded from the environment.
    #
    # An unknown name is reported and skipped rather than written: nothing reads
    # it, so the result of a typo is a dead Redis key plus a setting the
    # operator believes they configured and did not. Init still continues -
    # ALLOW_UNKNOWN_ENV_VAR opts out of the check entirely.
    #
    # TO ADD A SETTING, add a row here. The name is the string the Admin
    # Console component passes to loadSetting/saveSetting - find it in
    # openc3-cosmos-init/plugins/packages/openc3-vue-common/src/tools/admin/
    # tabs/settings/<Name>Settings.vue, e.g. TimeZoneSettings.vue has
    # `const settingName = 'time_zone'`. Then:
    #
    #   type:   what the reader SAVES and expects back, not what a control
    #           displays. Storing the wrong shape is silent - the reader either
    #           throws or ignores the value:
    #             :string     plain text (a URL, a subtitle)
    #             :boolean    real true/false; the frontend treats the string
    #                         "false" as truthy, so these must not be text
    #             :json_text  JSON kept as a String. A component that calls
    #                         JSON.stringify before saveSetting and JSON.parse
    #                         in parseSetting is this - handing it a parsed
    #                         object makes its own JSON.parse throw
    #             :json       JSON parsed into an object before storing, for a
    #                         reader that checks the shape. AiChatConfig.load
    #                         does `raw['data'].is_a?(Hash) ? ... : {}`, so text
    #                         would be silently discarded
    #   values: the allowed values, or nil for free text.
    #           Copy them from the component's v-select items.
    #   require_keys: for :json/:json_text, top-level keys the blob must have.
    #           Use when a partial blob would break the reader rather than just
    #           fall back to a default. See 'system_health' below.
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
      'astro' => { type: :json_text, values: nil },
      'classification_banner' => { type: :json_text, values: nil },
      'context_tag' => { type: :json_text, values: nil },
      # Settings with no Admin Console tab of their own - see NO_ADMIN_TAB below
      #
      # Written as JSON text by ScopeModel#seed_database and re-read by the
      # Enterprise metrics microservices. require_keys because a partial blob
      # doesn't degrade gracefully: log_thresholds does
      # data['global']['enableAlerts'] and passes data[metric_name] straight to
      # check_persistent_threshold, so a blob missing either key raises rather
      # than falling back, silently ending CPU/memory/disk alerting.
      'system_health' => { type: :json_text, values: nil,
                           require_keys: ['cpu', 'memory', 'disk', 'global'] },
      # Enterprise AI chat provider/model config. :json, not :json_text -
      # AiChatConfig.load ignores a String and falls back to {}
      'ai_chat_config' => { type: :json, values: nil },
    }

    # Settings that KNOWN_SETTINGS lists on purpose despite having no
    # *Settings.vue tab in this repo. The drift specs compare KNOWN_SETTINGS
    # against those components, so without this list adding either of these
    # would fail the "doesn't list a setting the Admin Console no longer has"
    # check. Both are real settings that code reads.
    NO_ADMIN_TAB = ['system_health', 'ai_chat_config']

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
    # Nothing here aborts init by default. A bad setting name, a bad value, or a
    # malformed control variable is reported on stdout and that one setting is
    # skipped, leaving COSMOS on its built-in default. Set STRICT_ENV_VAR to
    # fail init instead; --dry-run always fails.
    #
    # @param env [Hash] environment to read from, defaults to ENV
    # @param overwrite [Boolean, nil] nil reads OVERWRITE_ENV_VAR from env
    # @param strict [Boolean, nil] nil reads STRICT_ENV_VAR from env
    # @param dry_run [Boolean] report what would happen and write nothing.
    #   Reports every problem rather than aborting on the first, and works
    #   before Redis is up so it can be run ahead of starting COSMOS.
    # @return [Array<String>] names of the settings that were written
    def self.apply_defaults(env: ENV, overwrite: nil, dry_run: false, strict: nil)
      problems = []
      strict = read_control_flag(env, STRICT_ENV_VAR, problems) if strict.nil?
      overwrite = read_control_flag(env, OVERWRITE_ENV_VAR, problems) if overwrite.nil?
      allow_unknown = read_control_flag(env, ALLOW_UNKNOWN_ENV_VAR, problems)
      # Collects a value that can't be coerced, so OPENC3_SETTING_AI_CHAT=nope is
      # reported like any other bad value rather than escaping as an exception
      settings = parse_defaults_env(env, problems)

      prefix = dry_run ? '[dry run] ' : ''
      written = []
      if settings.empty?
        puts "#{prefix}No #{SETTING_ENV_PREFIX}* environment variables set - nothing to seed"
      else
        # A dry run is most useful before `openc3.sh start`, when there is no
        # Redis to compare against. Names and values can still be checked.
        comparable = dry_run ? redis_available? : true
        puts "#{prefix}Redis is not reachable - checking names and values only" unless comparable

        settings.each do |name, value|
          begin
            validate_setting!(name, value, allow_unknown: allow_unknown)
          rescue StandardError => error
            # Collect rather than abort. The init container restarts on failure
            # (compose restart: on-failure, Kubernetes restartPolicy OnFailure),
            # so raising here puts COSMOS in a crash loop over a cosmetic
            # setting, with the cause buried in restarting container logs.
            # Skipping leaves the setting at its default, which is the same
            # outcome as not setting it, and the error is reported below.
            problems << error.message
            next
          end

          existing = comparable ? get(name: name) : nil
          action, message = plan_setting(name, value, existing, overwrite)
          message += ' (current value unknown)' unless comparable
          puts "#{prefix}#{message}"
          next if action == :skip

          # :record leaves the setting alone and only refreshes provenance, so it
          # is not reported as written
          written << name if action == :write
          next if dry_run
          set({ name: name, data: value }, scope: nil) if action == :write
          record_seeded(name, value)
        end
      end

      report_problems(problems, prefix: prefix, dry_run: dry_run, strict: strict)
      written
    end

    # Print every problem and decide whether it should end the process.
    #
    # A typo in a cosmetic setting must not put the init container in a restart
    # loop with the cause buried in restarting container logs, so the default is
    # report-and-continue. Two things opt into failing: --dry-run, which exists
    # to be a preflight gate, and STRICT_ENV_VAR, for a deployment that would
    # rather not come up at all than come up misconfigured.
    def self.report_problems(problems, prefix:, dry_run:, strict:)
      return if problems.empty?
      problems.each { |problem| puts "#{prefix}ERROR: #{problem}" }
      # "problem" rather than "setting" - a malformed control variable is
      # reported here too, and it isn't a setting that got skipped
      summary = "#{problems.length} #{SETTING_ENV_PREFIX}* configuration problem(s)"
      if dry_run or strict
        puts "#{prefix}#{summary}"
      else
        puts "#{prefix}#{summary} - the affected setting(s) were skipped and COSMOS will use the default"
        puts "#{prefix}Set #{STRICT_ENV_VAR} to fail init on these instead of continuing"
      end
      $stdout.flush
      raise "#{summary}: #{problems.join('; ')}" if dry_run or strict
    end

    # Read a boolean control variable, reporting an unparsable value rather than
    # letting it abort init. Off is the safe reading of all three: OVERWRITE off
    # doesn't discard an Admin Console edit, ALLOW_UNKNOWN off doesn't write a
    # name nothing reads, and STRICT off doesn't fail init.
    #
    # @param problems [Array<String>] collects the message when the value is bad
    # @return [Boolean]
    def self.read_control_flag(env, name, problems)
      truthy_env?(env, name)
    rescue StandardError => error
      problems << "#{error.message} - treating #{name} as off"
      false
    end

    # What apply_defaults will do with one setting. Single-sourced so a dry run
    # cannot report one thing and the real run do another.
    #
    # @return [Array(Symbol, String)] :write, :record or :skip, and the line to
    #   log. :record means the stored value is already correct but provenance
    #   still needs writing, so the setting itself is left untouched.
    def self.plan_setting(name, value, existing, overwrite)
      if existing.nil?
        [:write, "Set default setting '#{name}' to: #{value.inspect}"]
      elsif overwrite
        if existing['data'] == value
          # Rewriting the same value would bump updated_at on every init and
          # report a write that changed nothing. Provenance is still recorded,
          # so the next run without OVERWRITE can tell this value came from the
          # environment rather than from an Admin Console edit.
          [:record, "Setting '#{name}' already matches #{value.inspect}"]
        else
          # Overwrite discards an Admin Console edit, so say what was lost -
          # otherwise the log reads identically to a first-time seed
          [:write, "Overwriting setting '#{name}': #{existing['data'].inspect} -> " \
                   "#{value.inspect} (#{OVERWRITE_ENV_VAR} is set)"]
        end
      elsif !seeded_value?(name, existing['data'])
        [:skip, "Setting '#{name}' was changed from the seeded value - leaving as #{existing['data'].inspect}"]
      elsif existing['data'] == value
        [:skip, "Setting '#{name}' already matches #{value.inspect} - leaving unchanged"]
      else
        [:write, "Updating unedited setting '#{name}': #{existing['data'].inspect} -> #{value.inspect}"]
      end
    end

    def self.redis_available?
      names()
      true
    rescue StandardError
      false
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
    # @param problems [Array<String>] collects a value that can't be coerced, so
    #   OPENC3_SETTING_AI_CHAT=nope is reported and skipped alongside every other
    #   bad value rather than escaping as an exception and aborting init
    # @return [Hash] setting name => coerced value
    def self.parse_defaults_env(env, problems = [])
      settings = {}
      env.each do |key, value|
        key = to_str(key)
        next unless key.start_with?(SETTING_ENV_PREFIX)
        name = key[SETTING_ENV_PREFIX.length..-1].downcase
        next if name.empty?
        begin
          settings[name] = coerce(name, to_str(value))
        rescue StandardError => error
          problems << error.message
        end
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
      case KNOWN_SETTINGS.dig(name, :type)
      when :boolean
        ConfigParser.handle_true_false_strict(value, description: "setting '#{name}'")
      when :json
        # Parsed, because this setting's reader checks for an object and
        # discards text. Validated here so a malformed blob is reported at seed
        # time rather than read back as a default nobody asked for.
        parse_json!(name, value)
      when :json_text
        # Kept as text, but parsed anyway to prove it is valid - the component
        # that JSON.parses it has no way to report a failure
        parse_json!(name, value)
        value
      else
        value
      end
    end

    # @return [Object] the parsed blob
    # @raise [RuntimeError] when the value isn't a JSON object with the keys the
    #   setting's reader requires
    def self.parse_json!(name, value)
      parsed = JSON.parse(value)
      unless parsed.is_a?(Hash)
        raise "Value for setting '#{name}' must be a JSON object, got #{parsed.class}"
      end
      required = KNOWN_SETTINGS.dig(name, :require_keys)
      if required
        missing = required - parsed.keys
        unless missing.empty?
          raise "Value for setting '#{name}' is missing required key(s): #{missing.join(', ')}. " \
                "Seed the whole object - a partial one breaks the code that reads it"
        end
      end
      parsed
    rescue JSON::ParserError => error
      raise "Value for setting '#{name}' is not valid JSON: #{error.message}"
    end

    # Largest value we will write. Settings are read into every browser tab, so
    # this is a guard against an env var that is a file by mistake rather than a
    # real limit - the biggest real setting is a few hundred bytes.
    MAX_VALUE_BYTES = 64 * 1024

    # Raise on anything we can prove is wrong, so the operator is told rather
    # than left with a tool silently falling back to its built-in default.
    #
    # Raising here does NOT abort init: apply_defaults collects the message,
    # skips that one setting and keeps going, because crash-looping the init
    # container over a cosmetic setting would be worse than using the default.
    # `initsettings --dry-run` is the mode that exits non-zero.
    def self.validate_setting!(name, value, allow_unknown: false)
      unless name =~ /\A[a-z0-9_]+\z/
        raise "Invalid setting name #{name.inspect}. Names must be lowercase letters, numbers and underscores"
      end

      unless KNOWN_SETTINGS.key?(name)
        unless allow_unknown
          # Period here, not on the suggestion - without a near match the
          # sentence used to run straight into "Set OPENC3_SETTINGS_ALLOW_UNKNOWN"
          message = "'#{name}' is not a known COSMOS setting."
          suggestion = KNOWN_SETTINGS.keys.find { |known| near_match?(known, name) }
          message += " Did you mean '#{suggestion}'?" if suggestion
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
                  else
                    case details[:type]
                    when :boolean then '1, true, 0, false'
                    when :json, :json_text
                      keys = details[:require_keys]
                      keys ? "JSON object with keys: #{keys.join(', ')}" : 'JSON object'
                    else 'any text'
                    end
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
