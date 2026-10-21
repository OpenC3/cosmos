# encoding: utf-8

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

require 'rubygems'
require 'rubygems/package'
require 'openc3'
require 'openc3/utilities/bucket'
require 'openc3/utilities/python_venv'
require 'openc3/utilities/store'
require 'openc3/config/config_parser'
require 'openc3/models/model'
require 'openc3/models/scope_model'
require 'openc3/models/gem_model'
require 'openc3/models/target_model'
require 'openc3/models/interface_model'
require 'openc3/models/router_model'
require 'openc3/models/script_engine_model'
require 'openc3/models/tool_model'
require 'openc3/models/widget_model'
require 'openc3/models/microservice_model'
require 'openc3/api/api'
require 'openc3/utilities/pypi_url'
require 'tmpdir'
require 'tempfile'
require 'fileutils'
require 'open3'

module OpenC3
  class EmptyGemFileError < StandardError; end

  # Represents a OpenC3 plugin that can consist of targets, interfaces, routers
  # microservices and tools. The PluginModel installs all these pieces as well
  # as destroys them all when the plugin is removed.
  class PluginModel < Model
    extend Api

    PRIMARY_KEY = 'openc3_plugins'
    # Reserved VARIABLE names. See local_mode.rb: update_local_plugin()
    RESERVED_VARIABLE_NAMES = ['target_name', 'microservice_name', 'scope']
    # Variable defined by VARIABLE_BRIDGE holding the selected bridge
    BRIDGE_VARIABLE_NAME = 'bridge_name'
    # ${name} in a VARIABLE_DISCOVERY parameter is replaced by the value of variable name
    DISCOVERY_REFERENCE = /\$\{(\w+)\}/
    # Input types of VARIABLE_TYPE in the plugin dialog
    VARIABLE_TYPES = ['TEXT', 'BOOLEAN', 'INTEGER', 'NUMBER', 'PASSWORD', 'JSON', 'SECRET']
    PLUGIN_TXT = 'plugin.txt'

    attr_accessor :variables
    attr_accessor :plugin_txt_lines
    attr_accessor :plugin_text
    attr_accessor :minimum_cosmos_version
    attr_accessor :needs_dependencies
    # The plugin's requirements.txt as installed, which bridges send to the host
    # (openc3-app) to provision bridged interfaces
    attr_accessor :python_requirements
    attr_accessor :store_plugin_id
    attr_accessor :store_version_id
    attr_accessor :title
    attr_accessor :description
    attr_accessor :licenses
    attr_accessor :homepage
    attr_accessor :repository
    attr_accessor :keywords
    attr_accessor :img_path

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    def self.get(name:, scope: nil)
      super("#{scope}__#{PRIMARY_KEY}", name: name)
    end

    def self.names(scope: nil)
      super("#{scope}__#{PRIMARY_KEY}")
    end

    def self.all(scope: nil)
      super("#{scope}__#{PRIMARY_KEY}")
    end

    # Called by the PluginsController to parse the plugin variables
    # Doesn't actually create the plugin during the phase
    def self.install_phase1(gem_file_path, existing_variables: nil, existing_plugin_txt_lines: nil, store_plugin_id: nil, store_version_id: nil, process_existing: false, scope:, validate_only: false)
      gem_name = File.basename(gem_file_path).split("__")[0]

      temp_dir = Dir.mktmpdir
      tf = nil
      begin
        if File.exist?(gem_file_path)
          if File.zero?(gem_file_path)
            raise EmptyGemFileError, "Gem file is empty: #{gem_file_path}"
          end

          # Load gem to internal gem server
          OpenC3::GemModel.put(gem_file_path, gem_install: false, scope: scope) unless validate_only
        else
          gem_file_path = OpenC3::GemModel.get(gem_name)
        end

        # Extract gem and process plugin.txt to determine what VARIABLEs need to be filled in
        pkg = Gem::Package.new(gem_file_path)

        minimum_cosmos_version = pkg.spec.metadata['openc3_cosmos_minimum_version']

        if existing_plugin_txt_lines and process_existing
          # This is only used in openc3cli load when everything is known
          plugin_txt_lines = existing_plugin_txt_lines
          file_data = existing_plugin_txt_lines.join("\n")
          tf = Tempfile.new(PLUGIN_TXT)
          tf.write(file_data)
          tf.close
          plugin_txt_path = tf.path
        else
          # Otherwise we always process the new and return both
          pkg.extract_files(temp_dir)
          plugin_txt_path = File.join(temp_dir, PLUGIN_TXT)
          plugin_text = File.read(plugin_txt_path)
          plugin_txt_lines = []
          plugin_text.each_line do |line|
            plugin_txt_lines << line.chomp
          end
        end

        parser = OpenC3::ConfigParser.new("https://openc3.com")

        # Phase 1 Gather Variables
        variables = {}
        current_variable_name = nil
        plugin_text_blocks = []
        plugin_text_lines = nil # Non-nil while inside PLUGIN_TEXT_START / PLUGIN_TEXT_END
        variable_text_lines = nil # Non-nil while inside VARIABLE_TEXT_START / VARIABLE_TEXT_END
        # Yield non-keyword lines so blank lines and markdown headers (# lines) are captured in PLUGIN_TEXT
        parser.parse_file(plugin_txt_path,
                          true,
                          true,
                          false) do |keyword, params|
          if plugin_text_lines
            if keyword == 'PLUGIN_TEXT_END'
              parser.set_preserve_lines(false)
              plugin_text_blocks << plugin_text_lines
              plugin_text_lines = nil
            else
              plugin_text_lines << parser.line
            end
            next
          end
          if variable_text_lines
            if keyword == 'VARIABLE_TEXT_END'
              parser.set_preserve_lines(false)
              # Shown below the PLUGIN_TEXT when the VARIABLE_STATE is selected
              option = variables[current_variable_name]['options'][-1]
              option['markdown'] = [option['markdown'], unindent_lines(variable_text_lines)].compact.join("\n\n")
              variable_text_lines = nil
            else
              variable_text_lines << parser.line
            end
            next
          end

          case keyword
          when 'PLUGIN_TEXT_START'
            parser.verify_num_parameters(0, 0, keyword)
            # Preserve the raw lines (no stripping, quote or continuation processing) until PLUGIN_TEXT_END
            parser.set_preserve_lines(true)
            plugin_text_lines = []
          when 'PLUGIN_TEXT_END'
            raise "PLUGIN_TEXT_END must follow a PLUGIN_TEXT_START"
          when 'VARIABLE_TEXT_START'
            parser.verify_num_parameters(0, 0, keyword)
            unless current_variable_name and variables[current_variable_name]['options']
              raise "VARIABLE_TEXT_START must follow a VARIABLE_STATE definition"
            end
            parser.set_preserve_lines(true)
            variable_text_lines = []
          when 'VARIABLE_TEXT_END'
            raise "VARIABLE_TEXT_END must follow a VARIABLE_TEXT_START"
          when 'VARIABLE', 'VARIABLE_BRIDGE'
            if keyword == 'VARIABLE'
              usage = "#{keyword} <Variable Name> <Default Value>"
              parser.verify_num_parameters(2, nil, usage)
              variable_name = params[0]
              if RESERVED_VARIABLE_NAMES.include?(variable_name)
                raise "VARIABLE name '#{variable_name}' is reserved"
              end
              value = params[1..-1].join(" ")
            else
              usage = "#{keyword} <Default Bridge Name (optional)>"
              parser.verify_num_parameters(0, 1, usage)
              variable_name = BRIDGE_VARIABLE_NAME
              value = (params[0] || 'DEFAULT').upcase
            end
            if variables[variable_name] and (keyword == 'VARIABLE_BRIDGE' or variables[variable_name]['bridge'])
              raise "VARIABLE '#{BRIDGE_VARIABLE_NAME}' is defined by VARIABLE_BRIDGE and cannot be redefined"
            end
            variables[variable_name] = { 'value' => value }
            # Selected from the available bridges in the plugin dialog
            variables[variable_name]['bridge'] = true if keyword == 'VARIABLE_BRIDGE'
            current_variable_name = variable_name
            if existing_variables && existing_variables.key?(variable_name)
              existing = existing_variables[variable_name]
              # Handle both old format (string) and new format (hash)
              if existing.is_a?(Hash)
                variables[variable_name]['value'] = existing['value']
              else
                variables[variable_name]['value'] = existing
              end
            end
          when 'VARIABLE_DESCRIPTION'
            usage = "#{keyword} <Description>"
            parser.verify_num_parameters(1, 1, usage)
            unless current_variable_name
              raise "VARIABLE_DESCRIPTION must follow a VARIABLE definition"
            end
            variables[current_variable_name]['description'] = params[0]
          when 'VARIABLE_LABEL'
            usage = "#{keyword} <Label>"
            parser.verify_num_parameters(1, 1, usage)
            unless current_variable_name
              raise "VARIABLE_LABEL must follow a VARIABLE definition"
            end
            # Shown in the plugin dialog instead of the variable name
            variables[current_variable_name]['label'] = params[0]
          when 'VARIABLE_TYPE'
            usage = "#{keyword} <#{VARIABLE_TYPES.join(' | ')}>"
            parser.verify_num_parameters(1, 1, usage)
            unless current_variable_name
              raise "VARIABLE_TYPE must follow a VARIABLE definition"
            end
            type = params[0].upcase
            unless VARIABLE_TYPES.include?(type)
              raise "VARIABLE_TYPE must be one of #{VARIABLE_TYPES.join(', ')} but got '#{params[0]}'"
            end
            variables[current_variable_name]['type'] = type
          when 'VARIABLE_GROUP'
            usage = "#{keyword} <Group Name>"
            parser.verify_num_parameters(1, 1, usage)
            unless current_variable_name
              raise "VARIABLE_GROUP must follow a VARIABLE definition"
            end
            # Shown in a titled section of the plugin dialog
            variables[current_variable_name]['group'] = params[0]
          when 'VARIABLE_REQUIRED'
            parser.verify_num_parameters(0, 0, keyword)
            unless current_variable_name
              raise "VARIABLE_REQUIRED must follow a VARIABLE definition"
            end
            # The plugin dialog won't install while it is shown and blank
            variables[current_variable_name]['required'] = true
          when 'VARIABLE_PATTERN'
            usage = "#{keyword} <Regular Expression> <Error Message (optional)>"
            parser.verify_num_parameters(1, 2, usage)
            unless current_variable_name
              raise "VARIABLE_PATTERN must follow a VARIABLE definition"
            end
            begin
              Regexp.new(params[0])
            rescue RegexpError => e
              raise "VARIABLE_PATTERN '#{params[0]}' is not a valid regular expression: #{e.message}"
            end
            # Matched against the whole value of a non-blank variable in the plugin dialog
            variables[current_variable_name]['pattern'] = params[0]
            variables[current_variable_name]['pattern_message'] = params[1] if params[1]
          when 'VARIABLE_HIDDEN'
            parser.verify_num_parameters(0, 0, keyword)
            unless current_variable_name
              raise "VARIABLE_HIDDEN must follow a VARIABLE definition"
            end
            # Never shown in the plugin dialog. Its value comes from VARIABLE_STATE_SET or
            # VARIABLE_DISCOVERY_SET for use in ERB and VARIABLE_DISCOVERY parameters.
            variables[current_variable_name]['hidden'] = true
          when 'VARIABLE_ADVANCED'
            parser.verify_num_parameters(0, 0, keyword)
            unless current_variable_name
              raise "VARIABLE_ADVANCED must follow a VARIABLE definition"
            end
            # Shown in a collapsed section of the plugin dialog
            variables[current_variable_name]['advanced'] = true
          when 'VARIABLE_STATE'
            usage = "#{keyword} <Display Text> <Value>"
            parser.verify_num_parameters(1, 2, usage)
            unless current_variable_name
              raise "VARIABLE_STATE must follow a VARIABLE definition"
            end
            variables[current_variable_name]['options'] ||= []
            option = { 'value' => params[1] || params[0], 'text' => params[0] }
            variables[current_variable_name]['options'] << option
          when 'VARIABLE_DISCOVERY'
            usage = "#{keyword} <Discovery Class Filename or Module> <Discovery Parameters (optional)> ..."
            parser.verify_num_parameters(1, nil, usage)
            unless current_variable_name
              raise "VARIABLE_DISCOVERY must follow a VARIABLE definition"
            end
            # Either a filename (openc3/discovery/hid_discovery.py) or a module (openc3.discovery.hid_discovery)
            unless params[0].end_with?('.py') or params[0] =~ /\A[A-Za-z_]\w*(\.[A-Za-z_]\w*)*\z/
              raise "VARIABLE_DISCOVERY requires a Python discovery class filename (.py) or module name but got '#{params[0]}'"
            end
            # A variable can have multiple discoveries whose results are combined.
            # Each is the discovery class followed by the parameters passed to it.
            variables[current_variable_name]['discovery'] ||= []
            variables[current_variable_name]['discovery'] << { 'discovery' => params }
          when 'VARIABLE_DISCOVERY_SET'
            usage = "#{keyword} <Variable Name> <Value>"
            parser.verify_num_parameters(2, nil, usage)
            discoveries = variables[current_variable_name]['discovery'] if current_variable_name
            unless discoveries
              raise "#{keyword} must follow a VARIABLE_DISCOVERY definition"
            end
            # Applied when the user selects a value found by this discovery
            discoveries[-1]['set'] ||= {}
            discoveries[-1]['set'][params[0]] = params[1..-1].join(" ")
          when 'VARIABLE_STATE_SHOW'
            usage = "#{keyword} <Variable Name> <Variable Name (optional)> ..."
            parser.verify_num_parameters(1, nil, usage)
            options = variables[current_variable_name]['options'] if current_variable_name
            unless options
              raise "#{keyword} must follow a VARIABLE_STATE definition"
            end
            options[-1]['show'] ||= []
            options[-1]['show'].concat(params)
            options[-1]['show'].uniq!
          when 'VARIABLE_STATE_DESCRIPTION', 'VARIABLE_STATE_ICON'
            usage = keyword == 'VARIABLE_STATE_ICON' ? "#{keyword} <Icon Name>" : "#{keyword} <Description>"
            parser.verify_num_parameters(1, 1, usage)
            options = variables[current_variable_name]['options'] if current_variable_name
            unless options
              raise "#{keyword} must follow a VARIABLE_STATE definition"
            end
            if keyword == 'VARIABLE_STATE_ICON'
              # Material Design Icons like mdi-cloud, or another icon set's prefix:name
              unless params[0] =~ /\A[\w:-]+\z/
                raise "VARIABLE_STATE_ICON '#{params[0]}' is not a valid icon name like mdi-cloud"
              end
              options[-1]['icon'] = params[0]
            else
              # Shown below the state's text in the plugin dialog dropdown
              options[-1]['description'] = params[0]
            end
          when 'VARIABLE_STATE_REQUIRED'
            usage = "#{keyword} <Variable Name> <Variable Name (optional)> ..."
            parser.verify_num_parameters(1, nil, usage)
            options = variables[current_variable_name]['options'] if current_variable_name
            unless options
              raise "#{keyword} must follow a VARIABLE_STATE definition"
            end
            # Required in the plugin dialog while the state is selected
            options[-1]['required'] ||= []
            options[-1]['required'].concat(params)
            options[-1]['required'].uniq!
          when 'VARIABLE_STATE_SET'
            usage = "#{keyword} <Variable Name> <Value>"
            parser.verify_num_parameters(2, nil, usage)
            options = variables[current_variable_name]['options'] if current_variable_name
            unless options
              raise "#{keyword} must follow a VARIABLE_STATE definition"
            end
            options[-1]['set'] ||= {}
            options[-1]['set'][params[0]] = params[1..-1].join(" ")
          end
        end

        raise "PLUGIN_TEXT_START without a matching PLUGIN_TEXT_END" if plugin_text_lines
        raise "VARIABLE_TEXT_START without a matching VARIABLE_TEXT_END" if variable_text_lines
        plugin_markdown = plugin_text_blocks.empty? ? nil : plugin_text_blocks.map { |lines| unindent_lines(lines) }.join("\n\n")

        # Variables can be defined after the VARIABLE_STATE_SHOW / SET and VARIABLE_DISCOVERY_SET
        # that reference them so validate the references once all variables are known
        variables.each do |variable_name, variable|
          references = []
          Array(variable['options']).each do |option|
            (Array(option['show']) + Array(option['required']) + Array(option['set']&.keys)).each do |target_name|
              references << [target_name, "state '#{option['text']}'"]
            end
          end
          Array(variable['discovery']).each do |discovery|
            source = "discovery '#{discovery['discovery'].join(' ')}'"
            Array(discovery['set']&.keys).each do |target_name|
              references << [target_name, source]
            end
            # Discovery parameters can use the value of another variable as ${name}
            discovery['discovery'][1..].each do |param|
              param.scan(DISCOVERY_REFERENCE).flatten.each do |target_name|
                references << [target_name, source]
              end
            end
          end
          references.each do |target_name, source|
            if target_name == variable_name
              raise "VARIABLE '#{variable_name}' #{source} cannot reference itself"
            end
            unless variables.key?(target_name)
              raise "VARIABLE '#{variable_name}' #{source} references undefined VARIABLE '#{target_name}'"
            end
          end
        end

        # Apply the VARIABLE_STATE_SET values of each initially selected state (in file order so
        # a set can select the state of a later variable). Values from an existing install win,
        # except for hidden variables which always follow the state (they can't be edited).
        variables.each do |_variable_name, variable|
          next unless variable['options']
          selected = variable['options'].find { |option| option['value'] == variable['value'] }
          next unless selected and selected['set']
          selected['set'].each do |target_name, value|
            next if existing_variables and existing_variables.key?(target_name) and not variables[target_name]['hidden']
            variables[target_name]['value'] = value
          end
        end

        store_plugin_id = Integer(store_plugin_id) if store_plugin_id
        store_version_id = Integer(store_version_id) if store_version_id
        model = PluginModel.new(name: gem_name, variables: variables, plugin_txt_lines: plugin_txt_lines, plugin_text: plugin_markdown, store_plugin_id: store_plugin_id, store_version_id: store_version_id, minimum_cosmos_version: minimum_cosmos_version, scope: scope)
        result = model.as_json()
        result['existing_plugin_txt_lines'] = existing_plugin_txt_lines if existing_plugin_txt_lines and not process_existing and existing_plugin_txt_lines != result['plugin_txt_lines']
        return result
      ensure
        FileUtils.remove_entry_secure(temp_dir, true)
        tf.unlink if tf
      end
    end

    # Extract simple key-value pairs for ERB substitution
    # Variables can be either new format (hash with 'value' key) or old format (string)
    def self.erb_variables(plugin_hash, scope:)
      erb_variables = {}
      (plugin_hash['variables'] || {}).each do |name, var|
        erb_variables[name] = var.is_a?(Hash) ? var['value'] : var
      end
      erb_variables['scope'] = scope
      erb_variables
    end

    # Renders ERB in a plugin's Python dependency file (requirements.txt or
    # pyproject.toml) in place using the plugin variables. The ERB filename is
    # set so templates can locate files next to it with File.dirname(__FILE__).
    def self.render_python_dependency_erb(path, erb_variables)
      data = File.read(path).force_encoding("UTF-8")
      return unless data.include?('<%')
      erb = ERB.new(data.comment_erb(), trim_mode: "-")
      erb.filename = path
      File.write(path, erb.result(binding.set_variables(erb_variables)))
    end

    # Called by the PluginsController to create the plugin
    # Because this uses ERB it must be run in a separate process from the API to
    # prevent corruption and single require problems in the current process
    # diff_only: dry run that renders the plugin's target files and returns the
    # list of modified files ("TARGET/path") whose live content differs from
    # what this plugin would deploy — used to warn before an upgrade which user
    # modifications it would supersede. Implies validate_only (no side effects).
    def self.install_phase2(plugin_hash, scope:, gem_file_path: nil, validate_only: false, diff_only: false)
      # diff_only implies a dry run; derive a local flag instead of mutating
      # the validate_only parameter.
      dry_run = validate_only || diff_only
      # Register plugin to aid in uninstall if install fails
      plugin_hash.delete("existing_plugin_txt_lines")
      # Version History upgrade hints (threaded from the admin install through
      # update_plugin). Extracted before the splat below because PluginModel
      # has no such attributes. version_history_files lists modified files the
      # user chose to take from the plugin; username attributes the upgrade.
      upgrade_username = plugin_hash.delete("username")
      upgrade_version_files = plugin_hash.delete("version_history_files")
      plugin_model = PluginModel.new(**(plugin_hash.transform_keys(&:to_sym)), scope: scope)
      plugin_model.create unless dry_run

      temp_dir = Dir.mktmpdir
      begin
        tf = nil

        # Get the gem from local gem server if it hasn't been passed
        if gem_file_path.nil?
          gem_name = plugin_hash['name'].split("__")[0]
          gem_file_path = OpenC3::GemModel.get(gem_name)
        else
          gem_name = File.basename(gem_file_path)
        end

        # Attempt to remove all older versions of this same plugin before install to prevent version conflicts
        # Especially on downgrades
        # Leave the same version if it already exists
        # Skipped for dry_run/diff_only: a dry run must not mutate gems.
        OpenC3::GemModel.destroy_all_other_versions(File.basename(gem_file_path)) unless dry_run

        # Actually install the gem now (slow)
        OpenC3::GemModel.install(gem_file_path, scope: scope) unless dry_run

        # Extract gem contents
        gem_path = File.join(temp_dir, "gem")
        FileUtils.mkdir_p(gem_path)
        pkg = Gem::Package.new(gem_file_path)
        pkg.extract_files(gem_path)
        Dir[File.join(gem_path, '**/screens/*.txt')].each do |filename|
          if File.basename(filename) != File.basename(filename).downcase
            raise "Invalid screen filename: #{filename}. Screen filenames must be lowercase."
          end
        end

        plugin_model.minimum_cosmos_version = pkg.spec.metadata['openc3_cosmos_minimum_version']

        # Process OpenC3 Store metadata
        plugin_model.title = pkg.spec.metadata['openc3_store_title'] || pkg.spec.summary.strip
        plugin_model.description = pkg.spec.metadata['openc3_store_description'] || pkg.spec.description.strip
        plugin_model.licenses = pkg.spec.licenses
        plugin_model.homepage = pkg.spec.homepage
        plugin_model.repository = pkg.spec.metadata['source_code_uri'] # this key because it's in the official gemspec examples
        plugin_model.keywords = pkg.spec.metadata['openc3_store_keywords']&.split(/, ?/)
        # Resolve the plugin's store image path. The gemspec generated by
        # `cli generate plugin` sets `openc3_store_image` to `public/store_img.png`
        # but does not create that file, so we must verify existence regardless
        # of whether the path came from metadata or the default — otherwise the
        # frontend hits a 500 when fetching the missing file.
        img_path = pkg.spec.metadata['openc3_store_image'] || 'public/store_img.png'
        img_path = nil unless File.exist?(File.join(gem_path, img_path))
        package_name = "#{pkg.spec.name}-#{pkg.spec.version}"
        # Build the upgrade context once the gem version is known; TargetModel
        # deploys use it either to collect a modified-file diff (diff_only) or
        # to version modified files taken from the plugin.
        upgrade_context = nil
        if diff_only
          upgrade_context = { diff_collector: [] }
        elsif upgrade_version_files && !upgrade_version_files.empty?
          upgrade_context = { username: upgrade_username,
                              plugin: "#{pkg.spec.name} #{pkg.spec.version}",
                              version_files: upgrade_version_files }
        end
        plugin_model.img_path = File.join('gems', package_name, img_path) if img_path # convert this filesystem path to volumes mount path
        plugin_model.update() unless dry_run

        needs_dependencies = pkg.spec.runtime_dependencies.length > 0
        needs_dependencies = true if Dir.exist?(File.join(gem_path, 'lib'))

        # Handle python dependencies (pyproject.toml or requirements.txt)
        pyproject_path = File.join(gem_path, 'pyproject.toml')
        requirements_path = File.join(gem_path, 'requirements.txt')
        # Dependency files may use ERB so plugin variables can select dependencies
        [pyproject_path, requirements_path].each do |path|
          render_python_dependency_erb(path, self.erb_variables(plugin_hash, scope: scope)) if File.exist?(path)
        end

        if File.exist?(requirements_path)
          plugin_model.python_requirements = File.read(requirements_path)
          plugin_model.update unless dry_run
        end

        if File.exist?(pyproject_path) || File.exist?(requirements_path)
          pypi_url = resolve_pypi_url(scope: scope)
          # Skipped for any dry run: diff_only runs inline in an HTTP request, so
          # a slow or unreachable PyPI would time it out, and it must not mutate
          # the plugin venv.
          unless dry_run
            pypi_args = build_pypi_args(pypi_url)

            # Install Python dependencies into an isolated per-plugin venv when UV
            # is available. Each plugin gets its own venv at /gems/plugin_venvs/<name>/.venv
            # so that plugins with conflicting Python dependency versions don't interfere.
            # If UV is unavailable or the install fails, fall back to the shared pipinstall
            # which installs into PYTHONUSERBASE (the legacy shared environment).
            uv_installed = ENV['OPENC3_USE_UV'] != 'false' && system('which uv > /dev/null 2>&1')
            if uv_installed
              plugin_venv_name = plugin_venv_name(scope: scope, plugin_name: plugin_model.name)
              Logger.info "Installing python packages into per-plugin venv '#{plugin_venv_name}' with pypi_url=#{pypi_url}"
              uv_args = [plugin_venv_name, gem_path] + pypi_args
              output, status = Open3.capture2e("/openc3/bin/uvinstall", *uv_args)
              puts output
              if status.success?
                # A plugin that declares openc3 itself would shadow the system
                # library once its site-packages goes on PYTHONPATH, so drop it
                # here rather than let the wrong client reach a running script.
                PythonVenv.purge_reserved_packages(File.join('/gems', 'plugin_venvs', plugin_venv_name, '.venv'))
              else
                Logger.warn "UV per-plugin install failed, falling back to shared pipinstall"
                uv_installed = false
              end
            end

            unless uv_installed
              pip_args = pypi_args.dup
              if File.exist?(pyproject_path)
                Logger.info "Installing python packages from pyproject.toml with pypi_url=#{pypi_url}"
                pip_args << gem_path
              else
                Logger.info "Installing python packages from requirements.txt with pypi_url=#{pypi_url}"
                pip_args += ["-r", requirements_path]
              end
              # Capture output and check exit code so failures surface as a warning
              # rather than silently succeeding. pipinstall is non-fatal: the plugin
              # continues to install even if Python packages fail so that non-Python
              # functionality still works.
              output, status = Open3.capture2e("/openc3/bin/pipinstall", *pip_args)
              puts output
              unless status.success?
                Logger.warn "Python package installation failed. Plugin Python microservices may not function correctly."
              end
            end
          end
          needs_dependencies = true
        end

        # If needs_dependencies hasn't already been set we need to scan the plugin.txt
        # to see if they've explicitly set the NEEDS_DEPENDENCIES keyword
        unless needs_dependencies
          if plugin_hash['plugin_txt_lines'].join("\n").include?('NEEDS_DEPENDENCIES')
            needs_dependencies = true
          end
        end
        if needs_dependencies
          plugin_model.needs_dependencies = true
          plugin_model.update unless dry_run
        end

        # Temporarily add all lib folders from the gem to the end of the load path
        load_dirs = []
        begin
          Dir.glob("#{gem_path}/**/*").each do |load_dir|
            if File.directory?(load_dir) and File.basename(load_dir) == 'lib'
              load_dirs << load_dir
              $LOAD_PATH << load_dir
            end
          end

          # Process plugin.txt file
          file_data = plugin_hash['plugin_txt_lines'].join("\n")
          tf = Tempfile.new(PLUGIN_TXT)
          tf.write(file_data)
          tf.close
          plugin_txt_path = tf.path
          erb_variables = self.erb_variables(plugin_hash, scope: scope)
          if File.exist?(plugin_txt_path)
            parser = OpenC3::ConfigParser.new("https://openc3.com")

            current_model = nil
            text_end = nil # The END keyword while inside a PLUGIN_TEXT or VARIABLE_TEXT block
            parser.parse_file(plugin_txt_path, false, true, true, erb_variables) do |keyword, params|
              # PLUGIN_TEXT and VARIABLE_TEXT were captured in phase 1 so skip them
              if text_end
                if keyword == text_end
                  parser.set_preserve_lines(false)
                  text_end = nil
                end
                next
              end
              case keyword
              when 'PLUGIN_TEXT_START', 'VARIABLE_TEXT_START'
                parser.set_preserve_lines(true)
                text_end = keyword.sub('_START', '_END')
              when 'VARIABLE', 'VARIABLE_DESCRIPTION', 'VARIABLE_LABEL', 'VARIABLE_TYPE', 'VARIABLE_GROUP', 'VARIABLE_REQUIRED', 'VARIABLE_PATTERN', 'VARIABLE_HIDDEN', 'VARIABLE_ADVANCED', 'VARIABLE_STATE', 'VARIABLE_STATE_SHOW', 'VARIABLE_STATE_SET', 'VARIABLE_STATE_REQUIRED', 'VARIABLE_STATE_DESCRIPTION', 'VARIABLE_STATE_ICON', 'VARIABLE_DISCOVERY', 'VARIABLE_DISCOVERY_SET', 'VARIABLE_BRIDGE', 'NEEDS_DEPENDENCIES'
                # Ignore during phase 2
              when 'TARGET', 'INTERFACE', 'ROUTER', 'MICROSERVICE', 'TOOL', 'WIDGET', 'SCRIPT_ENGINE'
                begin
                  if current_model
                    current_model.create unless dry_run
                    if current_model.is_a?(OpenC3::TargetModel)
                      current_model.deploy(gem_path, erb_variables, validate_only: dry_run, upgrade_context: upgrade_context)
                    else
                      current_model.deploy(gem_path, erb_variables, validate_only: dry_run)
                    end
                  end
                # If something goes wrong in create, or more likely in deploy,
                # we want to clear the current_model and try to instantiate the next
                # Otherwise we're stuck constantly iterating on the last model
                ensure
                  current_model = nil
                  current_model = OpenC3.const_get((keyword.split('_').collect(&:capitalize).join + 'Model').intern).handle_config(parser,
                    keyword, params, plugin: plugin_model.name, needs_dependencies: needs_dependencies, scope: scope)
                end
              else
                if current_model
                  current_model.handle_config(parser, keyword, params)
                else
                  raise "Invalid keyword '#{keyword}' in plugin.txt"
                end
              end
            end
            if current_model
              current_model.create unless dry_run
              if current_model.is_a?(OpenC3::TargetModel)
                current_model.deploy(gem_path, erb_variables, validate_only: dry_run, upgrade_context: upgrade_context)
              else
                current_model.deploy(gem_path, erb_variables, validate_only: dry_run)
              end
              current_model = nil
            end
          end
        ensure
          load_dirs.each do |load_dir|
            $LOAD_PATH.delete(load_dir)
          end
        end
      rescue => e
        # Install failed - need to cleanup
        plugin_model.destroy unless dry_run
        raise e
      ensure
        FileUtils.remove_entry_secure(temp_dir, true)
        tf.unlink if tf
      end
      return upgrade_context[:diff_collector].uniq if diff_only
      return plugin_model.as_json()
    end

    # Dry run: which modified files would this plugin's install supersede?
    # Returns a list of "TARGET/path" names whose live (modified) content
    # differs from the rendered plugin content. Read-only; no side effects.
    # Errors propagate so callers can tell a failed check from an empty diff.
    def self.modified_diff(plugin_hash, scope:)
      install_phase2(plugin_hash, scope: scope, diff_only: true)
    end

    # The plugin.txt lines that install the plugin with ERB rendered using the
    # plugin_hash variables, without the variable definitions and text blocks.
    # Returns { 'plugin_txt' => text } or { 'error' => message } if ERB fails.
    def self.preview(plugin_hash, scope:)
      erb_variables = self.erb_variables(plugin_hash, scope: scope)
      text = Array(plugin_hash['plugin_txt_lines']).join("\n")
      begin
        output = ERB.new(text.comment_erb(), trim_mode: "-").result(binding.set_variables(erb_variables))
      rescue Exception => e # SyntaxError and NameError are common ERB mistakes
        line = e.backtrace_locations&.find { |location| location.path == '(erb)' }&.lineno
        line ||= e.message[/\(erb\):(\d+)/, 1]
        return { 'error' => "ERB error#{" at line #{line}" if line}: #{e.message.lines.first&.strip}" }
      end
      lines = []
      text_end = nil
      output.each_line(chomp: true) do |line|
        keyword = line.strip.split(/\s+/, 2)[0]
        if text_end
          text_end = nil if keyword == text_end
          next
        end
        if keyword.nil?
          lines << '' unless lines.empty? or lines[-1].empty?
        elsif keyword == 'PLUGIN_TEXT_START' or keyword == 'VARIABLE_TEXT_START'
          text_end = keyword.sub('_START', '_END')
        elsif not keyword.start_with?('VARIABLE', '#')
          lines << line
        end
      end
      lines.pop while lines[-1] == ''
      { 'plugin_txt' => lines.join("\n") }
    end

    # Discovery classes can be given as a filename or module name, so compare
    # them as module names, e.g. openc3.discovery.serial_discovery
    def self.discovery_class_key(name)
      name.to_s.delete_suffix('.py').tr('/', '.')
    end

    # The value an installed plugin selected for a VARIABLE_DISCOVERY variable
    # "claims" that device (e.g. a serial port or controller serial number) so
    # discovery stops offering it to other plugins. Claims are per bridge, as
    # each bridge is a different host, and per discovery class (not its
    # parameters) so e.g. a HID serial number claimed through one product ID is
    # claimed for every HID discovery. Uninstalling the plugin releases its claims.
    #
    # @param exclude_plugin [String] Plugin being upgraded or edited, which must
    #   still be offered the devices it already holds
    # @return [Hash] Claimed value => name of the plugin holding it
    def self.discovery_claims(bridge_name, discovery_class, exclude_plugin: nil, scope:)
      bridge_name = bridge_name.to_s.upcase
      key = discovery_class_key(discovery_class)
      claims = {}
      all(scope: scope).each do |plugin_name, plugin|
        next if plugin_name == exclude_plugin
        variables = (plugin['variables'] || {}).values.select { |variable| variable.is_a?(Hash) }
        bridge = variables.find { |variable| variable['bridge'] }
        next unless (bridge ? bridge['value'] : 'DEFAULT').to_s.upcase == bridge_name
        variables.each do |variable|
          next unless variable['discovery'].is_a?(Array)
          next unless variable['discovery'].any? { |entry| discovery_class_key(Array(entry['discovery'])[0]) == key }
          claims[variable['value'].to_s] ||= plugin_name
        end
      end
      claims
    end

    # Remove the common leading whitespace so PLUGIN_TEXT can be indented in plugin.txt
    # without turning the markdown into code blocks
    def self.unindent_lines(lines)
      indent = lines.reject { |line| line.strip.empty? }.map { |line| line[/\A[ \t]*/].length }.min || 0
      lines.map { |line| line[indent..] || '' }.join("\n").strip
    end

    def initialize(
      name:,
      variables: {},
      plugin_txt_lines: [],
      plugin_text: nil,
      minimum_cosmos_version: nil,
      needs_dependencies: false,
      python_requirements: nil,
      store_plugin_id: nil,
      store_version_id: nil,
      title: nil,
      description: nil,
      keywords: nil,
      licenses: nil,
      homepage: nil,
      repository: nil,
      img_path: nil,
      updated_at: nil,
      scope:
    )
      super("#{scope}__#{PRIMARY_KEY}", name: name, updated_at: updated_at, scope: scope)
      @variables = variables
      @plugin_txt_lines = plugin_txt_lines
      @plugin_text = plugin_text
      @minimum_cosmos_version = minimum_cosmos_version
      @needs_dependencies = ConfigParser.handle_true_false(needs_dependencies)
      @python_requirements = python_requirements
      @store_plugin_id = store_plugin_id
      @store_version_id = store_version_id
      @title = title
      @description = description
      @keywords = keywords
      @licenses = licenses
      @homepage = homepage
      @repository = repository
      @img_path = img_path
    end

    def create(update: false, force: false, queued: false)
      if not update and not @name.index("__")
        existing_names = Set.new(self.class.names(scope: @scope))
        counter = 0
        counter += 1 while existing_names.include?("#{@name}__#{counter}")
        @name = "#{@name}__#{counter}"
      end
      super(update: update, force: force, queued: queued)
    end

    def as_json(*_a)
      {
        'name' => @name,
        'variables' => @variables,
        'plugin_txt_lines' => @plugin_txt_lines,
        'plugin_text' => @plugin_text,
        'minimum_cosmos_version' => @minimum_cosmos_version,
        'needs_dependencies' => @needs_dependencies,
        'python_requirements' => @python_requirements,
        'store_plugin_id' => @store_plugin_id,
        'store_version_id' => @store_version_id,
        'title' => @title,
        'description' => @description,
        'keywords' => @keywords,
        'licenses' => @licenses,
        'homepage' => @homepage,
        'repository' => @repository,
        'img_path' => @img_path,
        'updated_at' => @updated_at
      }
    end

    # Undeploy all models associated with this plugin
    def undeploy
      errors = []
      microservice_count = 0
      microservices = MicroserviceModel.find_all_by_plugin(plugin: @name, scope: @scope)
      microservices.each do |_name, model_instance|
        begin
          model_instance.destroy
        rescue Exception => e
          errors << e
        end
        microservice_count += 1
      end
      # Wait for the operator to wake up and remove the microservice processes
      sleep 15 if microservice_count > 0 # Cycle time 5s times 2 plus 5s wait for soft stop and then hard stop
      # Remove all the other models now that the processes have stopped
      # Save TargetModel for last as it has the most to cleanup
      [InterfaceModel, RouterModel, ToolModel, WidgetModel, TargetModel, ScriptEngineModel].each do |model|
        model.find_all_by_plugin(plugin: @name, scope: @scope).each do |_name, model_instance|
          begin
            model_instance.destroy
          rescue Exception => e
            errors << e
          end
        end
      end
      # Cleanup Redis stuff that might have been left by microservices
      microservices.each do |_name, model_instance|
        begin
          model_instance.cleanup
        rescue Exception => e
          errors << e
        end
      end
      # Remove the per-plugin UV virtual environment directory that was created
      # during install_phase2. This cleans up the .venv, pyproject.toml, uv.lock,
      # and .uv_managed marker so disk space is reclaimed on plugin uninstall.
      begin
        plugin_venv_name = self.class.plugin_venv_name(scope: @scope, plugin_name: @name)
        plugin_venv_path = File.join('/gems', 'plugin_venvs', plugin_venv_name)
        if File.directory?(plugin_venv_path)
          Logger.info("Removing per-plugin Python venv: #{plugin_venv_path}")
          FileUtils.rm_rf(plugin_venv_path)
        end
      rescue Exception => e
        errors << e
      end
      # Raise all the errors at once
      if errors.length > 0
        message = ''
        errors.each do |error|
          message += "\n#{error.formatted}\n"
        end
        raise message
      end
    rescue Exception => e
      Logger.error("Error undeploying plugin model #{@name} in scope #{@scope} due to: #{e.formatted}")
    ensure
      # Double check everything is gone
      found = []
      [MicroserviceModel, InterfaceModel, RouterModel, ToolModel, WidgetModel, TargetModel, ScriptEngineModel].each do |model|
        model.find_all_by_plugin(plugin: @name, scope: @scope).each do |_name, model_instance|
          found << model_instance
        end
      end
      if found.length > 0
        # If undeploy failed we need to not move forward with anything else
        Logger.error("Error undeploying plugin model #{@name} in scope #{@scope} due to: Plugin submodels still exist after undeploy = #{found.length}")
        raise "Plugin #{@name} submodels still exist after undeploy = #{found.length}"
      end
    end

    # Reinstall
    def restore
      plugin_hash = self.as_json()
      OpenC3::PluginModel.install_phase2(plugin_hash, scope: @scope)
      @destroyed = false
    end

    # Get list of plugin gem names across all scopes to prevent uninstall of gems from GemModel
    def self.gem_names
      result = []
      scopes = ScopeModel.names
      scopes.each do |scope|
        plugin_names = self.names(scope: scope)
        plugin_names.each do |plugin_name|
          gem_name = plugin_name.split("__")[0]
          result << gem_name unless result.include?(gem_name)
        end
      end
      return result.sort
    end

    # Resolve the PyPI URL from settings, environment, or default.
    # Used by both install_phase2 and migrate_to_uv! to avoid duplication.
    def self.resolve_pypi_url(scope:)
      pypi_url = nil
      begin
        pypi_url = PypiUrl.index_url(get_setting('pypi_url', scope: scope))
      rescue => e
        Logger.error("Failed to retrieve pypi_url: #{e.formatted}")
      ensure
        if pypi_url.nil?
          pypi_url = PypiUrl.index_url(ENV.fetch('PYPI_URL', nil))
          pypi_url ||= PypiUrl::DEFAULT
        end
      end
      PypiUrl.validate(pypi_url)
    end

    # Build the argv array of pypi index arguments. Kept as a delegate so
    # callers that already reference PluginModel keep working; the logic lives
    # in PypiUrl because PythonPackageModel needs it too and must not have to
    # require this file.
    def self.build_pypi_args(pypi_url)
      PypiUrl.build_args(pypi_url)
    end

    # Build a sanitized venv directory name from scope and plugin name.
    # Replaces characters that are not alphanumeric, underscore, or hyphen with underscores.
    def self.plugin_venv_name(scope:, plugin_name:)
      "#{scope}__#{plugin_name}".tr('^a-zA-Z0-9_-', '_')
    end

    # Check if this plugin needs migration to a per-plugin UV virtual environment.
    # Returns true if the plugin has Python dependencies but no .uv_managed marker exists.
    def needs_uv_migration?
      return false unless @needs_dependencies

      plugin_venv_name = self.class.plugin_venv_name(scope: @scope, plugin_name: @name)
      marker_path = File.join('/gems', 'plugin_venvs', plugin_venv_name, '.uv_managed')
      !File.exist?(marker_path)
    end

    # Migrate this plugin from the shared Python venv to a per-plugin UV virtual environment.
    # Non-fatal: logs a warning on failure, plugin continues using the shared venv.
    # Returns true on success, false on failure.
    def migrate_to_uv!(scope:)
      plugin_venv_name = self.class.plugin_venv_name(scope: scope, plugin_name: @name)
      marker_path = File.join('/gems', 'plugin_venvs', plugin_venv_name, '.uv_managed')
      if File.exist?(marker_path)
        Logger.info("Plugin '#{@name}' is already migrated to a per-plugin UV venv")
        return true
      end

      gem_name = @name.split("__")[0]
      gem_file_path = OpenC3::GemModel.get(gem_name)

      temp_dir = Dir.mktmpdir
      begin
        # Extract gem contents (same pattern as install_phase2)
        gem_path = File.join(temp_dir, "gem")
        FileUtils.mkdir_p(gem_path)
        pkg = Gem::Package.new(gem_file_path)
        pkg.extract_files(gem_path)

        # Check for Python dependency files
        pyproject_path = File.join(gem_path, 'pyproject.toml')
        requirements_path = File.join(gem_path, 'requirements.txt')

        unless File.exist?(pyproject_path) || File.exist?(requirements_path)
          Logger.info("Plugin #{@name} has no Python dependencies to migrate")
          return true
        end

        pypi_url = self.class.resolve_pypi_url(scope: scope)
        pypi_args = self.class.build_pypi_args(pypi_url)

        # Run uvinstall for this plugin
        plugin_venv_name = self.class.plugin_venv_name(scope: @scope, plugin_name: @name)
        Logger.info("Migrating plugin '#{@name}' to per-plugin UV venv '#{plugin_venv_name}'")
        uv_args = [plugin_venv_name, gem_path] + pypi_args
        output, status = Open3.capture2e("/openc3/bin/uvinstall", *uv_args)
        puts output
        if status.success?
          Logger.info("Successfully migrated plugin '#{@name}' to per-plugin UV venv")
          return true
        else
          Logger.warn("UV migration failed for plugin '#{@name}'. Plugin will continue using shared venv.")
          return false
        end
      rescue => e
        Logger.warn("UV migration failed for plugin '#{@name}': #{e.message}. Plugin will continue using shared venv.")
        return false
      ensure
        FileUtils.remove_entry_secure(temp_dir, true)
      end
    end

    # Remove the backing gem for an unloaded plugin so it disappears from
    # GemModel.names (and the admin Packages tab). Skips the removal if any
    # other PluginModel (any scope, any counter) still references the gem,
    # via the existing PluginModel.gem_names check inside GemModel.destroy.
    def self.cleanup_gem(plugin_name, scope:)
      gem_filename = plugin_name.split("__")[0]
      OpenC3::GemModel.destroy(gem_filename, log_and_raise_needed_errors: false)
    rescue => e
      Logger.warn("Could not remove gem #{gem_filename}: #{e.message}", scope: scope)
    end
  end
end
