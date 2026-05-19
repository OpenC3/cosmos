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

module OpenC3
  class CliGenerator
    GENERATORS = %w(plugin target microservice widget conversion processor limits_response tool tool_vue tool_angular tool_react tool_svelte command_validator)
    TEMPLATES_DIR = "#{File.dirname(__FILE__)}/../../../templates"

    # Generators that derive language from the target's target.txt
    TARGET_DERIVED_GENERATORS = %w(conversion processor limits_response command_validator).freeze
    # Generators that are JavaScript-only and ignore language flags
    JS_ONLY_GENERATORS = %w(widget tool tool_vue tool_angular tool_react tool_svelte).freeze
    # Generators that require an explicit language (or env/plugin default)
    LANGUAGE_REQUIRED_GENERATORS = %w(target microservice).freeze

    # Called by openc3cli with ARGV[1..-1]
    def self.generate(args)
      if args[0].nil? || args[0] == '--help' || args[0] == '-h'
        puts "Usage: cli generate GENERATOR [ARGS...] [--ruby | --python]"
        puts ""
        puts "Generate COSMOS components from templates"
        puts ""
        puts "Available Generators:"
        puts "  plugin                Create a new COSMOS plugin (--ruby/--python optional, sets plugin default)"
        puts "  target                Create a new target within a plugin (--ruby/--python required or inherited)"
        puts "  microservice          Create a new microservice within a plugin (--ruby/--python required or inherited)"
        puts "  widget                Create a new custom widget (JavaScript only)"
        puts "  conversion            Create a new conversion class for a target (language inherited from target)"
        puts "  processor             Create a new processor for a target (language inherited from target)"
        puts "  limits_response       Create a new limits response for a target (language inherited from target)"
        puts "  command_validator     Create a new command validator for a target (language inherited from target)"
        puts "  tool                  Create a new tool, Vue.js by default (JavaScript only)"
        puts "  tool_vue              Create a new Vue.js tool (JavaScript only)"
        puts "  tool_angular          Create a new Angular tool (JavaScript only)"
        puts "  tool_react            Create a new React tool (JavaScript only)"
        puts "  tool_svelte           Create a new Svelte tool (JavaScript only)"
        puts ""
        puts "Run 'cli generate GENERATOR --help' for detailed help on each generator."
        puts ""
        puts "Language Resolution (for target/microservice):"
        puts "  1. --ruby or --python flag"
        puts "  2. OPENC3_LANGUAGE environment variable"
        puts "  3. '# LANGUAGE ruby|python' comment in plugin.txt (set by 'generate plugin --ruby/--python')"
        puts ""
        puts "Options:"
        puts "  --ruby                Generate Ruby code"
        puts "  --python              Generate Python code"
        puts "  -h, --help            Show this help message"
        puts ""
        puts "Examples:"
        puts "  cli generate plugin MyPlugin --ruby     # Plugin defaults future generators to Ruby"
        puts "  cli generate target EXAMPLE --python    # Or inherit from plugin's stored default"
        puts "  cli generate widget SuperdataWidget     # No language flag needed"
        puts "  cli generate conversion EXAMPLE STATUS  # Language read from targets/EXAMPLE/target.txt"
        puts ""
        puts "Documentation:"
        puts "  https://docs.openc3.com/docs/development/developing"
        exit(args[0].nil? ? 1 : 0)
      end
      unless GENERATORS.include?(args[0])
        abort("Unknown generator '#{args[0]}'. Valid generators: #{GENERATORS.join(', ')}")
      end
      # Skip argument validation if user is requesting help
      unless args[1] == '--help' || args[1] == '-h'
        check_args(args)
      end
      send("generate_#{args[0].to_s.downcase.gsub('-', '_')}", args)
    end

    # Strip --ruby/--python tokens from args and return the resolved language ('rb'/'py'/nil).
    # Aborts if both flags are supplied. Aborts if a language flag appears before the NAME
    # positional arg (i.e. stripping flags would leave the generator with no NAME).
    def self.extract_language!(args)
      generator = args[0]
      lang_flags = []
      flag_indices = []
      args.each_with_index do |arg, idx|
        next if idx == 0 # don't touch the generator name itself
        if arg == '--ruby' || arg == '--python'
          lang_flags << arg
          flag_indices << idx
        end
      end

      if lang_flags.size > 1 && lang_flags.uniq.size > 1
        abort("Cannot specify both --ruby and --python.")
      end

      # If a language flag is present but no positional NAME follows the generator name,
      # the user wrote something like `cli generate plugin --python`. Abort with guidance.
      unless flag_indices.empty?
        first_flag_idx = flag_indices.min
        has_positional_name = args[1...first_flag_idx].any? { |a| a != '--ruby' && a != '--python' }
        unless has_positional_name
          abort("NAME must come before the language flag. Example: cli generate #{generator} MyName #{lang_flags.first}")
        end
      end

      # Remove flag tokens from args in-place so downstream argument-position checks work.
      flag_indices.reverse_each { |i| args.delete_at(i) }

      case lang_flags.first
      when '--python' then 'py'
      when '--ruby' then 'rb'
      else nil
      end
    end

    # Read the '# LANGUAGE ruby|python' comment from plugin.txt in the current directory.
    # Returns 'rb', 'py', or nil if the file or comment is absent.
    def self.read_plugin_language
      return nil unless File.exist?('plugin.txt')
      File.foreach('plugin.txt') do |line|
        if line =~ /^\s*#\s*LANGUAGE\s+(ruby|python)\b/i
          return $1.downcase == 'python' ? 'py' : 'rb'
        end
      end
      nil
    end

    # Convert OPENC3_LANGUAGE env var to 'rb'/'py' or nil.
    def self.env_language
      case ENV['OPENC3_LANGUAGE']
      when 'python' then 'py'
      when 'ruby' then 'rb'
      else nil
      end
    end

    # Argument validation + language resolution dispatch.
    # After this returns, args no longer contains --ruby/--python tokens and
    # @@language is set (except for generators that resolve language later,
    # like target-derived ones that read target.txt).
    def self.check_args(args)
      generator = args[0]
      explicit_lang = extract_language!(args)

      args.each do |arg|
        if arg =~ /\s/ and generator.to_s.downcase[0..3] != 'tool'
          abort("#{generator.to_s.downcase} arguments can not have spaces!")
        end
      end
      # All generators except 'plugin' must be within an existing plugin
      if generator != 'plugin' and Dir.glob("*.gemspec").empty?
        abort("No gemspec file detected. #{generator.to_s.downcase} generator should be run within an existing plugin.")
      end

      if JS_ONLY_GENERATORS.include?(generator)
        if explicit_lang
          puts "Note: --ruby/--python is ignored for the #{generator} generator (JavaScript only)."
        end
        # JS generators don't write any .rb/.py files but process_template still
        # filters by @@language; set to 'rb' as a harmless default.
        @@language = 'rb'
      elsif TARGET_DERIVED_GENERATORS.include?(generator)
        if explicit_lang
          puts "Note: --ruby/--python is ignored for the #{generator} generator (language is inherited from the target's target.txt)."
        end
        # @@language is set later by the generator after it locates target.txt.
        # Default to 'rb' here so any pre-target validation doesn't blow up.
        @@language = 'rb'
      elsif LANGUAGE_REQUIRED_GENERATORS.include?(generator)
        gen_lang = explicit_lang || env_language || read_plugin_language
        unless gen_lang
          abort("Language required for #{generator} generator. Pass --ruby or --python, set OPENC3_LANGUAGE, or add '# LANGUAGE ruby|python' to plugin.txt (the plugin generator does this automatically when given --ruby/--python).")
        end
        @@language = gen_lang
      else # plugin
        @@language = explicit_lang || env_language
        # nil is allowed for plugin; templates are language-agnostic at the plugin level.
      end
    end

    # Shared structure for every per-generator help block. Pass a hash with the
    # generator's usage line, description, arg/option/example lines, etc.
    # See generate_plugin / generate_target_artifact for examples.
    def self.print_help(opts)
      puts "Usage: #{opts[:usage]}"
      puts ""
      puts opts[:description]
      puts ""
      puts "Arguments:"
      opts.fetch(:arguments, []).each { |line| puts "  #{line}" }
      puts ""
      puts "Options:"
      opts.fetch(:options, []).each { |line| puts "  #{line}" }
      puts "  -h, --help        Show this help message"
      Array(opts[:notes]).each do |note|
        puts ""
        puts note
      end
      if opts[:language_defaults]
        puts ""
        puts "Language Defaults (used when --ruby/--python is not given):"
        opts[:language_defaults].each { |line| puts "  #{line}" }
      end
      if opts[:extra_section]
        puts ""
        puts "#{opts[:extra_section][:title]}:"
        opts[:extra_section][:lines].each { |line| puts "  #{line}" }
      end
      puts ""
      puts "Example:"
      Array(opts[:example]).each { |line| puts line.empty? ? "" : "  #{line}" }
      unless opts[:is_plugin]
        puts ""
        puts "Note: Must be run from within an existing plugin directory"
        Array(opts[:in_plugin_extra]).each { |line| puts "      #{line}" }
      end
      puts ""
      puts "Documentation:"
      puts "  #{opts[:docs]}"
      exit(opts[:exit_code])
    end

    # Single implementation backing the four target-derived generators.
    def self.generate_target_artifact(args, config)
      generator = args[0]
      if args[1].nil? || args[2].nil? || args[1] == '--help' || args[1] == '-h'
        print_help(
          usage: "cli generate #{generator} TARGET NAME",
          description: "Generate a new #{config[:kind].downcase} for an existing target",
          arguments: [
            'TARGET            Target name (required, must exist)',
            "NAME              #{config[:kind]} name (required)",
            "                  Will be uppercased with '_#{config[:suffix]}' suffix",
          ],
          notes: [
            "Note: Language is inherited from the target's target.txt (LANGUAGE keyword).",
            '      --ruby/--python flags are ignored.',
          ],
          example: [
            "cli generate #{generator} EXAMPLE #{config[:help_example]}",
            "Creates: targets/EXAMPLE/lib/#{config[:help_example].downcase}_#{generator}.rb (or .py)",
          ],
          docs: config[:docs],
          exit_code: (args[1].nil? || args[2].nil? ? 1 : 0),
        )
      end
      if args.length != 3
        abort("Usage: cli generate #{generator} <TARGET> <NAME>")
      end

      target_name = args[1].upcase
      target_path = "targets/#{target_name}"
      unless File.exist?(target_path)
        abort("Target '#{target_name}' does not exist! #{config[:kind_plural]} must be created for existing targets.")
      end
      @@language = read_target_language(target_path)

      artifact_name = "#{args[2].upcase.gsub(/_+|-+/, '_')}_#{config[:suffix]}"
      basename = "#{artifact_name.downcase}.#{@@language}"
      filename = "#{target_path}/lib/#{basename}"

      if File.exist?(filename)
        abort("#{config[:kind]} #{filename} already exists!")
      end

      # Bind the class name to the template-specific local-variable name
      # (e.g. conversion_class, processor_class) so the ERB templates resolve it.
      template_binding = binding
      template_binding.local_variable_set(config[:class_var].to_sym, basename.filename_to_class_name)

      template_source = "#{config[:template_source]}.#{@@language}"
      process_template("#{TEMPLATES_DIR}/#{config[:template]}", template_binding) do |fname|
        fname.sub!(template_source, filename)
        false
      end

      puts "#{config[:kind]} #{filename} successfully generated!"
      puts config[:usage_intro]
      directive = config[:usage_directive] % { basename: basename, name_upcase: args[2].upcase }
      puts "  #{directive}"
      artifact_name
    end

    # Read 'LANGUAGE ruby|python' from a target's target.txt. Aborts if missing.
    def self.read_target_language(target_path)
      target_txt = "#{target_path}/target.txt"
      unless File.exist?(target_txt)
        abort("Could not find #{target_txt} to determine target language.")
      end
      File.foreach(target_txt) do |line|
        if line =~ /^\s*LANGUAGE\s+(ruby|python)\b/i
          return $1.downcase == 'python' ? 'py' : 'rb'
        end
      end
      abort("No LANGUAGE keyword found in #{target_txt}. Add 'LANGUAGE ruby' or 'LANGUAGE python' to determine the language for generated files.")
    end

    def self.process_template(template_dir, the_binding)
      Dir.glob("#{template_dir}/**/*", File::FNM_DOTMATCH).each do |file|
        next if File.basename(file) == '.'
        # When @@language is nil (plugin generation with no language specified),
        # don't filter — let all template files through.
        if @@language == 'rb' and File.extname(file) == '.py'
          # Ignore python files if we're ruby
          next
        elsif @@language == 'py' and File.extname(file) == '.rb'
          # Ignore ruby files if we're python
          next
        end
        base_name = file.sub("#{template_dir}/", '')
        next if yield base_name
        if File.directory?(file)
          FileUtils.mkdir_p(base_name)
          next
        end
        output = ERB.new(File.read(file), trim_mode: "-").result(the_binding)
        File.open(base_name, 'w') do |base_file|
          base_file.write output
        end
      end
    end

    def self.generate_plugin(args)
      if args[1].nil? || args[1] == '--help' || args[1] == '-h'
        print_help(
          usage: 'cli generate plugin NAME [--ruby | --python]',
          description: 'Generate a new COSMOS plugin',
          arguments: [
            'NAME              Name of the plugin (required)',
            "                  Will be prefixed with 'openc3-cosmos-'",
            '                  Spaces, underscores, and hyphens will be converted to hyphens',
          ],
          options: [
            "--ruby            Set the plugin's default language to Ruby. Subsequent",
            "                  'cli generate target/microservice' invocations inside this",
            '                  plugin will default to Ruby. Recorded as a',
            "                  '# LANGUAGE ruby' comment in plugin.txt.",
            '--python          Same as --ruby, but sets the default to Python.',
          ],
          example: [
            'cli generate plugin demo --ruby',
            "Creates: openc3-cosmos-demo/ with '# LANGUAGE ruby' in plugin.txt",
            '',
            'cli generate plugin demo',
            'Creates: openc3-cosmos-demo/ with no language default',
          ],
          is_plugin: true,
          docs: 'https://docs.openc3.com/docs/configuration/plugins',
          exit_code: (args[1].nil? ? 1 : 0),
        )
      end
      if args.length < 2 or args.length > 2
        abort("Usage: cli generate #{args[0]} <NAME> [--ruby | --python]")
      end

      # Create the local variables that are used in process_template below (see openc3/templates/plugin/plugin.gemspec as an example)
      plugin_orig = args[1]
      plugin = plugin_orig.downcase.gsub(/_+|-+/, '-')
      plugin_name = "openc3-cosmos-#{plugin}"
      if File.exist?(plugin_name)
        abort("Plugin #{plugin_name} already exists!")
      end
      FileUtils.mkdir(plugin_name)
      Dir.chdir(plugin_name) # Change to the plugin path to make copying easier

      process_template("#{TEMPLATES_DIR}/plugin", binding) do |filename|
        filename.sub!("plugin.gemspec", "#{plugin_name}.gemspec")
        false
      end

      # If a language was specified, persist it in plugin.txt so future target /
      # microservice generators can default to it.
      if @@language
        lang_word = (@@language == 'py') ? 'python' : 'ruby'
        existing = File.exist?('plugin.txt') ? File.read('plugin.txt') : ''
        File.open('plugin.txt', 'w') do |file|
          file.puts "# LANGUAGE #{lang_word}"
          file.write(existing)
        end
      end

      puts "Plugin #{plugin_name} successfully generated!"
      return plugin_name
    end

    def self.generate_target(args)
      if args[1].nil? || args[1] == '--help' || args[1] == '-h'
        print_help(
          usage: 'cli generate target NAME [--ruby | --python]',
          description: 'Generate a new target within an existing plugin',
          arguments: [
            'NAME              Name of the target (required)',
            '                  Will be uppercased and underscores/hyphens converted to underscores',
          ],
          options: [
            '--ruby            Generate Ruby target (optional)',
            '--python          Generate Python target (optional)',
          ],
          language_defaults: [
            '1. OPENC3_LANGUAGE environment variable',
            "2. '# LANGUAGE ruby|python' comment in plugin.txt",
          ],
          example: [
            'cli generate target EXAMPLE --ruby',
            'Creates: targets/EXAMPLE/',
          ],
          docs: 'https://docs.openc3.com/docs/configuration/target',
          exit_code: (args[1].nil? ? 1 : 0),
        )
      end
      if args.length != 2
        abort("Usage: cli generate #{args[0]} <NAME> [--ruby | --python]")
      end

      # Create the local variables
      target_name = args[1].upcase.gsub(/_+|-+/, '_')
      target_path = "targets/#{target_name}"
      if File.exist?(target_path)
        abort("Target #{target_path} already exists!")
      end
      target_lib_filename = "#{target_name.downcase}.#{@@language}"
      target_class = target_lib_filename.filename_to_class_name
      target_object = target_name.downcase
      target_class.inspect # Remove unused variable warning. These are used in binding for generator
      target_object.inspect # Remove unused variable warning. These are used in binding for generator

      process_template("#{TEMPLATES_DIR}/target", binding) do |filename|
        # Rename the template TARGET to our actual target named after the plugin
        filename.sub!("targets/TARGET", "targets/#{target_name}")
        filename.sub!("target.#{@@language}", target_lib_filename)
        false
      end

      if @@language == 'py'
        # If we're using Python create a requirements.txt and list it in the gemspec
        # However, don't write over an existing file they may have already created
        unless File.exist?("requirements.txt")
          File.open("requirements.txt", 'w') do |file|
            file.puts "# Python dependencies"
          end
        end
        gemspec_filename = Dir['*.gemspec'][0]
        gemspec = File.read(gemspec_filename)
        gemspec.gsub!(/s\.files = Dir\.glob.*\n/) do |match|
          <<RUBY
# Prefer pyproject.toml over requirements.txt
  python_dep_file = if File.exist?('pyproject.toml')
    'pyproject.toml'
  else
    'requirements.txt'
  end
  s.files = Dir.glob("{targets,lib,public,tools,microservices}/**/*") + %w(Rakefile README.md LICENSE.md plugin.txt) + [python_dep_file]
RUBY
        end
        File.write(gemspec_filename, gemspec)

        target_txt_filename = "targets/#{target_name}/target.txt"
        target_txt = File.read(target_txt_filename)
        target_txt.gsub!('LANGUAGE ruby', 'LANGUAGE python')
        File.write(target_txt_filename, target_txt)
      end

      interface_line = "INTERFACE <%= #{target_name.downcase}_target_name %>_INT tcpip_client_interface.rb host.docker.internal 8080 8081 10.0 nil BURST"
      if @@language == 'py'
        interface_line = "INTERFACE <%= #{target_name.downcase}_target_name %>_INT openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8081 10.0 None BURST"
      end

      # Add this target to plugin.txt
      File.open("plugin.txt", 'a') do |file|
        file.puts <<~DOC

          VARIABLE #{target_name.downcase}_target_name #{target_name}

          TARGET #{target_name} <%= #{target_name.downcase}_target_name %>
          #{interface_line}
            MAP_TARGET <%= #{target_name.downcase}_target_name %>
        DOC
      end

      puts "Target #{target_name} successfully generated!"
      return target_name
    end

    def self.generate_microservice(args)
      if args[1].nil? || args[1] == '--help' || args[1] == '-h'
        print_help(
          usage: 'cli generate microservice NAME [--ruby | --python]',
          description: 'Generate a new microservice within an existing plugin',
          arguments: [
            'NAME              Name of the microservice (required)',
            '                  Will be uppercased and underscores/hyphens converted to underscores',
          ],
          options: [
            '--ruby            Generate Ruby microservice (optional)',
            '--python          Generate Python microservice (optional)',
          ],
          language_defaults: [
            '1. OPENC3_LANGUAGE environment variable',
            "2. '# LANGUAGE ruby|python' comment in plugin.txt",
          ],
          example: [
            'cli generate microservice DATA_PROCESSOR --ruby',
            'Creates: microservices/DATA_PROCESSOR/',
          ],
          docs: 'https://docs.openc3.com/docs/configuration/plugins#microservices',
          exit_code: (args[1].nil? ? 1 : 0),
        )
      end
      if args.length != 2
        abort("Usage: cli generate #{args[0]} <NAME> [--ruby | --python]")
      end

      # Create the local variables
      microservice_name = args[1].upcase.gsub(/_+|-+/, '_')
      microservice_path = "microservices/#{microservice_name}"
      if File.exist?(microservice_path)
        abort("Microservice #{microservice_path} already exists!")
      end
      # plugin.txt is checked separately because the user may have deleted the
      # microservices/NAME directory without cleaning up the plugin.txt entry.
      # A duplicate MICROSERVICE entry causes plugin install to fail with
      # "openc3_microservices:...already exists at create".
      if File.exist?('plugin.txt') && File.read('plugin.txt') =~ /^MICROSERVICE\s+#{Regexp.escape(microservice_name)}\b/
        abort("plugin.txt already declares MICROSERVICE #{microservice_name}. Remove that entry before regenerating.")
      end
      microservice_filename = "#{microservice_name.downcase}.#{@@language}"
      microservice_class = microservice_filename.filename_to_class_name
      microservice_class.inspect # Remove unused variable warning. These are used in binding for generator

      process_template("#{TEMPLATES_DIR}/microservice", binding) do |filename|
        # Rename the template MICROSERVICE to our actual microservice name
        filename.sub!("microservices/TEMPLATE", "microservices/#{microservice_name}")
        filename.sub!("microservice.#{@@language}", microservice_filename)
        false
      end

      cmd_line = "CMD ruby #{microservice_name.downcase}.rb"
      if @@language == 'py'
        cmd_line = "CMD python #{microservice_name.downcase}.py"
      end

      # Add this microservice to plugin.txt
      File.open("plugin.txt", 'a') do |file|
        file.puts <<~DOC

          MICROSERVICE #{microservice_name} #{microservice_name.downcase.gsub('_','-')}-microservice
            #{cmd_line}
        DOC
      end

      puts "Microservice #{microservice_name} successfully generated!"
      return microservice_name
    end

    def self.generate_widget(args)
      if args[1].nil? || args[1] == '--help' || args[1] == '-h'
        print_help(
          usage: 'cli generate widget NAME',
          description: 'Generate a new custom Vue.js widget within an existing plugin',
          arguments: [
            'NAME              Name of the widget (required)',
            "                  Must be CapitalCase ending with 'Widget'",
            '                  Example: SuperdataWidget, StatusWidget',
          ],
          notes: 'Note: Widgets are JavaScript only. --ruby/--python flags are ignored.',
          example: [
            'cli generate widget SuperdataWidget',
            'Creates: src/SuperdataWidget.vue',
          ],
          docs: 'https://docs.openc3.com/docs/guides/custom-widgets',
          exit_code: (args[1].nil? ? 1 : 0),
        )
      end
      if args.length != 2
        abort("Usage: cli generate #{args[0]} <SuperdataWidget>")
      end
      # Per https://stackoverflow.com/a/47591707/453280
      if args[1] !~ /.*Widget$/ or args[1][0...-6] != args[1][0...-6].capitalize
        abort("Widget name should be Uppercase followed by Widget, e.g. SuperdataWidget. Found '#{args[1]}'.")
      end

      # Create the local variables
      widget_name = args[1]
      widget_filename = "#{widget_name}.vue"
      widget_path = "src/#{widget_filename}"
      if File.exist?(widget_path)
        abort("Widget #{widget_path} already exists!")
      end
      skip_package = false
      if File.exist?('package.json')
        puts "package.json already exists ... you'll have to manually add this widget to the end of the \"build\" script."
        skip_package = true
      end

      process_template("#{TEMPLATES_DIR}/widget", binding) do |filename|
        if skip_package && filename == 'package.json'
          true # causes the block to skip processing this file
        elsif filename.include?('node_modules')
          true
        else
          filename.sub!("Widget.vue", widget_filename)
          false
        end
      end

      # Add this widget to plugin.txt but remove Widget from the name
      File.open("plugin.txt", 'a') do |file|
        file.puts <<~DOC

          WIDGET #{widget_name[0...-6]}
        DOC
      end

      puts "Widget #{widget_name} successfully generated!"
      puts "Please be sure #{widget_name} does not overlap an existing widget: https://docs.openc3.com/docs/configuration/telemetry-screens"
      return widget_name
    end

    def self.generate_tool(args)
      if args[1].nil? || args[1] == '--help' || args[1] == '-h'
        tool_type = args[0].to_s.downcase.gsub('-', '_')
        common_args = [
          'TOOL NAME         Display name of the tool (required, can include spaces)',
          '                  Will be converted to lowercase without spaces for directory name',
        ]
        common_note = 'Note: Tools are JavaScript only. --ruby/--python flags are ignored.'
        docs_url = 'https://docs.openc3.com/docs/guides/custom-tools'

        if tool_type != 'tool'
          framework = case tool_type
                      when 'tool_vue' then 'Vue.js'
                      when 'tool_react' then 'React'
                      when 'tool_angular' then 'Angular'
                      when 'tool_svelte' then 'Svelte'
                      else 'Custom'
                      end
          print_help(
            usage: "cli generate #{args[0]} 'TOOL NAME'",
            description: "Generate a new #{framework} tool within an existing plugin",
            arguments: common_args,
            notes: common_note,
            example: [
              "cli generate #{args[0]} 'Data Viewer'",
              "Creates: tools/dataviewer/ (#{framework}-based)",
            ],
            in_plugin_extra: 'For other tool types, see: cli generate tool --help',
            docs: docs_url,
            exit_code: (args[1].nil? ? 1 : 0),
          )
        else
          print_help(
            usage: "cli generate #{args[0]} 'TOOL NAME'",
            description: 'Generate a new custom tool within an existing plugin',
            arguments: common_args,
            notes: common_note,
            extra_section: {
              title: 'Tool Types',
              lines: [
                'tool              Generate Vue.js tool (default)',
                'tool_vue          Generate Vue.js tool',
                'tool_angular      Generate Angular tool',
                'tool_react        Generate React tool',
                'tool_svelte       Generate Svelte tool',
              ],
            },
            example: [
              "cli generate tool 'Data Viewer'",
              'Creates: tools/dataviewer/',
            ],
            docs: docs_url,
            exit_code: (args[1].nil? ? 1 : 0),
          )
        end
      end
      if args.length != 2
        abort("Usage: cli generate #{args[0]} 'Tool Name'")
      end

      # Create the local variables
      tool_type = args[0].to_s.downcase.gsub('-', '_')
      tool_type = 'tool_vue' if tool_type == 'tool'
      tool_name_display = args[1]
      tool_name = args[1].to_s.downcase.gsub('-', '').gsub(' ', '')
      tool_path = "tools/#{tool_name}"
      if File.exist?(tool_path)
        abort("Tool #{tool_path} already exists!")
      end
      skip_package = false
      if File.exist?('package.json')
        puts "package.json already exists ... you'll have to manually add this tool and its dependencies"
        skip_package = true
      end

      process_template("#{TEMPLATES_DIR}/#{tool_type}", binding) do |filename|
        if skip_package && filename == 'package.json'
          true # causes the block to skip processing this file
        elsif filename.include?('node_modules')
          true
        else
          filename.gsub!("tool_name", tool_name)
          false
        end
      end

      # Add this tool to plugin.txt
      js_file = 'main.js'
      File.open("plugin.txt", 'a') do |file|
        file.puts <<~DOC

        TOOL #{tool_name} "#{tool_name_display}"
          INLINE_URL #{js_file}
          ICON mdi-file-cad-box
        DOC
      end

      puts "Tool #{tool_name} successfully generated!"
      puts "Please be sure #{tool_name} does not conflict with any other tools"
      return tool_name
    end
    self.singleton_class.send(:alias_method, :generate_tool_vue, :generate_tool)
    self.singleton_class.send(:alias_method, :generate_tool_react, :generate_tool)
    self.singleton_class.send(:alias_method, :generate_tool_angular, :generate_tool)
    self.singleton_class.send(:alias_method, :generate_tool_svelte, :generate_tool)

    def self.generate_conversion(args)
      generate_target_artifact(args, {
        suffix: 'CONVERSION',
        kind: 'Conversion',
        kind_plural: 'Conversions',
        template: 'conversion',
        template_source: 'conversion', # template file is conversion.rb / conversion.py
        class_var: 'conversion_class',
        usage_intro: 'To use the conversion add the following to a telemetry item:',
        usage_directive: 'READ_CONVERSION %{basename}',
        docs: 'https://docs.openc3.com/docs/configuration/telemetry#read_conversion',
        help_example: 'STATUS',
      })
    end
    def self.generate_processor(args)
      generate_target_artifact(args, {
        suffix: 'PROCESSOR',
        kind: 'Processor',
        kind_plural: 'Processors',
        template: 'processor',
        template_source: 'processor',
        class_var: 'processor_class',
        usage_intro: 'To use the processor add the following to a telemetry packet:',
        usage_directive: 'PROCESSOR %{name_upcase} %{basename} <PARAMS...>',
        docs: 'https://docs.openc3.com/docs/configuration/telemetry#processor',
        help_example: 'DATA',
      })
    end
    def self.generate_limits_response(args)
      generate_target_artifact(args, {
        suffix: 'LIMITS_RESPONSE',
        kind: 'Limits response',
        kind_plural: 'Limits responses',
        template: 'limits_response',
        template_source: 'response', # template file is response.rb / response.py
        class_var: 'response_class',
        usage_intro: 'To use the limits response add the following to a telemetry item:',
        usage_directive: 'LIMITS_RESPONSE %{basename}',
        docs: 'https://docs.openc3.com/docs/configuration/telemetry#limits_response',
        help_example: 'CUSTOM',
      })
    end
    def self.generate_command_validator(args)
      generate_target_artifact(args, {
        suffix: 'COMMAND_VALIDATOR',
        kind: 'Command validator',
        kind_plural: 'Command validators',
        template: 'command_validator',
        template_source: 'command_validator',
        class_var: 'validator_class',
        usage_intro: 'To use the command validator add the following to a command:',
        usage_directive: 'VALIDATOR %{basename}',
        docs: 'https://docs.openc3.com/docs/configuration/command#validator',
        help_example: 'RANGE',
      })
    end
  end
end
