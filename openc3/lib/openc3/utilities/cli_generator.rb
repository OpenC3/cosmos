# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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

module OpenC3
  class CliGenerator
    GENERATORS = %w(plugin target microservice widget conversion processor limits_response tool tool_vue tool_angular tool_react tool_svelte command_validator)
    TEMPLATES_DIR = "#{File.dirname(__FILE__)}/../../../templates"

    # Called by openc3cli with ARGV[1..-1]
    def self.generate(args)
      if args[0].nil? || args[0] == '--help' || args[0] == '-h'
        puts "Usage: cli generate GENERATOR [ARGS...] (--ruby or --python)"
        puts ""
        puts "Generate COSMOS components from templates"
        puts ""
        puts "Available Generators:"
        puts "  plugin                Create a new COSMOS plugin"
        puts "  target                Create a new target within a plugin"
        puts "  microservice          Create a new microservice within a plugin"
        puts "  widget                Create a new custom widget"
        puts "  conversion            Create a new conversion class for a target"
        puts "  processor             Create a new processor for a target"
        puts "  limits_response       Create a new limits response for a target"
        puts "  command_validator     Create a new command validator for a target"
        puts "  tool                  Create a new tool (Vue.js by default)"
        puts "  tool_vue              Create a new Vue.js tool"
        puts "  tool_angular          Create a new Angular tool"
        puts "  tool_react            Create a new React tool"
        puts "  tool_svelte           Create a new Svelte tool"
        puts ""
        puts "Run 'cli generate GENERATOR --help' for detailed help on each generator."
        puts ""
        puts "Options:"
        puts "  --ruby                Generate Ruby code (or set OPENC3_LANGUAGE=ruby)"
        puts "  --python              Generate Python code (or set OPENC3_LANGUAGE=python)"
        puts "  -h, --help            Show this help message"
        puts ""
        puts "Examples:"
        puts "  cli generate plugin MyPlugin --ruby"
        puts "  cli generate target EXAMPLE --python"
        puts "  cli generate widget SuperdataWidget --ruby"
        puts "  cli generate conversion EXAMPLE STATUS --ruby"
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

    def self.check_args(args)
      args.each do |arg|
        if arg =~ /\s/ and args[0].to_s.downcase[0..3] != 'tool'
          abort("#{args[0].to_s.downcase} arguments can not have spaces!")
        end
      end
      # All generators except 'plugin' must be within an existing plugin
      if args[0] != 'plugin' and Dir.glob("*.gemspec").empty?
        abort("No gemspec file detected. #{args[0].to_s.downcase} generator should be run within an existing plugin.")
      end

      gen_lang = ENV['OPENC3_LANGUAGE']
      if (args[-1] == '--python' || args[-1] == '--ruby')
        gen_lang = args[-1][2, 6]
      end
      case gen_lang
      when 'python'
        @@language = 'py'
      when 'ruby'
        @@language = 'rb'
      else
        abort("One of --python or --ruby is required unless OPENC3_LANGUAGE is set.")
      end
    end

    def self.process_template(template_dir, the_binding)
      Dir.glob("#{template_dir}/**/*", File::FNM_DOTMATCH).each do |file|
        next if File.basename(file) == '.'
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
        puts "Usage: cli generate plugin NAME (--ruby or --python)"
        puts ""
        puts "Generate a new COSMOS plugin"
        puts ""
        puts "Arguments:"
        puts "  NAME              Name of the plugin (required)"
        puts "                    Will be prefixed with 'openc3-cosmos-'"
        puts "                    Spaces, underscores, and hyphens will be converted to hyphens"
        puts ""
        puts "Options:"
        puts "  --ruby            Generate Ruby plugin (or set OPENC3_LANGUAGE=ruby)"
        puts "  --python          Generate Python plugin (or set OPENC3_LANGUAGE=python)"
        puts "  -h, --help        Show this help message"
        puts ""
        puts "Example:"
        puts "  cli generate plugin demo --ruby"
        puts "  Creates: openc3-cosmos-demo/"
        puts ""
        puts "Documentation:"
        puts "  https://docs.openc3.com/docs/configuration/plugins"
        exit(args[1].nil? ? 1 : 0)
      end
      if args.length < 2 or args.length > 3
        abort("Usage: cli generate #{args[0]} <NAME> (--ruby or --python)")
      end

      # Create the local variables
      plugin = args[1].downcase.gsub(/_+|-+/, '-')
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

      puts "Plugin #{plugin_name} successfully generated!"
      return plugin_name
    end

    def self.generate_target(args)
      if args[1].nil? || args[1] == '--help' || args[1] == '-h'
        puts "Usage: cli generate target NAME (--ruby or --python)"
        puts ""
        puts "Generate a new target within an existing plugin"
        puts ""
        puts "Arguments:"
        puts "  NAME              Name of the target (required)"
        puts "                    Will be uppercased and underscores/hyphens converted to underscores"
        puts ""
        puts "Options:"
        puts "  --ruby            Generate Ruby target (or set OPENC3_LANGUAGE=ruby)"
        puts "  --python          Generate Python target (or set OPENC3_LANGUAGE=python)"
        puts "  -h, --help        Show this help message"
        puts ""
        puts "Example:"
        puts "  cli generate target EXAMPLE --ruby"
        puts "  Creates: targets/EXAMPLE/"
        puts ""
        puts "Note: Must be run from within an existing plugin directory"
        puts ""
        puts "Documentation:"
        puts "  https://docs.openc3.com/docs/configuration/target"
        exit(args[1].nil? ? 1 : 0)
      end
      if args.length < 2 or args.length > 3
        abort("Usage: cli generate #{args[0]} <NAME> (--ruby or --python)")
      end

      # Create the local variables
      target_name = args[1].upcase.gsub(/_+|-+/, '_')
      target_path = "targets/#{target_name}"
      if File.exist?(target_path)
        abort("Target #{target_path} already exists!")
      end
      target_lib_filename = "#{target_name.downcase}.#{@@language}"
      target_class = target_lib_filename.filename_to_class_name # NOSONAR
      target_object = target_name.downcase # NOSONAR

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
        gemspec.gsub!('plugin.txt', 'plugin.txt requirements.txt')
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
        puts "Usage: cli generate microservice NAME (--ruby or --python)"
        puts ""
        puts "Generate a new microservice within an existing plugin"
        puts ""
        puts "Arguments:"
        puts "  NAME              Name of the microservice (required)"
        puts "                    Will be uppercased and underscores/hyphens converted to underscores"
        puts ""
        puts "Options:"
        puts "  --ruby            Generate Ruby microservice (or set OPENC3_LANGUAGE=ruby)"
        puts "  --python          Generate Python microservice (or set OPENC3_LANGUAGE=python)"
        puts "  -h, --help        Show this help message"
        puts ""
        puts "Example:"
        puts "  cli generate microservice DATA_PROCESSOR --ruby"
        puts "  Creates: microservices/DATA_PROCESSOR/"
        puts ""
        puts "Note: Must be run from within an existing plugin directory"
        puts ""
        puts "Documentation:"
        puts "  https://docs.openc3.com/docs/configuration/plugins#microservices"
        exit(args[1].nil? ? 1 : 0)
      end
      if args.length < 2 or args.length > 3
        abort("Usage: cli generate #{args[0]} <NAME> (--ruby or --python)")
      end

      # Create the local variables
      microservice_name = args[1].upcase.gsub(/_+|-+/, '_')
      microservice_path = "microservices/#{microservice_name}"
      if File.exist?(microservice_path)
        abort("Microservice #{microservice_path} already exists!")
      end
      microservice_filename = "#{microservice_name.downcase}.#{@@language}"
      microservice_class = microservice_filename.filename_to_class_name # NOSONAR

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
        puts "Usage: cli generate widget NAME (--ruby or --python)"
        puts ""
        puts "Generate a new custom Vue.js widget within an existing plugin"
        puts ""
        puts "Arguments:"
        puts "  NAME              Name of the widget (required)"
        puts "                    Must be CapitalCase ending with 'Widget'"
        puts "                    Example: SuperdataWidget, StatusWidget"
        puts ""
        puts "Options:"
        puts "  --ruby            Generate Ruby plugin (or set OPENC3_LANGUAGE=ruby)"
        puts "  --python          Generate Python plugin (or set OPENC3_LANGUAGE=python)"
        puts "  -h, --help        Show this help message"
        puts ""
        puts "Example:"
        puts "  cli generate widget SuperdataWidget --ruby"
        puts "  Creates: src/SuperdataWidget.vue"
        puts ""
        puts "Note: Must be run from within an existing plugin directory"
        puts ""
        puts "Documentation:"
        puts "  https://docs.openc3.com/docs/guides/custom-widgets"
        exit(args[1].nil? ? 1 : 0)
      end
      if args.length < 2 or args.length > 3
        abort("Usage: cli generate #{args[0]} <SuperdataWidget> (--ruby or --python)")
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

        # Specific help for tool variants
        if tool_type != 'tool'
          framework = case tool_type
                      when 'tool_vue' then 'Vue.js'
                      when 'tool_react' then 'React'
                      when 'tool_angular' then 'Angular'
                      when 'tool_svelte' then 'Svelte'
                      else 'Custom'
                      end

          puts "Usage: cli generate #{args[0]} 'TOOL NAME' (--ruby or --python)"
          puts ""
          puts "Generate a new #{framework} tool within an existing plugin"
          puts ""
          puts "Arguments:"
          puts "  TOOL NAME         Display name of the tool (required, can include spaces)"
          puts "                    Will be converted to lowercase without spaces for directory name"
          puts ""
          puts "Options:"
          puts "  --ruby            Generate Ruby plugin (or set OPENC3_LANGUAGE=ruby)"
          puts "  --python          Generate Python plugin (or set OPENC3_LANGUAGE=python)"
          puts "  -h, --help        Show this help message"
          puts ""
          puts "Example:"
          puts "  cli generate #{args[0]} 'Data Viewer' --ruby"
          puts "  Creates: tools/dataviewer/ (#{framework}-based)"
          puts ""
          puts "Note: Must be run from within an existing plugin directory"
          puts "      For other tool types, see: cli generate tool --help"
          puts ""
          puts "Documentation:"
          puts "  https://docs.openc3.com/docs/guides/custom-tools"
          exit(args[1].nil? ? 1 : 0)
        else
          # Generic help showing all types
          puts "Usage: cli generate #{args[0]} 'TOOL NAME' (--ruby or --python)"
          puts ""
          puts "Generate a new custom tool within an existing plugin"
          puts ""
          puts "Arguments:"
          puts "  TOOL NAME         Display name of the tool (required, can include spaces)"
          puts "                    Will be converted to lowercase without spaces for directory name"
          puts ""
          puts "Options:"
          puts "  --ruby            Generate Ruby plugin (or set OPENC3_LANGUAGE=ruby)"
          puts "  --python          Generate Python plugin (or set OPENC3_LANGUAGE=python)"
          puts "  -h, --help        Show this help message"
          puts ""
          puts "Tool Types:"
          puts "  tool              Generate Vue.js tool (default)"
          puts "  tool_vue          Generate Vue.js tool"
          puts "  tool_angular      Generate Angular tool"
          puts "  tool_react        Generate React tool"
          puts "  tool_svelte       Generate Svelte tool"
          puts ""
          puts "Example:"
          puts "  cli generate tool 'Data Viewer' --ruby"
          puts "  Creates: tools/dataviewer/"
          puts ""
          puts "Note: Must be run from within an existing plugin directory"
          puts ""
          puts "Documentation:"
          puts "  https://docs.openc3.com/docs/guides/custom-tools"
          exit(args[1].nil? ? 1 : 0)
        end
      end
      if args.length < 2 or args.length > 3
        abort("Usage: cli generate #{args[0]} 'Tool Name' (--ruby or --python)")
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
      if args[1].nil? || args[2].nil? || args[1] == '--help' || args[1] == '-h'
        puts "Usage: cli generate conversion TARGET NAME (--ruby or --python)"
        puts ""
        puts "Generate a new conversion class for an existing target"
        puts ""
        puts "Arguments:"
        puts "  TARGET            Target name (required, must exist)"
        puts "  NAME              Conversion name (required)"
        puts "                    Will be uppercased with '_CONVERSION' suffix"
        puts ""
        puts "Options:"
        puts "  --ruby            Generate Ruby conversion (or set OPENC3_LANGUAGE=ruby)"
        puts "  --python          Generate Python conversion (or set OPENC3_LANGUAGE=python)"
        puts "  -h, --help        Show this help message"
        puts ""
        puts "Example:"
        puts "  cli generate conversion EXAMPLE STATUS --ruby"
        puts "  Creates: targets/EXAMPLE/lib/status_conversion.rb"
        puts ""
        puts "Note: Must be run from within an existing plugin directory"
        puts ""
        puts "Documentation:"
        puts "  https://docs.openc3.com/docs/configuration/telemetry#read_conversion"
        exit(args[1].nil? || args[2].nil? ? 1 : 0)
      end
      if args.length < 3 or args.length > 4
        abort("Usage: cli generate conversion <TARGET> <NAME> (--ruby or --python)")
      end

      # Create the local variables
      target_name = args[1].upcase
      unless File.exist?("targets/#{target_name}")
        abort("Target '#{target_name}' does not exist! Conversions must be created for existing targets.")
      end
      conversion_name = "#{args[2].upcase.gsub(/_+|-+/, '_')}_CONVERSION"
      conversion_basename = "#{conversion_name.downcase}.#{@@language}"
      conversion_class = conversion_basename.filename_to_class_name # NOSONAR
      conversion_filename = "targets/#{target_name}/lib/#{conversion_basename}"
      if File.exist?(conversion_filename)
        abort("Conversion #{conversion_filename} already exists!")
      end

      process_template("#{TEMPLATES_DIR}/conversion", binding) do |filename|
        filename.sub!("conversion.#{@@language}", conversion_filename)
        false
      end

      puts "Conversion #{conversion_filename} successfully generated!"
      puts "To use the conversion add the following to a telemetry item:"
      puts "  READ_CONVERSION #{conversion_basename}"
      return conversion_name
    end

    def self.generate_processor(args)
      if args[1].nil? || args[2].nil? || args[1] == '--help' || args[1] == '-h'
        puts "Usage: cli generate processor TARGET NAME (--ruby or --python)"
        puts ""
        puts "Generate a new processor for an existing target"
        puts ""
        puts "Arguments:"
        puts "  TARGET            Target name (required, must exist)"
        puts "  NAME              Processor name (required)"
        puts "                    Will be uppercased with '_PROCESSOR' suffix"
        puts ""
        puts "Options:"
        puts "  --ruby            Generate Ruby processor (or set OPENC3_LANGUAGE=ruby)"
        puts "  --python          Generate Python processor (or set OPENC3_LANGUAGE=python)"
        puts "  -h, --help        Show this help message"
        puts ""
        puts "Example:"
        puts "  cli generate processor EXAMPLE DATA --ruby"
        puts "  Creates: targets/EXAMPLE/lib/data_processor.rb"
        puts ""
        puts "Note: Must be run from within an existing plugin directory"
        puts ""
        puts "Documentation:"
        puts "  https://docs.openc3.com/docs/configuration/telemetry#processor"
        exit(args[1].nil? || args[2].nil? ? 1 : 0)
      end
      if args.length < 3 or args.length > 4
        abort("Usage: cli generate processor <TARGET> <NAME> (--ruby or --python)")
      end

      # Create the local variables
      target_name = args[1].upcase
      unless File.exist?("targets/#{target_name}")
        abort("Target '#{target_name}' does not exist! Processors must be created for existing targets.")
      end
      processor_name = "#{args[2].upcase.gsub(/_+|-+/, '_')}_PROCESSOR"
      processor_basename = "#{processor_name.downcase}.#{@@language}"
      processor_class = processor_basename.filename_to_class_name # NOSONAR
      processor_filename = "targets/#{target_name}/lib/#{processor_basename}"
      if File.exist?(processor_filename)
        abort("Processor #{processor_filename} already exists!")
      end

      process_template("#{TEMPLATES_DIR}/processor", binding) do |filename|
        filename.sub!("processor.#{@@language}", processor_filename)
        false
      end

      puts "Processor #{processor_filename} successfully generated!"
      puts "To use the processor add the following to a telemetry packet:"
      puts "  PROCESSOR #{args[2].upcase} #{processor_basename} <PARAMS...>"
      return processor_name
    end

    def self.generate_limits_response(args)
      if args[1].nil? || args[2].nil? || args[1] == '--help' || args[1] == '-h'
        puts "Usage: cli generate limits_response TARGET NAME (--ruby or --python)"
        puts ""
        puts "Generate a new limits response for an existing target"
        puts ""
        puts "Arguments:"
        puts "  TARGET            Target name (required, must exist)"
        puts "  NAME              Limits response name (required)"
        puts "                    Will be uppercased with '_LIMITS_RESPONSE' suffix"
        puts ""
        puts "Options:"
        puts "  --ruby            Generate Ruby limits response (or set OPENC3_LANGUAGE=ruby)"
        puts "  --python          Generate Python limits response (or set OPENC3_LANGUAGE=python)"
        puts "  -h, --help        Show this help message"
        puts ""
        puts "Example:"
        puts "  cli generate limits_response EXAMPLE CUSTOM --ruby"
        puts "  Creates: targets/EXAMPLE/lib/custom_limits_response.rb"
        puts ""
        puts "Note: Must be run from within an existing plugin directory"
        puts ""
        puts "Documentation:"
        puts "  https://docs.openc3.com/docs/configuration/telemetry#limits_response"
        exit(args[1].nil? || args[2].nil? ? 1 : 0)
      end
      if args.length < 3 or args.length > 4
        abort("Usage: cli generate limits_response <TARGET> <NAME> (--ruby or --python)")
      end

      # Create the local variables
      target_name = args[1].upcase
      unless File.exist?("targets/#{target_name}")
        abort("Target '#{target_name}' does not exist! Limits responses must be created for existing targets.")
      end
      response_name = "#{args[2].upcase.gsub(/_+|-+/, '_')}_LIMITS_RESPONSE"
      response_basename = "#{response_name.downcase}.#{@@language}"
      response_filename = "targets/#{target_name}/lib/#{response_basename}"
      response_class = response_basename.filename_to_class_name # NOSONAR
      if File.exist?(response_filename)
        abort("response #{response_filename} already exists!")
      end

      process_template("#{TEMPLATES_DIR}/limits_response", binding) do |filename|
        filename.sub!("response.#{@@language}", response_filename)
        false
      end

      puts "Limits response #{response_filename} successfully generated!"
      puts "To use the limits response add the following to a telemetry item:"
      puts "  LIMITS_RESPONSE #{response_basename}"
      return response_name
    end

    def self.generate_command_validator(args)
      if args[1].nil? || args[2].nil? || args[1] == '--help' || args[1] == '-h'
        puts "Usage: cli generate command_validator TARGET NAME (--ruby or --python)"
        puts ""
        puts "Generate a new command validator for an existing target"
        puts ""
        puts "Arguments:"
        puts "  TARGET            Target name (required, must exist)"
        puts "  NAME              Command validator name (required)"
        puts "                    Will be uppercased with '_COMMAND_VALIDATOR' suffix"
        puts ""
        puts "Options:"
        puts "  --ruby            Generate Ruby command validator (or set OPENC3_LANGUAGE=ruby)"
        puts "  --python          Generate Python command validator (or set OPENC3_LANGUAGE=python)"
        puts "  -h, --help        Show this help message"
        puts ""
        puts "Example:"
        puts "  cli generate command_validator EXAMPLE RANGE --ruby"
        puts "  Creates: targets/EXAMPLE/lib/range_command_validator.rb"
        puts ""
        puts "Note: Must be run from within an existing plugin directory"
        puts ""
        puts "Documentation:"
        puts "  https://docs.openc3.com/docs/configuration/command#validator"
        exit(args[1].nil? || args[2].nil? ? 1 : 0)
      end
      if args.length < 3 or args.length > 4
        abort("Usage: cli generate command_validator <TARGET> <NAME> (--ruby or --python)")
      end

      # Create the local variables
      target_name = args[1].upcase
      unless File.exist?("targets/#{target_name}")
        abort("Target '#{target_name}' does not exist! Command validators must be created for existing targets.")
      end
      validator_name = "#{args[2].upcase.gsub(/_+|-+/, '_')}_COMMAND_VALIDATOR"
      validator_basename = "#{validator_name.downcase}.#{@@language}"
      validator_class = validator_basename.filename_to_class_name # NOSONAR
      validator_filename = "targets/#{target_name}/lib/#{validator_basename}"
      if File.exist?(validator_filename)
        abort("Command validator #{validator_filename} already exists!")
      end

      process_template("#{TEMPLATES_DIR}/command_validator", binding) do |filename|
        filename.sub!("command_validator.#{@@language}", validator_filename)
        false
      end

      puts "Command validator #{validator_filename} successfully generated!"
      puts "To use the command validator add the following to a command:"
      puts "  VALIDATOR #{validator_basename}"
      return validator_name
    end
  end
end
