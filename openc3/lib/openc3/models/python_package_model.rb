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

require 'fileutils'
require 'open3'
require 'openc3/utilities/process_manager'
require 'openc3/api/api'
require 'pathname'
require 'json'

module OpenC3
  # This class acts like a Model but doesn't inherit from Model because it doesn't
  # actual interact with the Store (Redis). Instead we implement names, get, put
  # and destroy to allow interaction with python package files from the PluginModel and
  # the PackagesController.
  class PythonPackageModel
    extend Api

    DIST_INFO =  '.dist-info'
    PLUGIN_VENVS_DIR = '/gems/plugin_venvs'

    def self.names
      result = {}

      # Collect packages from per-plugin venvs
      if File.directory?(PLUGIN_VENVS_DIR)
        Dir.glob("#{PLUGIN_VENVS_DIR}/*/").each do |plugin_dir|
          plugin_name = File.basename(plugin_dir)
          venv_dir = File.join(plugin_dir, '.venv')
          next unless File.directory?(venv_dir)

          packages = packages_in_venv(venv_dir)
          result[plugin_name] = packages.sort unless packages.empty?
        end
      end

      # Also collect packages from the shared venv for backwards compatibility
      shared_packages = shared_venv_packages
      result['shared'] = shared_packages.sort unless shared_packages.empty?

      return result
    end

    # List packages in a specific venv by scanning dist-info directories
    def self.packages_in_venv(venv_dir)
      packages = []
      # Look for site-packages in the venv's lib directory
      Dir.glob("#{venv_dir}/lib/*/site-packages").each do |site_packages|
        next unless File.directory?(site_packages)
        Pathname.new(site_packages).children.each do |child|
          if child.directory? && File.extname(child) == DIST_INFO
            packages << File.basename(child, DIST_INFO)
          end
        end
      end
      packages
    end

    # List packages in the shared venv (backwards compatibility)
    def self.shared_venv_packages
      packages = []
      pythonuserbase = ENV['PYTHONUSERBASE']
      return packages unless pythonuserbase

      paths = Dir.glob("#{pythonuserbase}/lib/*")
      paths.each do |path|
        site_packages = File.join(path, 'site-packages')
        next unless File.directory?(site_packages)
        Pathname.new(site_packages).children.each do |child|
          if child.directory? && File.extname(child) == DIST_INFO
            packages << File.basename(child, DIST_INFO)
          end
        end
      end
      packages
    end

    def self.get(name)
      path = "#{ENV['PYTHONUSERBASE']}/cache"
      FileUtils.mkdir_p(path) unless Dir.exist?(path)
      result = Pathname.new(path).children.select { |c| c.file? and File.basename(c, File.extname(c)) == name }
      if result.length > 0
        return result[0] if File.exist?(result[0])
      end
      raise "Package #{name} not found"
    end

    def self.put(package_file_path, package_install: true, scope:, plugin: nil)
      if File.file?(package_file_path)
        package_filename = File.basename(package_file_path)
        FileUtils.mkdir_p("#{ENV['PYTHONUSERBASE']}/cache") unless Dir.exist?("#{ENV['PYTHONUSERBASE']}/cache")
        cache_path = "#{ENV['PYTHONUSERBASE']}/cache/#{File.basename(package_file_path)}"
        FileUtils.cp(package_file_path, cache_path)
        if package_install
          return self.install(cache_path, scope: scope, plugin: plugin)
        end
      else
        message = "Package file #{package_file_path} does not exist!"
        Logger.error message
        raise message
      end
      return nil
    end

    def self.install(name_or_path, scope:, plugin: nil)
      if File.exist?(name_or_path)
        package_file_path = name_or_path
      else
        package_file_path = get(name_or_path)
      end
      package_filename = File.basename(package_file_path)
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
      Logger.info "Installing python package: #{name_or_path}"
      if ENV['PIP_ENABLE_TRUSTED_HOST'].nil?
        pip_args = ["-i", pypi_url, package_file_path]
      else
        pip_args = ["-i", pypi_url, "--trusted-host", URI.parse(pypi_url).host, package_file_path]
      end
      spawn_env = {}
      if plugin
        venv_path = "#{PLUGIN_VENVS_DIR}/#{plugin}/.venv"
        spawn_env['PIPINSTALL_VENV'] = venv_path
      end
      result = OpenC3::ProcessManager.instance.spawn(["/openc3/bin/pipinstall"] + pip_args, "package_install", package_filename, Time.now + 3600.0, scope: scope, env: spawn_env)
      return result.name
    end

    def self.destroy(name, scope:)
      package_name, version = self.extract_name_and_version(name)
      Logger.info "Uninstalling package: #{name}"
      pip_args = [package_name]
      result = OpenC3::ProcessManager.instance.spawn(["/openc3/bin/pipuninstall"] + pip_args, "package_uninstall", name, Time.now + 3600.0, scope: scope)
      return result.name
    end

    # Returns a hash of plugin_name => "uv tree" text output for each plugin venv.
    # Falls back to a flat package list for venvs without pyproject.toml (pip-installed).
    def self.trees
      result = {}
      flat = self.names

      if File.directory?(PLUGIN_VENVS_DIR)
        Dir.glob("#{PLUGIN_VENVS_DIR}/*/").each do |plugin_dir|
          plugin_name = File.basename(plugin_dir)
          venv_dir = File.join(plugin_dir, '.venv')
          pyproject = File.join(plugin_dir, 'pyproject.toml')
          next unless File.directory?(venv_dir)

          if File.exist?(pyproject)
            stdout, status = Open3.capture2('uv', 'tree', '--no-dev', '--frozen', chdir: plugin_dir)
            if status.success?
              # Strip the first line (root project name/version) from the tree output
              lines = stdout.lines
              lines.shift
              tree_text = lines.join.rstrip
              result[plugin_name] = tree_text unless tree_text.empty?
            elsif flat[plugin_name]
              result[plugin_name] = flat[plugin_name].join("\n")
            end
          elsif flat[plugin_name]
            result[plugin_name] = flat[plugin_name].join("\n")
          end
        end
      end

      result
    end

    def self.extract_name_and_version(name)
      split_name = name.split('-')
      if split_name.length > 1
        package_name = split_name[0..-2].join('-')
        version = File.basename(split_name[-1], DIST_INFO)
      else
        package_name = name
        version = "Unknown"
      end

      return package_name, version
    end
  end
end
