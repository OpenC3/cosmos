# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'rubygems'
require 'rubygems/package'
require 'openc3'
require 'openc3/utilities/bucket'
require 'openc3/utilities/store'
require 'openc3/config/config_parser'
require 'openc3/models/model'
require 'openc3/models/gem_model'
require 'openc3/models/target_model'
require 'openc3/models/interface_model'
require 'openc3/models/router_model'
require 'openc3/models/script_engine_model'
require 'openc3/models/tool_model'
require 'openc3/models/widget_model'
require 'openc3/models/microservice_model'
require 'openc3/api/api'
require 'tmpdir'
require 'tempfile'
require 'fileutils'

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
    PLUGIN_TXT = 'plugin.txt'

    attr_accessor :variables
    attr_accessor :plugin_txt_lines
    attr_accessor :needs_dependencies
    attr_accessor :store_id
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
    def self.install_phase1(gem_file_path, existing_variables: nil, existing_plugin_txt_lines: nil, store_id: nil, process_existing: false, scope:, validate_only: false)
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
        parser.parse_file(plugin_txt_path,
                          false,
                          true,
                          false) do |keyword, params|
          if keyword == 'VARIABLE'
            usage = "#{keyword} <Variable Name> <Default Value>"
            parser.verify_num_parameters(2, nil, usage)
            variable_name = params[0]
            if RESERVED_VARIABLE_NAMES.include?(variable_name)
              raise "VARIABLE name '#{variable_name}' is reserved"
            end
            value = params[1..-1].join(" ")
            variables[variable_name] = value
            if existing_variables && existing_variables.key?(variable_name)
              variables[variable_name] = existing_variables[variable_name]
            end
          end
        end

        store_id = Integer(store_id) if store_id
        model = PluginModel.new(name: gem_name, variables: variables, plugin_txt_lines: plugin_txt_lines, store_id: store_id, scope: scope)
        result = model.as_json()
        result['existing_plugin_txt_lines'] = existing_plugin_txt_lines if existing_plugin_txt_lines and not process_existing and existing_plugin_txt_lines != result['plugin_txt_lines']
        return result
      ensure
        FileUtils.remove_entry_secure(temp_dir, true)
        tf.unlink if tf
      end
    end

    # Called by the PluginsController to create the plugin
    # Because this uses ERB it must be run in a separate process from the API to
    # prevent corruption and single require problems in the current process
    def self.install_phase2(plugin_hash, scope:, gem_file_path: nil, validate_only: false)
      # Register plugin to aid in uninstall if install fails
      plugin_hash.delete("existing_plugin_txt_lines")
      plugin_model = PluginModel.new(**(plugin_hash.transform_keys(&:to_sym)), scope: scope)
      plugin_model.create unless validate_only

      temp_dir = Dir.mktmpdir
      begin
        tf = nil

        # Get the gem from local gem server if it hasn't been passed
        unless gem_file_path
          gem_name = plugin_hash['name'].split("__")[0]
          gem_file_path = OpenC3::GemModel.get(gem_name)
        end

        # Attempt to remove all older versions of this same plugin before install to prevent version conflicts
        # Especially on downgrades
        # Leave the same version if it already exists
        OpenC3::GemModel.destroy_all_other_versions(File.basename(gem_file_path))

        # Actually install the gem now (slow)
        OpenC3::GemModel.install(gem_file_path, scope: scope) unless validate_only

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

        # Process app store metadata
        plugin_model.title = pkg.spec.metadata['openc3_store_title'] || pkg.spec.summary.strip
        plugin_model.description = pkg.spec.metadata['openc3_store_description'] || pkg.spec.description.strip
        plugin_model.licenses = pkg.spec.licenses
        plugin_model.homepage = pkg.spec.homepage
        plugin_model.repository = pkg.spec.metadata['source_code_uri'] # this key because it's in the official gemspec examples
        plugin_model.keywords = pkg.spec.metadata['openc3_store_keywords']&.split(/, ?/)
        img_path = pkg.spec.metadata['openc3_store_image']
        unless img_path
          default_img_path = 'public/store_img.png'
          full_default_path = File.join(gem_path, default_img_path)
          img_path = default_img_path if File.exist? full_default_path
        end
        plugin_model.img_path = File.join('gems', gem_name.split(".gem")[0], img_path) if img_path # convert this filesystem path to volumes mount path
        plugin_model.update() unless validate_only

        needs_dependencies = pkg.spec.runtime_dependencies.length > 0
        needs_dependencies = true if Dir.exist?(File.join(gem_path, 'lib'))

        # Handle python dependencies (pyproject.toml or requirements.txt)
        pyproject_path = File.join(gem_path, 'pyproject.toml')
        requirements_path = File.join(gem_path, 'requirements.txt')

        if File.exist?(pyproject_path) || File.exist?(requirements_path)
          begin
            pypi_url = get_setting('pypi_url', scope: scope)
            if pypi_url
              pypi_url += '/simple'
            end
          rescue => e
            Logger.error("Failed to retrieve pypi_url: #{e.formatted}")
          ensure
            if pypi_url.nil?
              # If Redis isn't running try the ENV, then simply pypi.org/simple
              pypi_url = ENV['PYPI_URL']
              if pypi_url
                pypi_url += '/simple'
              end
              pypi_url ||= 'https://pypi.org/simple'
            end
          end
          unless validate_only
            if File.exist?(pyproject_path)
              Logger.info "Installing python packages from pyproject.toml with pypi_url=#{pypi_url}"
              if ENV['PIP_ENABLE_TRUSTED_HOST'].nil?
                pip_args = "--no-warn-script-location -i #{pypi_url} #{gem_path}"
              else
                pip_args = "--no-warn-script-location -i #{pypi_url} --trusted-host #{URI.parse(pypi_url).host} #{gem_path}"
              end
            else
              Logger.info "Installing python packages from requirements.txt with pypi_url=#{pypi_url}"
              if ENV['PIP_ENABLE_TRUSTED_HOST'].nil?
                pip_args = "--no-warn-script-location -i #{pypi_url} -r #{requirements_path}"
              else
                pip_args = "--no-warn-script-location -i #{pypi_url} --trusted-host #{URI.parse(pypi_url).host} -r #{requirements_path}"
              end
            end
            puts `/openc3/bin/pipinstall #{pip_args}`
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
          plugin_model.update unless validate_only
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
          variables = plugin_hash['variables']
          variables ||= {}
          variables['scope'] = scope
          if File.exist?(plugin_txt_path)
            parser = OpenC3::ConfigParser.new("https://openc3.com")

            current_model = nil
            parser.parse_file(plugin_txt_path, false, true, true, variables) do |keyword, params|
              case keyword
              when 'VARIABLE', 'NEEDS_DEPENDENCIES'
                # Ignore during phase 2
              when 'TARGET', 'INTERFACE', 'ROUTER', 'MICROSERVICE', 'TOOL', 'WIDGET', 'SCRIPT_ENGINE'
                begin
                  if current_model
                    current_model.create unless validate_only
                    current_model.deploy(gem_path, variables, validate_only: validate_only)
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
              current_model.create unless validate_only
              current_model.deploy(gem_path, variables, validate_only: validate_only)
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
        plugin_model.destroy unless validate_only
        raise e
      ensure
        FileUtils.remove_entry_secure(temp_dir, true)
        tf.unlink if tf
      end
      return plugin_model.as_json()
    end

    def initialize(
      name:,
      variables: {},
      plugin_txt_lines: [],
      needs_dependencies: false,
      store_id: nil,
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
      @needs_dependencies = ConfigParser.handle_true_false(needs_dependencies)
      @store_id = store_id
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
        'needs_dependencies' => @needs_dependencies,
        'store_id' => @store_id,
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
  end
end
