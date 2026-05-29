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
require 'set'
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
    SYSTEM_VENV_DIR = '/openc3/python/.venv'
    DEFAULT_UV_CACHE_DIR = '/gems/uv'

    # Normalize a package name to lowercase with hyphens (PEP 503 canonical form)
    def self.normalize_pkg_name(name)
      name.tr('_', '-').downcase
    end

    def self.names
      result = {}

      # Collect all packages available in the UV download cache
      # This includes system packages (seeded from the Docker image) plus
      # any additional packages downloaded during plugin installs
      cached = cached_packages
      result['cached'] = cached.sort unless cached.empty?

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

    # List packages in a specific venv by scanning dist-info directories.
    # Returns normalized names (lowercase, hyphens) for consistent display.
    def self.packages_in_venv(venv_dir)
      packages = []
      # Look for site-packages in the venv's lib directory
      Dir.glob("#{venv_dir}/lib/*/site-packages").each do |site_packages|
        next unless File.directory?(site_packages)
        Pathname.new(site_packages).children.each do |child|
          if child.directory? && File.extname(child) == DIST_INFO
            raw_name = File.basename(child, DIST_INFO)
            # Normalize: split name from version, normalize name, rejoin
            match = raw_name.match(/\A(.+?)-(\d.*)/)
            if match
              packages << "#{normalize_pkg_name(match[1])}-#{match[2]}"
            else
              packages << normalize_pkg_name(raw_name)
            end
          end
        end
      end
      packages
    end

    # List packages in the system venv (/openc3/python/.venv)
    def self.system_venv_packages
      packages_in_venv(SYSTEM_VENV_DIR)
    end

    # List unique packages in the UV download cache.
    # UV cache structure: wheels-v<N>/<registry>/<package-name>/<version-pytag-abitag-platform>
    # e.g. wheels-v6/pypi/numpy/2.4.6-cp312-cp312-musllinux_1_2_aarch64
    def self.cached_packages
      cache_dir = ENV.fetch('UV_CACHE_DIR', DEFAULT_UV_CACHE_DIR)
      return [] unless File.directory?(cache_dir)

      packages = Set.new
      # Glob 4 levels deep: wheels-v<N>/<registry>/<package-name>/<version-entry>
      Dir.glob("#{cache_dir}/wheels-v*/*/*/*").each do |entry|
        basename = File.basename(entry)
        # Skip UV metadata sidecar files (.http, .msgpack)
        next if basename.end_with?('.http', '.msgpack')

        # Version entries start with a digit
        match = basename.match(/\A(\d[^-]*)/)
        next unless match

        # Parent directory name is the package name
        pkg_name = File.basename(File.dirname(entry)).tr('_', '-').downcase
        packages.add("#{pkg_name}-#{match[1]}")
      end
      packages.to_a
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

    # Returns a hash of plugin_name => "uv pip list" text output for each plugin venv.
    def self.trees
      result = {}

      if File.directory?(PLUGIN_VENVS_DIR)
        Dir.glob("#{PLUGIN_VENVS_DIR}/*/").each do |plugin_dir|
          plugin_name = File.basename(plugin_dir)
          venv_dir = File.join(plugin_dir, '.venv')
          next unless File.directory?(venv_dir)

          stdout, status = Open3.capture2('uv', 'pip', 'list', '--python', venv_dir)
          if status.success? && stdout.lines.length > 2
            result[plugin_name] = stdout.rstrip
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
