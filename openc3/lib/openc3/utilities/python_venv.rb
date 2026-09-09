# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/target_model'
require 'openc3/utilities/target_file'

module OpenC3
  module PythonVenv
    PLUGIN_VENVS_DIR = '/gems/plugin_venvs'

    # Shared user site-packages directory used by plugins that predate the
    # per-plugin UV venvs. Every caller that falls back off a plugin venv points
    # PYTHONUSERBASE here, so keep it in one place rather than repeating the
    # literal in script.rb, running_script.rb, microservice_operator.rb and
    # microservice_model.rb.
    DEFAULT_PYTHONUSERBASE = '/gems/python_packages'

    # Resolve a script's plugin venv and expose its packages to a child process.
    # Returns the venv path when configured, or nil when the system environment
    # should be used.
    def self.configure_for_script(environment, name:, scope:, python_venv: nil)
      venv_dir = resolve_script_venv(name: name, scope: scope, python_venv: python_venv)
      return nil unless venv_dir

      configure_environment(environment, venv_dir)
      venv_dir
    end

    def self.configure_environment(environment, venv_dir)
      environment['VIRTUAL_ENV'] = venv_dir
      environment['PATH'] = "#{venv_dir}/bin:#{ENV.fetch('PATH', '')}"
      environment['PYTHONUSERBASE'] = venv_dir

      site_packages = Dir.glob("#{venv_dir}/lib/python*/site-packages").first
      # Prefer a PYTHONPATH the caller already seeded on `environment` over the
      # ambient one. Script.process_suite sets it to ENV['PYTHONPATH'] || '.'
      # before calling here, and reading ENV directly would drop that value.
      existing_pythonpath = environment['PYTHONPATH'] || ENV.fetch('PYTHONPATH', '')
      if site_packages
        environment['PYTHONPATH'] = existing_pythonpath.empty? ? site_packages : "#{site_packages}:#{existing_pythonpath}"
      else
        environment['PYTHONPATH'] = existing_pythonpath.empty? ? nil : existing_pythonpath
      end

      environment
    end

    def self.plugin_venv_path(scope:, plugin_name:)
      sanitized_name = "#{scope}__#{plugin_name}".tr('^a-zA-Z0-9_-', '_')
      candidate = File.join(PLUGIN_VENVS_DIR, sanitized_name, '.venv')
      candidate if File.directory?(candidate)
    end

    def self.resolve_script_venv(name:, scope:, python_venv: nil)
      target_name = name.split('/')[0].to_s.upcase
      if target_name == TargetFile::TEMP_FOLDER && python_venv
        # File.basename strips directory components; the tr() then whitelists the
        # name down to the character set PluginModel.plugin_venv_name builds it
        # from. That leaves no path separators and no glob metacharacters, so
        # the value cannot escape PLUGIN_VENVS_DIR or widen the Dir.glob in
        # configure_environment.
        safe_name = File.basename(python_venv.to_s).tr('^a-zA-Z0-9_-', '_')
        # The venv name is client-supplied, so it must also be confined to the
        # caller's scope. Venv directories are named "<scope>__<plugin>" by
        # PluginModel.plugin_venv_name; without this check a user in one scope
        # could name another scope's venv and run against its packages.
        return nil unless safe_name.start_with?("#{scope}__".tr('^a-zA-Z0-9_-', '_'))

        candidate = File.join(PLUGIN_VENVS_DIR, safe_name, '.venv')
        return candidate if File.directory?(candidate)
      else
        target_info = TargetModel.get(name: target_name, scope: scope)
        if target_info && target_info['plugin']
          return plugin_venv_path(scope: scope, plugin_name: target_info['plugin'])
        end
      end
      nil
    rescue => e
      Logger.debug("Could not resolve plugin venv for script '#{name}': #{e.message}")
      nil
    end
    private_class_method :resolve_script_venv
  end
end
