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

# NOTE: Run this file from the root to get the .env vars set:
# cosmos % ruby scripts/release/package_audit.rb

require 'open3'
require 'fileutils'
require 'json'
require 'yaml'
require 'time'

$overall_apk = []
$overall_apt = []
$overall_rpm = []
$overall_dnf = []
$overall_gems = []
$overall_wheels = []
$overall_pnpm = []

ROOT_DIR = File.expand_path(File.join(__dir__, '..', '..'))

def prompt_yes_no(message, default: true)
  default_str = default ? 'Y/n' : 'y/N'
  print "#{message} [#{default_str}]: "
  STDOUT.flush
  response = STDIN.gets&.strip&.downcase
  return default if response.nil? || response.empty?
  response.start_with?('y')
end

# True if `new_v` increments the major component of `old_v` (semver-shaped).
# Both can be plain "1.2.3" or have a "v" prefix and/or trailing suffix like
# "-alpine". Returns false if either string doesn't look like semver.
def major_version_change?(old_v, new_v)
  old_m = old_v.to_s.match(/v?(\d+)\.(\d+)\.(\d+)/)
  new_m = new_v.to_s.match(/v?(\d+)\.(\d+)\.(\d+)/)
  return false unless old_m && new_m
  new_m[1].to_i > old_m[1].to_i
end

# Upgrade-aware prompt. Defaults to yes; if the change crosses a major version
# boundary, asks a follow-up "Are you sure?" that defaults to no.
def prompt_update?(message, current, new_version)
  return false unless prompt_yes_no(message)
  return true unless major_version_change?(current, new_version)
  prompt_yes_no("  Major version change (#{current} -> #{new_version}). Are you sure?", default: false)
end

# Update `KEY=value` (no quotes) on the same line. Used for Dockerfile ARGs,
# shell script variable assignments, --build-arg flags, and .env entries.
# Skips lines where the value is a shell variable expansion (`=${FOO}` or `=$FOO`)
# since those should stay as references, not be rewritten to a literal.
def update_key_value(path, key, new_value)
  unless File.exist?(path)
    puts "WARN: #{path} does not exist"
    return false
  end
  content = File.read(path)
  pattern = /^(.*\b#{Regexp.escape(key)})=(\S+)/
  matched = false
  new_content = content.gsub(pattern) do |full|
    value = $2
    if value.start_with?('$')
      full # leave shell-var references alone
    else
      matched = true
      "#{$1}=#{new_value}"
    end
  end
  unless matched
    puts "WARN: #{key} not found in #{path}"
    return false
  end
  return true if content == new_content
  File.write(path, new_content)
  puts "  Updated #{key}=#{new_value} in #{path.sub(ROOT_DIR + '/', '')}"
  true
end

def get_docker_version(path, arg: nil)
  args = {}
  version = ''
  File.open(path) do |file|
    file.each do |line|
      if line.include?("ARG")
        parts = line.split("ARG")[1].strip.split('=')
        args[parts[0]] = parts[1]
        if arg and line.include?(arg)
          return parts[1].strip
        end
      end
      if line.include?("FROM")
        # Remove "AS ..." qualifiers in the FROM line
        line.gsub!(/as\s+.*/i, '')
        version = line.split(':')[-1].strip
        # Check for an ARG variable
        if version.include?("${")
          version = args[version[2..-2]]
        end
        # Stop at the first FROM
        break
      end
    end
  end
  return version
end

def make_sorted_hash(name_versions)
  result = {}
  name_versions.sort!
  name_versions.each do |name, version, package|
    result[name] ||= [[], []]
    result[name][0] << version
    result[name][1] << package
  end
  result.each do |_name, data|
    data[0].uniq!
    data[1].uniq!
  end
  result
end

def breakup_versioned_package(line, name_versions, package)
  split_line = line.split('-')
  found = false
  (split_line.length - 1).times do |index|
    i = index + 1
    if (split_line[i][0] =~ /\d/) or split_line[i -1] == 'pubkey'
      name = split_line[0..(i - 1)].join('-')
      version = split_line[i..-1].join('-')
      name_versions << [name, version, package]
      found = true
      break
    end
  end
  raise "Couldn't breakup version for #{package}" unless found
end

def extract_apk(container)
  container_name = container[:name]
  name_versions = []
  results, stderr, status = Open3.capture3("docker run --entrypoint '' --rm --user root #{container_name} apk list -I")
  if status.exitstatus != 0
    puts "apk command failed with exit status #{status.exitstatus} for container #{container_name}"
    puts "Raw apk output:\n#{results}"
    puts "Raw apk error output:\n#{stderr}" unless stderr.strip.empty?
  end
  results.each_line do |line|
    package = line.split(' ')[0]
    breakup_versioned_package(package, name_versions, package)
  end
  $overall_apk.concat(name_versions)
  make_sorted_hash(name_versions)
end

def extract_apt(container)
  container_name = container[:name]
  results, stderr, status = Open3.capture3("docker run --entrypoint '' --rm --user root #{container_name} apt list --installed")
  if status.exitstatus != 0
    puts "apt command failed with exit status #{status.exitstatus} for container #{container_name}"
    puts "Raw apt output:\n#{results}"
    puts "Raw apt error output:\n#{stderr}" unless stderr.strip.empty?
  end
  name_versions = []
  results.each_line do |line|
    next if line =~ /Listing/
    name = line.split("/now")[0]
    version = line.split(' ')[1]
    name_versions << [name, version, nil]
  end
  $overall_apt.concat(name_versions)
  make_sorted_hash(name_versions)
end

def extract_rpm(container)
  container_name = container[:name]
  name_versions = []
  results, stderr, status = Open3.capture3("docker run --entrypoint '' --rm --user root #{container_name} rpm -qa")
  if status.exitstatus != 0
    puts "rpm command failed with exit status #{status.exitstatus} for container #{container_name}"
    puts "Raw rpm output:\n#{results}"
    puts "Raw rpm error output:\n#{stderr}" unless stderr.strip.empty?
  end
  results.each_line do |line|
    full_package = line.strip
    split_line = full_package.split('.')
    if split_line.length > 1
      split_line = split_line[0..-3] # Remove el8 and arch
    end
    line = split_line.join('.')
    breakup_versioned_package(line, name_versions, full_package)
  end
  $overall_rpm.concat(name_versions)
  make_sorted_hash(name_versions)
end

def extract_dnf(container)
  container_name = container[:name]
  name_versions = []
  results, stderr, status = Open3.capture3("docker run --entrypoint '' --rm --user root #{container_name} dnf list --installed")
  if status.exitstatus != 0
    puts "dnf command failed with exit status #{status.exitstatus} for container #{container_name}"
    puts "Raw dnf output:\n#{results}"
    puts "Raw dnf error output:\n#{stderr}" unless stderr.strip.empty?
  end
  results.each_line do |line|
    next if line =~ /Installed Packages/ || line.strip.empty?
    parts = line.split(' ')
    name_versions << [parts[0], parts[1], nil]
  end
  $overall_dnf.concat(name_versions)
  make_sorted_hash(name_versions)
end

def extract_gems(container)
  container_name = container[:name]
  name_versions = []
  lines = `docker run --rm #{container_name} gem list --local`
  lines.each_line do |line|
    split_line = line.strip.split(' ')
    name = split_line[0]
    rest = split_line[1..-1].join(' ')
    versions = rest[1..-2]
    versions.gsub!("default: ", "")
    versions = versions.split(',')
    name_versions << [name, versions, nil]
  end
  $overall_gems.concat(name_versions)
  make_sorted_hash(name_versions)
end

def extract_wheels(container)
  container_name = container[:name]
  name_versions = []
  lines = `docker run --rm #{container_name} pip list`
  lines.each_line do |line|
    split_line = line.strip.split(' ')
    name = split_line[0]
    version = split_line[1]
    name_versions << [name, version, nil]
  end
  $overall_wheels.concat(name_versions)
  make_sorted_hash(name_versions)
end

def extract_pnpm(container)
  container_name = container[:name]
  name_versions = []
  pnpm_lock_paths = container[:pnpm]
  pnpm_lock_paths.each do |path|
    local_name = path.split('/')[-1]
    id = `docker create #{container_name}`.strip
    `docker cp #{id}:#{path} .`
    `docker rm -v #{id}`
    begin
      data = File.read(local_name)
      name_versions.concat(process_pnpm(data))
    ensure
      FileUtils.rm_f(local_name)
    end
  end
  $overall_pnpm.concat(name_versions)
  make_sorted_hash(name_versions)
end

def process_pnpm(data)
  result = []
  begin
    lock_data = YAML.safe_load(data)
    if lock_data['packages']
      lock_data['packages'].each do |package_key, _package_info|
        next if package_key.nil? || package_key.empty?

        if package_key.start_with?('@') && package_key.count('@') >= 2 # like '@babel/core@7.28.4'
          last_at_index = package_key.rindex('@')
          name = package_key[0...last_at_index]
          version = package_key[last_at_index + 1..-1]
        elsif !package_key.start_with?('@') && package_key.include?('@') # like 'vue@3.5.21'
          parts = package_key.split('@')
          name = parts[0]
          version = parts[1]
        else
          name = package_key
          version = 'unknown'
        end
        result << [name, version, nil] if !name&.empty? && !version&.empty?
      end
    end
  rescue StandardError => e
    puts "Error parsing pnpm-lock.yaml: #{e.message}"
  end

  result
end

def build_section(title, name_version_hash, show_full_packages = false)
  report = ""
  report << "#{title}:\n"
  name_version_hash.each do |name, data|
    versions = data[0]
    packages = data[1]
    if show_full_packages
      report << "  #{name} (#{versions.join(', ')}) [#{packages.join(', ')}]\n"
    else
      report << "  #{name} (#{versions.join(', ')})\n"
    end
  end
  report
end

def build_summary_report(containers)
  report = ""
  report << "OpenC3 COSMOS Package Report Summary\n"
  report << ("-" * 80)
  report << "\n\nCreated: #{Time.now}\n\n"
  report << "Containers:\n"
  containers.each do |container|
    if container[:base_image]
      report << "  #{container[:name]} - Base Image: #{container[:base_image]}\n"
    else
      report << "  #{container[:name]}\n"
    end
  end
  report << "\n"
  if $overall_apk.length > 0
    report << build_section("APK Packages", make_sorted_hash($overall_apk), false)
    report << "\n"
  end
  if $overall_apt.length > 0
    report << build_section("APT Packages", make_sorted_hash($overall_apt), false)
    report << "\n"
  end
  if $overall_rpm.length > 0
    report << build_section("RPM Packages", make_sorted_hash($overall_rpm), true)
    report << "\n"
  end
  if $overall_dnf.length > 0
    report << build_section("DNF Packages", make_sorted_hash($overall_dnf), true)
    report << "\n"
  end
  if $overall_gems.length > 0
    report << build_section("Ruby Gems", make_sorted_hash($overall_gems), false)
    report << "\n"
  end
  if $overall_wheels.length > 0
    report << build_section("Python Wheels", make_sorted_hash($overall_wheels), false)
    report << "\n"
  end
  if $overall_pnpm.length > 0
    report << build_section("Node Packages", make_sorted_hash($overall_pnpm), false)
    report << "\n"
  end
  report
end

def build_container_report(container)
  report = ""
  report << "Container: #{container[:name]}\n"
  report << "Base Image: #{container[:base_image]}\n" if container[:base_image]
  report << build_section("APK Packages", extract_apk(container), false) if container[:apk]
  report << build_section("APT Packages", extract_apt(container), false) if container[:apt]
  report << build_section("RPM Packages", extract_rpm(container), true) if container[:rpm]
  report << build_section("DNF Packages", extract_dnf(container), true) if container[:dnf]
  report << build_section("Ruby Gems", extract_gems(container), false) if container[:gems]
  report << build_section("Python Wheels", extract_wheels(container), false) if container[:python]
  report << build_section("Node Packages", extract_pnpm(container), false) if container[:pnpm]
  report << "\n"
  report
end

def build_report(containers)
  report = ""
  report << "Individual Container Reports\n"
  report << ("-" * 80)
  report << "\n\n"
  containers.each do |container|
    report << build_container_report(container)
  end
  report
end

def check_debian(client)
  release = ENV.fetch('DEBIAN_RELEASE')
  ruby_version = ENV.fetch('RUBY_VERSION')

  # Verify the pinned base image tags actually exist on Docker Hub
  ruby_tag = "#{ruby_version}-slim-#{release}"
  unless docker_tag_exists?(client, 'library/ruby', ruby_tag)
    puts "ERROR: Could not find ruby image tag: #{ruby_tag}"
  end
  debian_tag = "#{release}-slim"
  unless docker_tag_exists?(client, 'library/debian', debian_tag)
    puts "ERROR: Could not find debian image tag: #{debian_tag}"
  end

  # Check for a newer Ruby minor/major line built on the same Debian release.
  # Ruby uses rolling "X.Y-slim-<release>" tags, so there is no patch to bump.
  major, minor = ruby_version.split('.').map(&:to_i)
  new_ruby = nil
  [[major, minor + 1], [major + 1, 0]].each do |mj, mn|
    candidate = "#{mj}.#{mn}"
    if docker_tag_exists?(client, 'library/ruby', "#{candidate}-slim-#{release}")
      new_ruby = candidate
      break
    end
  end
  puts "NOTE: Ruby has a newer version available: #{new_ruby} (current #{ruby_version})" if new_ruby

  # Debian stable releases roll on a multi-year cadence and require manual review
  # of the release notes (codenames don't sort by version), so just remind.
  puts "NOTE: Building on Debian '#{release}'. Verify it is still the current stable release: https://www.debian.org/releases/"

  # Verify the roadmap.md documents the current Debian release
  roadmap_path = File.join(ROOT_DIR, 'docs.openc3.com/docs/development/roadmap.md')
  if File.exist?(roadmap_path)
    roadmap = File.read(roadmap_path)
    unless roadmap.downcase.include?("debian #{release}") || roadmap.downcase.include?("debian-#{release}")
      puts "WARN: roadmap.md does not mention Debian #{release}. Update the base OS version in docs.openc3.com/docs/development/roadmap.md"
    end
  else
    puts "WARN: Could not find roadmap.md at #{roadmap_path}"
  end

  return unless new_ruby
  if prompt_update?("Update Ruby from #{ruby_version} to #{new_ruby}?", ruby_version, new_ruby)
    update_debian_files('RUBY_VERSION', new_ruby)
  end
end

# Update a build variable (RUBY_VERSION or DEBIAN_RELEASE) in the .env and any
# Dockerfile that pins it as a default ARG, then reload the in-process ENV.
def update_debian_files(key, new_value)
  update_key_value(File.join(ROOT_DIR, '.env'), key, new_value)
  Dir.glob(File.join(ROOT_DIR, '**', 'Dockerfile*')).each do |path|
    next unless File.read(path).match?(/^ARG\s+#{Regexp.escape(key)}=/)
    update_key_value(path, key, new_value)
  end
  ENV[key] = new_value
  puts "  NOTE: also update docs.openc3.com/docs/development/roadmap.md and openc3-ruby/Dockerfile-ubi if needed"
end

# Returns the new version selected by the user (and applied), or nil
def check_versitygw(client, versitygw_version)
  puts "Checking versitygw against version: #{versitygw_version}"
  resp = client.get('https://api.github.com/repos/versity/versitygw/releases').body
  releases = JSON.parse(resp)
  versions = releases.map { |r| r['tag_name'] }
  candidates = validate_versions(versions, versitygw_version, 'versitygw')
  new_version = prompt_for_upgrade('versitygw (will download binaries)', versitygw_version, candidates)

  # Self-heal: even when up to date, (re)download if the configured version's
  # tarballs are missing from openc3-buckets (e.g. the version string was bumped
  # without the matching binaries being fetched).
  if new_version.nil?
    return nil if versitygw_binaries_present?(versitygw_version)
    puts "versitygw #{versitygw_version} binaries missing from openc3-buckets; downloading."
    new_version = versitygw_version
  end

  return nil unless download_versitygw_binaries(new_version)
  update_key_value(File.join(ROOT_DIR, 'openc3-buckets/Dockerfile'), 'OPENC3_VERSITYGW_VERSION', new_version)
  update_key_value(File.join(ROOT_DIR, 'openc3-buckets/Dockerfile-ubi'), 'OPENC3_VERSITYGW_VERSION', new_version)
  update_key_value(File.join(ROOT_DIR, 'scripts/release/build_multi_arch.sh'), 'OPENC3_VERSITYGW_VERSION', new_version)
  update_key_value(File.join(ROOT_DIR, 'scripts/linux/openc3_build_ubi.sh'), 'OPENC3_VERSITYGW_VERSION', new_version)
  new_version
end

# True if both Linux release tarballs for `version` already exist in openc3-buckets.
def versitygw_binaries_present?(version)
  %w[arm64 x86_64].all? do |arch|
    File.exist?(File.join(ROOT_DIR, 'openc3-buckets', "versitygw_#{version}_Linux_#{arch}.tar.gz"))
  end
end

# Download both Linux versitygw release tarballs (arm64 + x86_64) into
# openc3-buckets/ and remove any other-version versitygw Linux tarballs left
# behind. Returns true on success. On any download failure the partial new files
# are removed and the existing tarballs are left untouched so the build still has
# a working version.
def download_versitygw_binaries(version)
  buckets_dir = File.join(ROOT_DIR, 'openc3-buckets')
  arches = %w[arm64 x86_64]
  new_paths = arches.map { |arch| File.join(buckets_dir, "versitygw_#{version}_Linux_#{arch}.tar.gz") }
  arches.zip(new_paths).each do |arch, path|
    url = "https://github.com/versity/versitygw/releases/download/#{version}/versitygw_#{version}_Linux_#{arch}.tar.gz"
    puts "  Downloading #{url}"
    unless system("curl -fSL #{url} -o #{path}")
      puts "ERROR: failed to download #{url}"
      new_paths.each { |p| FileUtils.rm_f(p) }
      return false
    end
  end
  if new_paths.any? { |p| File.size(p) < 1_000_000 }
    puts "ERROR: downloaded versitygw tarball looks invalid (too small) - check the release URL"
    new_paths.each { |p| FileUtils.rm_f(p) }
    return false
  end
  # Remove tarballs for any other version so only the current pair remains.
  Dir.glob(File.join(buckets_dir, 'versitygw_*_Linux_*.tar.gz')).each do |p|
    FileUtils.rm_f(p) unless new_paths.include?(p)
  end
  puts "  Updated versitygw binaries to #{version}"
  true
end

def check_tsdb(client, tsdb_version)
  puts "Checking tsdb against version: #{tsdb_version}"
  resp = client.get('https://api.github.com/repos/questdb/questdb/releases').body
  releases = JSON.parse(resp)
  versions = releases.map { |r| r['tag_name'] }
  candidates = validate_versions(versions, tsdb_version, 'tsdb')
  new_version = prompt_for_upgrade('questdb/tsdb', tsdb_version, candidates)
  return nil unless new_version
  update_key_value(File.join(ROOT_DIR, 'openc3-tsdb/Dockerfile'), 'OPENC3_TSDB_VERSION', new_version)
  new_version
end

# Sync the traefik/versitygw versions referenced from the build scripts with
# whatever the canonical Dockerfile says (used as a safety check after the
# per-image prompts above run, in case the user previously edited only one).
def check_build_files(versitygw_version, traefik_version)
  build_multi = File.join(ROOT_DIR, 'scripts/release/build_multi_arch.sh')
  build_ubi = File.join(ROOT_DIR, 'scripts/linux/openc3_build_ubi.sh')
  [[build_multi, 'OPENC3_VERSITYGW_VERSION', versitygw_version, 'build_multi_arch.sh', 'openc3-buckets Dockerfile'],
   [build_multi, 'OPENC3_TRAEFIK_RELEASE',  traefik_version,  'build_multi_arch.sh', 'traefik Dockerfile'],
   [build_ubi,   'OPENC3_VERSITYGW_VERSION', versitygw_version, 'openc3_build_ubi.sh', 'openc3-buckets Dockerfile'],
   [build_ubi,   'OPENC3_TRAEFIK_RELEASE',  traefik_version,  'openc3_build_ubi.sh', 'traefik Dockerfile']].each do |path, key, target, short, source|
    next unless File.exist?(path)
    content = File.read(path)
    content.each_line do |line|
      m = line.match(/\b#{Regexp.escape(key)}=(\S+)/)
      next unless m
      current = m[1]
      next if current.start_with?('$') # skip shell variable references
      current = current.chomp('\\').strip
      next if current.empty? || current == target
      if prompt_yes_no("#{short}: #{key} is #{current} but #{source} is #{target}. Sync?")
        update_key_value(path, key, target)
      end
      break
    end
  end
end

# Returns an array of candidate upgrade versions from highest to lowest tier
# (major → minor → patch), each preserving any leading "v" prefix and trailing
# suffix (e.g. "-alpine"). Empty array if up to date or current is missing.
def validate_versions(versions, version, name)
  unless versions.include?(version)
    puts "ERROR: Could not find #{name} image: #{version}"
    return []
  end

  parts = version.match(/^(v?)(\d+)\.(\d+)\.(\d+)(.*)$/)
  unless parts
    puts "#{name} is up to date with #{version}"
    return []
  end
  prefix, major, minor, patch, suffix = parts.captures

  major_candidate = nil
  ["#{major.to_i + 1}.1.0", "#{major.to_i + 1}.0.1", "#{major.to_i + 1}.0.0"].each do |v|
    full = "#{prefix}#{v}#{suffix}"
    if versions.include?(full)
      major_candidate = full
      break
    end
  end

  minor_candidate = nil
  ["#{major}.#{minor.to_i + 1}.1", "#{major}.#{minor.to_i + 1}.0"].each do |v|
    full = "#{prefix}#{v}#{suffix}"
    if versions.include?(full)
      minor_candidate = full
      break
    end
  end

  patch_full = "#{prefix}#{major}.#{minor}.#{patch.to_i + 1}#{suffix}"
  patch_candidate = versions.include?(patch_full) ? patch_full : nil

  candidates = [major_candidate, minor_candidate, patch_candidate].compact
  if candidates.empty?
    puts "#{name} is up to date with #{version}"
    return []
  end

  puts "NOTE: #{name} has a new major version: #{major_candidate}, Current Version: #{version}" if major_candidate
  puts "NOTE: #{name} has a new minor version: #{minor_candidate}, Current Version: #{version}" if minor_candidate
  puts "NOTE: #{name} has a new patch version: #{patch_candidate}, Current Version: #{version}" if patch_candidate

  candidates
end

# Walk candidate upgrades from highest to lowest tier, prompting per candidate.
# Returns the first version the user accepts, or nil if all are declined / list
# is empty.
def prompt_for_upgrade(name, current, candidates)
  candidates.each do |new_version|
    return new_version if prompt_update?("Update #{name} from #{current} to #{new_version}?", current, new_version)
  end
  nil
end

def check_grafana(client, containers, dockerfile_path: nil, build_files: [])
  container = containers.select { |val| val[:name].include?('grafana') }[0]
  version = container[:base_image].split(':')[-1]
  # Both grafana/grafana and grafana/grafana-oss share the same version tags;
  # use grafana/grafana to match the container base_image above.
  versions = docker_hub_candidate_tags(client, 'grafana/grafana', version)
  candidates = validate_versions(versions, version, 'grafana')
  new_version = prompt_for_upgrade('grafana', version, candidates)
  return nil unless new_version
  if dockerfile_path && File.exist?(dockerfile_path)
    update_key_value(dockerfile_path, 'GRAFANA_VERSION', new_version)
  end
  build_files.each do |path|
    update_key_value(path, 'GRAFANA_VERSION', new_version)
  end
  new_version
end

def check_keycloak(client, containers, dockerfile_path: nil)
  container = containers.select { |val| val[:name].include?('keycloak') }[0]
  version = container[:base_image].split(':')[-1]
  versions = []
  # They only give us a partial list and then a Link in the header to request the rest
  url_root = 'https://quay.io'
  url = '/v2/keycloak/keycloak/tags/list'
  while true
    resp = client.get("#{url_root}#{url}")
    versions.concat(JSON.parse(resp.body)['tags'])
    if resp.headers["link"]
      url = resp.headers["link"].split(';')[0][1..-2]
    else
      break
    end
  end
  candidates = validate_versions(versions, version, 'keycloak')
  new_version = prompt_for_upgrade('keycloak', version, candidates)
  return nil unless new_version
  if dockerfile_path && File.exist?(dockerfile_path)
    update_key_value(dockerfile_path, 'OPENC3_KEYCLOAK_VERSION', new_version)
  end
  new_version
end

# Returns true if `tag` is an exact tag on the Docker Hub repository `repo`.
# Uses the `?name=` substring filter so we don't have to paginate through
# thousands of tags. The filter is substring-only, so we still verify an exact
# name match against each returned result.
def docker_tag_exists?(client, repo, tag)
  resp = client.get("https://registry.hub.docker.com/v2/repositories/#{repo}/tags?name=#{tag}&page_size=100")
  return false unless resp.status == 200
  data =
    begin
      JSON.parse(resp.body)
    rescue JSON::ParserError
      { 'results' => [] }
    end
  Array(data['results']).any? { |r| r['name'] == tag }
end

# Build the candidate set validate_versions cares about and ask Docker Hub
# whether each one exists, instead of fetching the full tag list (which is
# capped at 100 per page and contains thousands of variant tags).
def docker_hub_candidate_tags(client, repo, version)
  parts = version.match(/^(v?)(\d+)\.(\d+)\.(\d+)(.*)$/)
  return [] unless parts
  prefix, major, minor, patch, suffix = parts.captures
  candidates = [
    version,
    "#{prefix}#{major.to_i + 1}.1.0#{suffix}",
    "#{prefix}#{major.to_i + 1}.0.1#{suffix}",
    "#{prefix}#{major.to_i + 1}.0.0#{suffix}",
    "#{prefix}#{major}.#{minor.to_i + 1}.1#{suffix}",
    "#{prefix}#{major}.#{minor.to_i + 1}.0#{suffix}",
    "#{prefix}#{major}.#{minor}.#{patch.to_i + 1}#{suffix}",
  ]
  candidates.uniq.select { |c| docker_tag_exists?(client, repo, c) }
end

def check_container_version(client, containers, image_name)
  container = containers.select { |val| val[:name].include?(image_name) }[0]
  name, version = container[:base_image].split(':')
  repo =
    case image_name
    when 'traefik' then 'library/traefik'
    when 'redis' then 'valkey/valkey'
    else raise "Unsupported image_name: #{image_name}"
    end
  versions = docker_hub_candidate_tags(client, repo, version)
  candidates = validate_versions(versions, version, name)
  new_version = prompt_for_upgrade(name, version, candidates)
  return nil unless new_version
  case image_name
  when 'traefik'
    update_key_value(File.join(ROOT_DIR, 'openc3-traefik/Dockerfile'), 'OPENC3_TRAEFIK_RELEASE', new_version)
    update_key_value(File.join(ROOT_DIR, 'scripts/release/build_multi_arch.sh'), 'OPENC3_TRAEFIK_RELEASE', new_version)
    update_key_value(File.join(ROOT_DIR, 'scripts/linux/openc3_build_ubi.sh'), 'OPENC3_TRAEFIK_RELEASE', new_version)
  when 'redis'
    update_key_value(File.join(ROOT_DIR, 'openc3-redis/Dockerfile'), 'OPENC3_REDIS_VERSION', new_version)
  else
    raise "Unsupported image_name: #{image_name}"
  end
  new_version
end

def check_anycable(client, container_name)
  anycable = `docker run --rm #{container_name} /usr/bin/anycable-go --version`.strip
  puts "Raw anycable-go version: #{anycable}"
  any_cable_version = anycable.split('version:')[-1].split('-')[0].strip
  # The anycable-go binaries ship as release assets on the anycable/anycable repo
  # (the anycable-go repo's own tags lag behind).
  resp = client.get('https://api.github.com/repos/anycable/anycable/releases?per_page=30').body
  releases = JSON.parse(resp)
  versions = releases.map { |r| r['tag_name'] }.compact.reject { |v| v.include?('-') }
  candidates = validate_versions(versions, "v#{any_cable_version}", 'anycable-go')
  new_version = prompt_for_upgrade('anycable-go (will download binaries)', "v#{any_cable_version}", candidates)
  return nil unless new_version
  ver = new_version.sub(/^v/, '')
  amd_url = "https://github.com/anycable/anycable/releases/download/v#{ver}/anycable-go-linux-amd64"
  arm_url = "https://github.com/anycable/anycable/releases/download/v#{ver}/anycable-go-linux-arm64"
  amd_path = File.join(ROOT_DIR, 'openc3-ruby/anycable-go-linux-amd64')
  arm_path = File.join(ROOT_DIR, 'openc3-ruby/anycable-go-linux-arm64')
  system("curl -fSL #{amd_url} -o #{amd_path}") || (puts("ERROR: failed to download #{amd_url}"); return nil)
  system("curl -fSL #{arm_url} -o #{arm_path}") || (puts("ERROR: failed to download #{arm_url}"); return nil)
  if File.size(amd_path) < 1_000_000 || File.size(arm_path) < 1_000_000
    puts "ERROR: downloaded anycable-go binaries look invalid (check release URL)"
  else
    puts "  Updated anycable-go binaries to #{new_version}"
  end
  new_version
end

def check_tool_base(path, base_pkgs, force: false)
  Dir.chdir(path) do
    # List the remote tags and sort reverse order (latest on top)
    # Pipe to sed to get the second line because the output looks like:
    #   6b7bfd3c201c1185129e819e02dc2505dbb82994	refs/tags/v7.0.96^{}
    #   fd525f20da2351e5aa0f02f0640036ca7bd52f19	refs/tags/v7.0.96
    # Then get the second column which is the tag
    md = `git ls-remote --tags --sort=-v:refname https://github.com/Templarian/MaterialDesign-Webfont.git | sed -n 2p | awk '{print $2}'`
    # Process refs/tags/v7.0.96 into 7.0.96
    latest = md.split('/')[-1].strip[1..-1]
    existing = Dir['public/css/materialdesignicons-*'][-1]
    existing_version = existing.to_s[/(\d+\.\d+\.\d+)/, 1]
    if !existing.include?(latest) && prompt_update?("Update MaterialDesignIcons from #{existing} to #{latest}?", existing_version, latest)
      puts "Existing MaterialDesignIcons: #{existing}, doesn't match latest: #{latest}. Upgrading..."
      `curl https://cdnjs.cloudflare.com/ajax/libs/MaterialDesign-Webfont/#{latest}/css/materialdesignicons.min.css --output public/css/materialdesignicons-#{latest}.min.css`
      `curl https://cdnjs.cloudflare.com/ajax/libs/MaterialDesign-Webfont/#{latest}/css/materialdesignicons.css.map --output public/css/materialdesignicons.css.map`
      `curl https://cdnjs.cloudflare.com/ajax/libs/MaterialDesign-Webfont/#{latest}/fonts/materialdesignicons-webfont.eot --output public/fonts/materialdesignicons-webfont.eot`
      `curl https://cdnjs.cloudflare.com/ajax/libs/MaterialDesign-Webfont/#{latest}/fonts/materialdesignicons-webfont.ttf --output public/fonts/materialdesignicons-webfont.ttf`
      `curl https://cdnjs.cloudflare.com/ajax/libs/MaterialDesign-Webfont/#{latest}/fonts/materialdesignicons-webfont.woff --output public/fonts/materialdesignicons-webfont.woff`
      `curl https://cdnjs.cloudflare.com/ajax/libs/MaterialDesign-Webfont/#{latest}/fonts/materialdesignicons-webfont.woff2 --output public/fonts/materialdesignicons-webfont.woff2`
      FileUtils.rm(existing)

      # Now update the files with references to materialdesignicons
      files = ["public/index.html"]
      # The base also has to update index.html in openc3-tool-base
      files << "../packages/openc3-tool-base/public/index.html" unless path.include?('enterprise')
      files.each do |filename|
        html = File.read(filename)
        html.gsub!(/materialdesignicons-.+\.min\.css/, "materialdesignicons-#{latest}.min.css")
        html.gsub!(/woff2\?v=.+/, "woff2?v=#{latest}")
        File.open(filename, 'w') {|file| file.puts html }
      end
    end

    # Ensure various js files match their package.json versions
    # This Hash syntax turns an array into a hash with the array values as keys
    packages = Hash[base_pkgs.each_with_object(nil).to_a]
    packages.keys.each do |package|
      File.open('package.json') do |file|
        file.each do |line|
          if line.include?("\"#{package}\":")
            packages[package] = line.split(':')[-1].strip.split('"')[1]
          end
        end
      end
    end
    packages.each do |package, latest|
      # vue and vuetify are special cases due to the package names
      alt_package = package
      if package == 'vue'
        alt_package = 'vue.global.prod'
      elsif package == 'vuetify'
        alt_package = 'vuetify-labs'
      end
      # Ensure we're only matching package names followed by numbers
      # This prevents vue- from matching vue-router-
      existing = Dir["public/js/#{alt_package}-[0-9]*"][0]
      if !latest
        puts "ERROR: Could not find latest version for #{package} in #{Dir.pwd}/package.json"
        next
      end
      if !existing && !force
        puts "ERROR: Could not find existing package #{alt_package} in #{Dir.pwd}/public/js (use FORCE=1 to download it fresh)"
        next
      end
      existing_version = existing.to_s[/(\d+\.\d+\.\d+)/, 1]
      version_matches = existing && existing.include?(latest)
      from_label = existing || 'none'
      prompt = version_matches ? "Re-download #{package} (#{alt_package}) #{latest}?" : "Update #{package} (#{alt_package}) from #{from_label} to #{latest}?"
      if (force || !version_matches) && prompt_update?(prompt, existing_version || latest, latest)
        puts "Updating #{package} to #{latest} (existing: #{from_label})..."
        # Handle nuances in individual packages
        # Search here to get the URLs: https://cdnjs.com/
        case package
        when 'vue'
          outfile = "public/js/#{package}.global-#{latest}.js"
          `curl https://cdn.jsdelivr.net/npm/#{package}@#{latest}/dist/#{package}.global.js --output #{outfile}`
          validate_outfile(outfile, package, latest)
          # Remove the old non-prod base file only when the version changed; on a
          # forced same-version re-download the new file has the same name.
          if existing && !version_matches
            old_base_filename = existing.sub('vue.global.prod', 'vue.global').sub('.min.js', '.js')
            FileUtils.rm_f old_base_filename
          end
          outfile = "public/js/#{package}.global.prod-#{latest}.min.js"
          `curl https://cdn.jsdelivr.net/npm/#{package}@#{latest}/dist/#{package}.global.prod.js --output #{outfile}`
          validate_outfile(outfile, package, latest)
        when 'single-spa'
          outfile = "public/js/#{package}-#{latest}.min.js"
          `curl https://cdn.jsdelivr.net/npm/#{package}@#{latest}/lib/es5/system/#{package}.min.js --output #{outfile}`
          validate_outfile(outfile, package, latest)
          outfile = "public/js/#{package}-#{latest}.min.js.map"
          `curl https://cdn.jsdelivr.net/npm/#{package}@#{latest}/lib/es5/system/#{package}.min.js.map --output #{outfile}`
          validate_outfile(outfile, package, latest)
        when 'vuetify'
          old_css = Dir["public/css/vuetify-*"][0] # Delete the existing vuetify css (if a different version)
          FileUtils.rm_f(old_css) if old_css && !old_css.include?(latest)
          outfile = "public/css/#{package}-labs-#{latest}.min.css"
          `curl https://cdn.jsdelivr.net/npm/#{package}@#{latest}/dist/#{package}-labs.min.css --output #{outfile}`
          validate_outfile(outfile, package, latest)
          outfile = "public/js/#{package}-labs-#{latest}.min.js"
          `curl https://cdn.jsdelivr.net/npm/#{package}@#{latest}/dist/#{package}-labs.min.js --output #{outfile}`
          validate_outfile(outfile, package, latest)
        when 'import-map-overrides'
          outfile = "public/js/#{package}-#{latest}.min.js"
          `curl https://cdn.jsdelivr.net/npm/#{package}@#{latest}/dist/import-map-overrides.js --output #{outfile}`
          validate_outfile(outfile, package, latest)
          outfile = "public/js/#{package}-#{latest}.min.js.map"
          `curl https://cdn.jsdelivr.net/npm/#{package}@#{latest}/dist/import-map-overrides.js.map --output #{outfile}`
          validate_outfile(outfile, package, latest)
        when 'keycloak-js'
          outfile = "public/js/#{package}-#{latest}.min.js"
          `curl https://cdn.jsdelivr.net/npm/#{package}@#{latest}/lib/keycloak.min.js --output #{outfile}`
          validate_outfile(outfile, package, latest)
        when 'pinia'
          # pinia ships browser globals as pinia.iife.prod.js (minified prod build)
          outfile = "public/js/#{package}-#{latest}.min.js"
          `curl https://cdn.jsdelivr.net/npm/#{package}@#{latest}/dist/#{package}.iife.prod.js --output #{outfile}`
          validate_outfile(outfile, package, latest)
        when 'systemjs'
          # systemjs browser build lives at dist/system.min.js (not systemjs.min.js)
          outfile = "public/js/#{package}-#{latest}.min.js"
          `curl https://cdn.jsdelivr.net/npm/#{package}@#{latest}/dist/system.min.js --output #{outfile}`
          validate_outfile(outfile, package, latest)
        when 'vue-router'
          # vue-router ships the minified prod IIFE global at dist/vue-router.global.prod.js
          outfile = "public/js/#{package}-#{latest}.min.js"
          `curl https://cdn.jsdelivr.net/npm/#{package}@#{latest}/dist/#{package}.global.prod.js --output #{outfile}`
          validate_outfile(outfile, package, latest)
        else
          outfile = "public/js/#{package}-#{latest}.min.js"
          `curl https://cdn.jsdelivr.net/npm/#{package}@#{latest}/dist/#{package}.min.js --output #{outfile}`
          validate_outfile(outfile, package, latest)
        end
        FileUtils.rm_f existing if existing && !version_matches
        # Now update the public/index.html with references to <package>-<version>.min.js
        html = File.read("public/index.html")
        html.gsub!(/#{alt_package}-\d+\.\d+\.\d+\.min\.js/, "#{alt_package}-#{latest}.min.js")
        html.gsub!(/#{alt_package}-\d+\.\d+\.\d+\.min\.css/, "#{alt_package}-#{latest}.min.css")
        File.open("public/index.html", 'w') {|file| file.puts html }
        if package == 'keycloak-js'
          html = File.read('public/js/auth.js')
          html.gsub!(/#{alt_package}-\d+\.\d+\.\d+\.min\.js/, "#{alt_package}-#{latest}.min.js")
          File.open('public/js/auth.js', 'w') {|file| file.puts html }
        end
      end
    end
  end
end

def validate_outfile(outfile, package, latest)
  data = File.read(outfile)
  if data.length < 100
    puts "ERROR: While updating #{package} to #{latest} got the following:\n#{data}\n\nCheck the package and version."
    FileUtils.rm outfile
    exit 1
  end
end

# Walk `bundle outdated --strict` (only gems whose newest version is reachable
# under the current Gemfile constraints) and prompt for each. Without --strict,
# bundle lists gems where a newer version exists on rubygems even when the
# Gemfile constraint blocks the bump, so `bundle update <gem>` becomes a no-op
# and the user thinks acceptance did nothing.
#
# The openc3-cosmos-cmd-tlm-api / -script-runner-api Gemfiles depend on the
# local `openc3` gem via ENV['OPENC3_PATH'] (falling back to a rubygems version
# that may not exist yet), so we point OPENC3_PATH at the openc3/ directory in
# this repo for every bundle call.
def update_outdated_gems(dir, extra_env = {})
  label = dir.sub(ROOT_DIR + '/', '')
  puts "\nChecking outdated gems in #{label}:"
  updated = 0
  env = { 'OPENC3_PATH' => File.join(ROOT_DIR, 'openc3') }.merge(extra_env)
  Dir.chdir(dir) do
    system(env, 'bundle install') unless File.exist?('Gemfile.lock')

    strict_output, _stderr, _status = Open3.capture3(env, 'bundle outdated --parseable --strict')
    strict_output.each_line do |line|
      m = line.match(/^([\w\-.]+)\s*\(newest\s+([\w\-.]+),\s*installed\s+([\w\-.]+)/)
      next unless m
      name, newest, installed = m.captures
      next if newest == installed
      if prompt_update?("[#{label}] Update gem #{name} from #{installed} to #{newest}?", installed, newest)
        system(env, "bundle update #{name}")
        updated += 1
      end
    end
  end
  puts "  No updatable gems." if updated == 0
  updated
end

# Walk `uv pip list --outdated` in a uv-managed project and prompt per package.
# Direct-dep constraint violations are skipped at prompt time (analogous to
# `bundle outdated --strict`). Transitive constraint blocks are detected
# post-hoc by checking that the uv.lock actually changed.
def update_outdated_wheels(dir)
  label = dir.sub(ROOT_DIR + '/', '')
  puts "\nChecking outdated wheels in #{label}:"
  updated = 0
  Dir.chdir(dir) do
    direct_constraints = read_pyproject_dep_constraints('pyproject.toml')
    output, _stderr, _status = Open3.capture3('uv pip list --outdated --format=json')
    data =
      begin
        JSON.parse(output)
      rescue JSON::ParserError
        []
      end
    data.each do |pkg|
      name = pkg['name']
      current = pkg['version']
      latest = pkg['latest_version']
      next if current == latest

      constraint = direct_constraints[name.downcase]
      if constraint && !pep440_satisfies?(latest, constraint)
        puts "  Skipping #{name} #{current} -> #{latest} (pyproject.toml constraint #{constraint} blocks it)"
        next
      end

      next unless prompt_update?("[#{label}] Update wheel #{name} from #{current} to #{latest}?", current, latest)

      # Even when the direct constraint allows it, a transitive constraint may
      # still prevent the resolver from moving. Snapshot uv.lock and check.
      lock_before = File.exist?('uv.lock') ? File.read('uv.lock') : nil
      system("uv lock --upgrade-package #{name}")
      lock_after = File.exist?('uv.lock') ? File.read('uv.lock') : nil
      if lock_before && lock_after && lock_before == lock_after
        puts "  No change for #{name} (transitive constraint blocks #{latest})"
      else
        updated += 1
      end
    end
    system('uv sync') if updated > 0
  end
  puts "  No updatable wheels." if updated == 0
  updated
end

# Returns { 'package-name-lowercased' => 'specifier-string' } from a
# pyproject.toml `dependencies = [ ... ]` block. Recognises both
# `"name (>=1.0,<2.0)"` and `"name>=1.0,<2.0"` shapes.
def read_pyproject_dep_constraints(path)
  return {} unless File.exist?(path)
  body = File.read(path)
  block = body[/^dependencies\s*=\s*\[(.*?)^\]/m, 1]
  return {} unless block
  result = {}
  block.scan(/"([^"]+)"/).flatten.each do |entry|
    # Strip extras like `psycopg[binary,pool]` for the name
    m = entry.match(/^\s*([A-Za-z0-9_.\-]+)(?:\[[^\]]*\])?\s*(?:\(([^)]+)\)|([^,]\S.*))?$/)
    next unless m
    name = m[1].downcase
    spec = (m[2] || m[3] || '').strip
    result[name] = spec unless spec.empty?
  end
  result
end

# True if `version` satisfies the PEP 440 specifier string `spec` (comma-joined
# list of `<op><target>` clauses). Supports >=, <=, >, <, ==, !=, ~=.
def pep440_satisfies?(version, spec)
  v = Gem::Version.new(version.sub(/^v/, ''))
  spec.split(',').all? do |clause|
    m = clause.strip.match(/^(>=|<=|==|!=|~=|>|<)\s*(.+)$/)
    next true unless m
    op, target = m.captures
    t = Gem::Version.new(target.strip.sub(/^v/, ''))
    case op
    when '>=' then v >= t
    when '>'  then v > t
    when '<=' then v <= t
    when '<'  then v < t
    when '==' then v == t
    when '!=' then v != t
    when '~='
      # ~=X.Y allows >=X.Y, <(X+1); ~=X.Y.Z allows >=X.Y.Z, <X.(Y+1)
      segs = t.segments
      next false unless v >= t
      upper_segs = segs[0..-2].dup
      upper_segs[-1] = upper_segs[-1].to_i + 1
      v < Gem::Version.new(upper_segs.join('.'))
    else
      true # unknown operator -> don't filter
    end
  end
rescue ArgumentError
  true # unparsable -> don't filter
end

# requirements.txt-based projects with exact pins (==version). Prompts per pin
# and rewrites the file when accepted; the actual `pip install` of the new
# version happens at container build time so no venv is created here.
def update_outdated_requirements_txt(dir, client)
  label = dir.sub(ROOT_DIR + '/', '')
  requirements = File.join(dir, 'requirements.txt')
  return 0 unless File.exist?(requirements)
  puts "\nChecking outdated wheels in #{label}:"
  updated = 0
  content = File.read(requirements)
  new_content = content.dup
  content.each_line do |line|
    m = line.match(/^([\w\-.]+)==([\w.]+)/)
    next unless m
    name, current = m.captures
    resp = client.get("https://pypi.org/pypi/#{name}/json")
    next unless resp.status == 200
    latest = JSON.parse(resp.body)['info']['version'] rescue nil
    next unless latest && latest != current
    if prompt_update?("[#{label}] Update #{name} from #{current} to #{latest}?", current, latest)
      new_content = new_content.sub(/^#{Regexp.escape(name)}==[\w.]+/, "#{name}==#{latest}")
      updated += 1
    end
  end
  if updated > 0
    File.write(requirements, new_content)
    puts "  Updated #{requirements.sub(ROOT_DIR + '/', '')}"
  else
    puts "  No outdated wheels."
  end
  updated
end

# pnpm-managed workspace; prompts per outdated package and surgically rewrites
# only the accepted package's version pin in each workspace package.json that
# declares it. A single `pnpm install` at the end syncs the lockfile.
#
# This is intentionally NOT `pnpm update X@latest --recursive`. That command
# re-resolves the whole workspace and pnpm freely bumps unrelated direct deps
# (e.g. vite 7.3.3 → 8.0.14) as part of its resolution — the user reported vite
# being upgraded without ever being prompted for it.
def update_outdated_pnpm(dir, client = nil)
  label = dir.sub(ROOT_DIR + '/', '')
  puts "\nChecking outdated pnpm packages in #{label}:"
  updated = 0
  Dir.chdir(dir) do
    system('pnpm install --silent', out: File::NULL) unless File.directory?('node_modules')

    # pnpm 10 enforces `minimumReleaseAge` (minutes since publish). Pulling a
    # newer version of a too-fresh package makes the subsequent `pnpm install`
    # fail, which the user has hit. Skip those at prompt time and tell them why.
    min_age = pnpm_min_release_age_minutes
    if min_age > 0
      puts "  pnpm minimumReleaseAge = #{min_age} min; newer-than-that releases will be skipped."
    end

    output, _stderr, _status = Open3.capture3('pnpm outdated --format json --recursive')
    data =
      begin
        JSON.parse(output)
      rescue JSON::ParserError
        {}
      end
    data = {} unless data.is_a?(Hash)

    package_jsons = Dir.glob(File.join(dir, '**', 'package.json')).reject { |p| p.include?('/node_modules/') }

    data.each do |name, info|
      current = info['current']
      latest = info['latest']
      next if current.nil? || latest.nil? || current == latest

      # Offer each upgrade tier in turn (newest major, then newest minor within
      # the current major, then newest patch) instead of only jumping to latest.
      candidates = client ? npm_upgrade_candidates(client, name, current) : []
      candidates = [latest] if candidates.empty?

      chosen = nil
      candidates.each do |candidate|
        next if candidate == current
        if min_age > 0 && client
          age = npm_published_age_minutes(client, name, candidate)
          if age && age < min_age
            puts "  Skipping #{name} #{current} -> #{candidate} (published #{format_age(age)} ago, below minimumReleaseAge of #{min_age} min)."
            next
          end
        end
        if prompt_update?("[#{label}] Update pnpm #{name} from #{current} to #{candidate}?", current, candidate)
          chosen = candidate
          break
        end
      end
      next unless chosen
      latest = chosen

      # Try to rewrite the version pin in any workspace package.json that has
      # this package as a direct dep. If none changed, it's either transitive
      # or package.json is already at the target (and only the lockfile is
      # stale) — either way we still want `pnpm install` to reconcile.
      touched = false
      package_jsons.each do |pkg_path|
        body = File.read(pkg_path)
        new_body = bump_pnpm_dep(body, name, latest)
        next if new_body == body
        File.write(pkg_path, new_body)
        puts "  Updated #{name}=#{latest} in #{pkg_path.sub(ROOT_DIR + '/', '')}"
        touched = true
      end
      unless touched
        puts "  No package.json edit needed for #{name} (transitive dep or pin already at #{latest}); pnpm install will refresh the lockfile."
      end
      updated += 1
    end

    if updated > 0
      puts "  Running pnpm install to sync lockfile..."
      system('pnpm install')
    end
  end
  puts "  No outdated pnpm packages." if updated == 0
  updated
end

# Replace just the version string of `name` inside any of dependencies /
# devDependencies / peerDependencies / optionalDependencies. Preserves a
# leading "^" or "~" range marker if present. Leaves all other formatting and
# unrelated deps untouched.
def bump_pnpm_dep(json_text, name, new_version)
  json_text.gsub(/("#{Regexp.escape(name)}"\s*:\s*")([\^~]?)([^"]+)(")/) do
    %{#{$1}#{$2}#{new_version}#{$4}}
  end
end

# Effective pnpm `minimumReleaseAge` for the current working directory, in
# minutes. Returns 0 if unset or non-numeric.
def pnpm_min_release_age_minutes
  out, _err, status = Open3.capture3('pnpm config get minimumReleaseAge')
  return 0 unless status.success?
  value = out.strip
  return 0 if value.empty? || value == 'undefined'
  Integer(value, 10)
rescue ArgumentError
  0
end

# Upgrade targets above `current` for npm package `name`, highest tier first:
# the newest major (major > current major), the newest minor within the current
# major (minor > current minor), and the newest patch within the current minor.
# Stable releases only (anything with a "-" prerelease tag is ignored). Returns
# [] on any fetch/parse error so callers fall back to `latest`.
def npm_upgrade_candidates(client, name, current)
  resp = client.get("https://registry.npmjs.org/#{name}")
  return [] unless resp.status == 200
  versions = JSON.parse(resp.body)['versions']&.keys || []
  cur = Gem::Version.new(current)
  cmaj, cmin, = current.split('.').map(&:to_i)
  parsed = versions.filter_map do |v|
    next unless v =~ /^\d+\.\d+\.\d+$/
    gv = Gem::Version.new(v)
    next unless gv > cur
    [v, gv, v.split('.').map(&:to_i)]
  end
  major = parsed.select { |_, _, (maj, _, _)| maj > cmaj }.max_by { |_, gv, _| gv }
  minor = parsed.select { |_, _, (maj, mn, _)| maj == cmaj && mn > cmin }.max_by { |_, gv, _| gv }
  patch = parsed.select { |_, _, (maj, mn, _)| maj == cmaj && mn == cmin }.max_by { |_, gv, _| gv }
  [major, minor, patch].compact.map(&:first).uniq
rescue StandardError
  []
end

# Minutes since `version` of `name` was published to npm, or nil if unknown.
def npm_published_age_minutes(client, name, version)
  resp = client.get("https://registry.npmjs.org/#{name}")
  return nil unless resp.status == 200
  data = JSON.parse(resp.body)
  pub = data.dig('time', version)
  return nil unless pub
  ((Time.now - Time.parse(pub)) / 60.0).to_i
rescue StandardError
  nil
end

def format_age(minutes)
  return "#{minutes}m" if minutes < 60
  hours = minutes / 60
  return "#{hours}h #{minutes % 60}m" if hours < 24
  days = hours / 24
  "#{days}d #{hours % 24}h"
end
