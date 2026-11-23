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

require 'digest'
require 'fileutils'
require 'json'
require 'net/http'
require 'open3'
require 'rubygems/package'
require 'tmpdir'
require 'uri'

module OpenC3
  # Bundles a Python plugin's locked dependencies into the plugin gem as wheels
  # so an air-gapped deployment can install them with no index.
  #
  # A plugin opts in from its pyproject.toml:
  #
  #   [tool.openc3]
  #   offline_install = true
  #   # Optional. Defaults to the machine running the build.
  #   python_platforms = ["x86_64-manylinux_2_28", "aarch64-manylinux_2_28"]
  #   python_version = "3.13"
  #
  # The build (`openc3cli bundlewheels`, run by the plugin Rakefile) writes the
  # wheels to WHEELS_DIR. At install, PluginModel hands that directory to
  # uvinstall, which installs from it alone against the hashes in uv.lock.
  module PythonWheelBundle
    class Error < StandardError; end

    WHEELS_DIR = 'python_wheels'

    # offline_install on a line before any comment marker
    MENTIONS_OFFLINE_INSTALL = /^[^#\n]*offline_install/

    # Reads TOML with Python's tomllib: Ruby has no TOML parser in the standard
    # library, and a hand-rolled one would miss spellings such as inline tables
    # and silently build a gem without its wheels.
    TOML_TO_JSON = 'import json, sys, tomllib; json.dump(tomllib.load(open(sys.argv[1], "rb")), sys.stdout)'

    # @param project_dir [String] plugin source or extracted gem directory
    # @return [Hash] offline_install, python_platforms, python_version. Disabled
    #   when the plugin has no pyproject.toml or does not set offline_install.
    def self.config(project_dir)
      disabled = { offline_install: false, python_platforms: [], python_version: nil }
      pyproject = File.join(project_dir, 'pyproject.toml')
      return disabled unless File.exist?(pyproject)
      # Every TOML spelling of the key contains its name outside a comment, so
      # a plugin that never sets it, or only has the template's commented
      # example, skips the Python process.
      return disabled unless File.read(pyproject).match?(MENTIONS_OFFLINE_INSTALL)

      settings = read_toml(pyproject).dig('tool', 'openc3') || {}
      offline = settings.fetch('offline_install', false)
      unless [true, false].include?(offline)
        raise Error, "[tool.openc3] offline_install must be true or false in #{pyproject}"
      end

      platforms = settings.fetch('python_platforms', [])
      unless platforms.is_a?(Array) && platforms.all?(String)
        raise Error, "[tool.openc3] python_platforms must be a list of strings in #{pyproject}"
      end

      version = settings['python_version']
      unless version.nil? || version.is_a?(String)
        raise Error, "[tool.openc3] python_version must be a string such as \"3.13\" in #{pyproject}"
      end
      if !platforms.empty? && version.nil?
        raise Error, "[tool.openc3] python_platforms also needs python_version, the deployment's Python " \
                     "such as \"3.13\", in #{pyproject}. Otherwise the wheels match the build machine's Python."
      end

      { offline_install: offline, python_platforms: platforms, python_version: version }
    end

    # @param project_dir [String] plugin source or extracted gem directory
    # @return [Boolean] whether the plugin asks for its wheels to be bundled
    def self.offline_install?(project_dir)
      config(project_dir)[:offline_install]
    end

    # The bundled wheels directory of a plugin that sets offline_install, or
    # nil when it does not. Raises when the gem lacks the uv.lock or wheels an
    # offline install needs, so the gem fails validation rather than reaching
    # an air-gapped deployment that cannot install it.
    #
    # @param dir [String] extracted gem or plugin source directory
    # @return [String, nil] the wheels directory
    def self.offline_wheels_dir(dir)
      return nil unless offline_install?(dir)

      unless File.exist?(File.join(dir, 'uv.lock'))
        raise Error, "Plugin sets [tool.openc3] offline_install but its gem has no uv.lock. Run `uv lock`, commit uv.lock, and include it in the gemspec files."
      end

      wheels_dir = File.join(dir, WHEELS_DIR)
      unless File.directory?(wheels_dir)
        raise Error, "Plugin sets [tool.openc3] offline_install but its gem has no #{WHEELS_DIR}/. " \
                     "Build it with `openc3cli bundlewheels` before `gem build` (the plugin Rakefile does this) and include #{WHEELS_DIR}/* in the gemspec files."
      end
      wheels_dir
    end

    # Bundles the wheels a plugin's uv.lock pins into <project_dir>/WHEELS_DIR,
    # replacing any earlier bundle. When offline_install is off, removes the
    # directory instead so a stale bundle never ships.
    #
    # uv picks the wheels: for each target it installs the exported, hashed
    # requirements into a scratch directory, which evaluates environment markers
    # and wheel tags for that target. Each installed .dist-info/WHEEL lists the
    # tags of the wheel uv chose, and that tag set identifies exactly one wheel
    # entry in uv.lock, whose url and sha256 are then used to fetch and check it.
    # Finally the bundle is installed offline, from itself alone, for every
    # target: the same check uvinstall makes at deployment.
    #
    # @param project_dir [String] plugin source directory
    # @param out [IO] where progress is reported
    # @return [Array<String>] the bundled wheel filenames
    def self.build(project_dir, out: $stdout)
      wheels_dir = File.join(project_dir, WHEELS_DIR)
      settings = config(project_dir)
      unless settings[:offline_install]
        if File.exist?(wheels_dir)
          out.puts "Removing #{WHEELS_DIR}/: offline_install is not set in [tool.openc3]"
          FileUtils.rm_rf(wheels_dir)
        end
        return []
      end

      lock_path = File.join(project_dir, 'uv.lock')
      unless File.exist?(lock_path)
        raise Error, "[tool.openc3] offline_install requires a uv.lock. Run `uv lock` and commit the result."
      end

      output, status = Open3.capture2e('uv', 'lock', '--check', chdir: project_dir)
      unless status.success?
        raise Error, "uv.lock is out of date with pyproject.toml. Run `uv lock` and commit the result.\n#{output}"
      end

      check_lock_committed(project_dir)

      targets = settings[:python_platforms].empty? ? [nil] : settings[:python_platforms]
      lock_wheels = lock_wheels_by_name(read_toml(lock_path))

      Dir.mktmpdir do |tmp|
        requirements = export_requirements(project_dir, tmp)

        selected = {}
        targets.each_with_index do |platform, index|
          target_dir = File.join(tmp, "select_#{index}")
          run_uv(project_dir, 'pip', 'install', '--target', target_dir, '--only-binary', ':all:', '--require-hashes',
                 *target_args(platform, settings[:python_version]), '-r', requirements,
                 what: "find a compatible wheel for every locked package for #{describe_target(platform, settings[:python_version])}")
          installed_wheels(target_dir).each do |name, version, tags|
            wheel = match_lock_wheel(lock_wheels, name, version, tags)
            unless wheel
              raise Error, "uv installed #{name} #{version} for #{describe_target(platform, settings[:python_version])} " \
                           "from a wheel uv.lock does not record"
            end
            selected[wheel[:filename]] = wheel
          end
        end

        FileUtils.rm_rf(wheels_dir)
        FileUtils.mkdir_p(wheels_dir)
        selected.values.sort_by { |wheel| wheel[:filename] }.each do |wheel|
          fetch_wheel(project_dir, wheel, File.join(wheels_dir, wheel[:filename]))
        end
        File.write(File.join(wheels_dir, 'SHA256SUMS'),
                   selected.keys.sort.map { |filename| "#{selected[filename][:sha256]}  #{filename}\n" }.join)

        targets.each_with_index do |platform, index|
          run_uv(project_dir, 'pip', 'install', '--target', File.join(tmp, "verify_#{index}"), '--offline', '--no-index',
                 '--find-links', wheels_dir, '--require-hashes', *target_args(platform, settings[:python_version]),
                 '-r', requirements,
                 what: "install from the bundled wheels alone for #{describe_target(platform, settings[:python_version])}")
        end
      end

      bundled = Dir[File.join(wheels_dir, '*.whl')].map { |path| File.basename(path) }.sort
      out.puts "Bundled #{bundled.length} wheel(s) into #{WHEELS_DIR}/ for " \
               "#{targets.map { |platform| describe_target(platform, settings[:python_version]) }.join(', ')}"
      bundled
    end

    # Checks a plugin's bundled wheels without network access and prints a
    # report: each bundled wheel against its uv.lock hash, then for each target
    # which bundled wheel serves each locked package, or uv's reason the target
    # cannot install from the bundle.
    #
    # @param path [String] a plugin .gem file, or a plugin source directory
    # @param out [IO] where the report is printed
    # @param python_platforms [Array<String>, nil] uv --python-platform names to
    #   check instead of the plugin's own python_platforms
    # @param python_version [String, nil] Python version to check instead of the
    #   plugin's own python_version
    # @return [Boolean] true when every target installs from the bundle alone
    def self.verify(path, out: $stdout, python_platforms: nil, python_version: nil)
      if File.directory?(path)
        return verify_dir(path, path, out, python_platforms, python_version)
      end

      Dir.mktmpdir do |tmp|
        Gem::Package.new(path).extract_files(tmp)
        verify_dir(tmp, path, out, python_platforms, python_version)
      end
    end

    def self.verify_dir(dir, label, out, python_platforms, python_version)
      out.puts "Plugin: #{label}"
      begin
        wheels_dir = offline_wheels_dir(dir)
      rescue Error => e
        out.puts "FAIL: #{e.message}"
        return false
      end
      unless wheels_dir
        out.puts "FAIL: does not set [tool.openc3] offline_install, so COSMOS installs its Python dependencies from an index"
        return false
      end

      settings = config(dir)
      lock_path = File.join(dir, 'uv.lock')

      platforms = python_platforms || settings[:python_platforms]
      version = python_version || settings[:python_version]
      if !platforms.empty? && version.nil?
        raise Error, "--python-platform also needs --python-version, the deployment's Python such as 3.13"
      end

      targets = platforms.empty? ? [nil] : platforms
      lock_wheels = lock_wheels_by_name(read_toml(lock_path))
      locked_by_filename = lock_wheels.values.flatten.to_h { |wheel| [wheel[:filename], wheel] }
      passed = true

      bundled = Dir[File.join(wheels_dir, '*.whl')]
      hash_status = {}
      out.puts "", "Bundled wheels (#{bundled.length}), checked against the sha256 in uv.lock:"
      bundled.each do |wheel_path|
        filename = File.basename(wheel_path)
        locked = locked_by_filename[filename]
        hash_status[filename] = if locked.nil?
                                  'NOT IN uv.lock'
                                elsif Digest::SHA256.file(wheel_path).hexdigest == locked[:sha256]
                                  'OK'
                                else
                                  'HASH MISMATCH'
                                end
        passed = false unless hash_status[filename] == 'OK'
      end
      print_table(out, bundled.map { |wheel_path| [File.basename(wheel_path), hash_status[File.basename(wheel_path)]] })

      Dir.mktmpdir do |tmp|
        requirements = export_requirements(dir, tmp)
        targets.each_with_index do |platform, index|
          target_dir = File.join(tmp, "verify_#{index}")
          output, status = Open3.capture2e('uv', 'pip', 'install', '--target', target_dir, '--offline', '--no-index',
                                           '--find-links', wheels_dir, '--require-hashes',
                                           *target_args(platform, version), '-r', requirements, chdir: dir)
          out.puts ""
          unless status.success?
            passed = false
            out.puts "#{describe_target(platform, version)}  FAIL"
            output.each_line { |line| out.puts "  #{line}" }
            next
          end

          out.puts "#{describe_target(platform, version)}  PASS"
          rows = installed_wheels(target_dir).sort.map do |name, installed_version, tags|
            wheel = match_lock_wheel(lock_wheels, name, installed_version, tags)
            [name, installed_version, wheel ? wheel[:filename] : '(not in uv.lock)', wheel ? hash_status[wheel[:filename]] : 'NOT IN uv.lock']
          end
          print_table(out, [%w(Package Version Wheel Hash)] + rows)
        end
      end

      out.puts "", (passed ? "PASS: installs offline from the bundled wheels on every target" : "FAIL")
      passed
    end
    private_class_method :verify_dir

    def self.print_table(out, rows)
      return if rows.empty?

      widths = rows.transpose.map { |column| column.map(&:length).max }
      rows.each { |row| out.puts "  " + row.each_with_index.map { |cell, i| cell.ljust(widths[i]) }.join('  ').rstrip }
    end
    private_class_method :print_table

    # Exports uv.lock's runtime dependencies, with every wheel hash, without
    # touching the network
    def self.export_requirements(dir, tmp)
      requirements = File.join(tmp, 'requirements.txt')
      run_uv(dir, 'export', '--frozen', '--offline', '--no-dev', '--no-emit-project', '--no-header', '--no-annotate',
             '--format', 'requirements-txt', '-o', requirements, what: 'export requirements from uv.lock')
      requirements
    end
    private_class_method :export_requirements

    # Fails when the plugin is in a git repository and its uv.lock is
    # untracked or changed since the last commit, so the bundled wheels always
    # match a lock someone committed. Outside a repository, or with no git on
    # PATH, there is nothing to compare against.
    #
    # `openc3.sh cli rake build` mounts the plugin into a container whose user
    # does not own it, and git refuses such a repository as "dubious
    # ownership", which would skip this check without a word. safe.directory
    # lifts that for these read-only queries, and --no-ext-diff keeps the
    # repository's own config from running a diff program.
    def self.check_lock_committed(project_dir)
      git = ['git', '-c', 'safe.directory=*', '-C', project_dir]
      _, status = Open3.capture2e(*git, 'rev-parse', '--is-inside-work-tree')
      return unless status.success?

      _, tracked = Open3.capture2e(*git, 'ls-files', '--error-unmatch', 'uv.lock')
      _, unchanged = Open3.capture2e(*git, 'diff', '--quiet', '--no-ext-diff', 'HEAD', '--', 'uv.lock')
      return if tracked.success? && unchanged.success?

      raise Error, "uv.lock is not committed. Run `git add uv.lock` and commit it, so the bundled wheels match the lock in source control."
    rescue Errno::ENOENT
      nil
    end
    private_class_method :check_lock_committed

    def self.target_args(platform, version)
      args = []
      args += ['--python-platform', platform] if platform
      args += ['--python-version', version] if version
      args
    end
    private_class_method :target_args

    def self.describe_target(platform, version)
      [platform || 'this machine', version && "Python #{version}"].compact.join(' / ')
    end
    private_class_method :describe_target

    def self.run_uv(project_dir, *args, what:)
      output, status = Open3.capture2e('uv', *args, chdir: project_dir)
      raise Error, "Could not #{what}:\n#{output}" unless status.success?

      output
    end
    private_class_method :run_uv

    # PEP 503 normalization, which uv.lock already applies to its names
    def self.normalize(name)
      name.downcase.gsub(/[-_.]+/, '-')
    end
    private_class_method :normalize

    # The tags a wheel filename covers, expanding compressed tag sets
    # (PEP 425): "py2.py3-none-any" covers py2-none-any and py3-none-any.
    def self.filename_tags(filename)
      python, abi, platform = File.basename(filename, '.whl').split('-')[-3..]
      python.split('.').product(abi.split('.'), platform.split('.')).map { |tag| tag.join('-') }.sort
    end
    private_class_method :filename_tags

    # @return [Hash] normalized name => array of { version:, filename:, tags:, url:/path:, sha256: }
    def self.lock_wheels_by_name(lock)
      result = Hash.new { |hash, key| hash[key] = [] }
      Array(lock['package']).each do |package|
        Array(package['wheels']).each do |wheel|
          location = wheel['url'] || wheel['path']
          next unless location

          # A local version's "+" is percent-encoded in index URLs (torch-2.5.1%2Bcpu-...)
          filename = URI.decode_uri_component(File.basename(location.split(/[?#]/).first))
          result[normalize(package['name'])] << {
            version: package['version'], filename: filename, tags: filename_tags(filename),
            url: wheel['url'], path: wheel['path'], sha256: wheel['hash'].to_s.delete_prefix('sha256:'),
          }
        end
      end
      result
    end
    private_class_method :lock_wheels_by_name

    # @return [Array<Array>] [name, version, sorted tags] for every dist uv installed
    def self.installed_wheels(target_dir)
      Dir[File.join(target_dir, '*.dist-info')].map do |dist_info|
        metadata = File.read(File.join(dist_info, 'METADATA'))
        name = metadata[/^Name: *(.+)$/, 1].strip
        version = metadata[/^Version: *(.+)$/, 1].strip
        tags = File.read(File.join(dist_info, 'WHEEL')).scan(/^Tag: *(\S+)$/).flatten.sort
        [name, version, tags]
      end
    end
    private_class_method :installed_wheels

    def self.match_lock_wheel(lock_wheels, name, version, tags)
      candidates = lock_wheels[normalize(name)].select { |wheel| wheel[:tags] == tags }
      # A lock can hold two versions of one package under different markers
      candidates = candidates.select { |wheel| wheel[:version] == version } if candidates.length > 1
      candidates.length == 1 ? candidates[0] : nil
    end
    private_class_method :match_lock_wheel

    # Copies or downloads a locked wheel and checks it against uv.lock's hash
    def self.fetch_wheel(project_dir, wheel, destination)
      if wheel[:sha256].empty?
        raise Error, "uv.lock records no hash for #{wheel[:filename]}, so it cannot be verified. " \
                     "Lock against an index rather than find-links or a local path."
      end
      if wheel[:path]
        FileUtils.cp(File.expand_path(wheel[:path], project_dir), destination)
      else
        download(URI(wheel[:url]), destination)
      end
      actual = Digest::SHA256.file(destination).hexdigest
      return if actual == wheel[:sha256]

      FileUtils.rm_f(destination)
      raise Error, "#{wheel[:filename]} does not match uv.lock: expected sha256 #{wheel[:sha256]}, got #{actual}"
    end
    private_class_method :fetch_wheel

    def self.download(uri, destination, redirects: 5)
      raise Error, "Too many redirects fetching #{uri}" if redirects.zero?

      # Net::HTTP honors http_proxy/https_proxy/no_proxy from the environment
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
        request = Net::HTTP::Get.new(uri)
        http.request(request) do |response|
          case response
          when Net::HTTPSuccess
            File.open(destination, 'wb') { |file| response.read_body { |chunk| file.write(chunk) } }
          when Net::HTTPRedirection
            return download(URI.join(uri, response['location']), destination, redirects: redirects - 1)
          else
            raise Error, "Could not download #{uri}: HTTP #{response.code}"
          end
        end
      end
    end
    private_class_method :download

    # @param path [String] TOML file to parse
    # @return [Hash] the parsed document
    def self.read_toml(path)
      output, error, status = Open3.capture3('python3', '-c', TOML_TO_JSON, path)
      raise Error, "Could not read #{path}: #{error.strip}" unless status.success?

      JSON.parse(output)
    rescue Errno::ENOENT
      raise Error, "python3 (3.11 or newer) is required to read #{path}"
    end
  end
end
