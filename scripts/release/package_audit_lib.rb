# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc.
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

# NOTE: Run this file from the root to get the .env vars set:
# cosmos % ruby scripts/release/package_audit.rb

require 'open3'
require 'fileutils'
require 'json'

$overall_apk = []
$overall_apt = []
$overall_rpm = []
$overall_gems = []
$overall_yarn = []

def get_docker_version(path)
  File.open(path) do |file|
    file.each do |line|
      if line.include?("FROM")
        # Remove "AS ..." qualifiers in the FROM line
        line.gsub!(/as\s+.*/i, '')
        return line.split(':')[-1].strip
      end
    end
  end
end

def make_sorted_hash(name_versions)
  result = {}
  name_versions.sort!
  name_versions.each do |name, version, package|
    result[name] ||= [[], []]
    result[name][0] << version
    result[name][1] << package
  end
  result.each do |name, data|
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
  lines, stderr, status = Open3.capture3('docker run --rm #{container_name} apk list -I')
  lines.each_line do |line|
    package = line.split(' ')[0]
    breakup_versioned_package(package, name_versions, package)
  end
  $overall_apk.concat(name_versions)
  make_sorted_hash(name_versions)
end

def extract_apt(container)
  container_name = container[:name]
  results, stderr, status = Open3.capture3('docker run --rm #{container_name} apt list --installed')
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
  lines = `docker run --entrypoint "" --rm #{container_name} rpm -qa`
  lines.each_line do |line|
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

def extract_yarn(container)
  container_name = container[:name]
  name_versions = []
  yarn_lock_paths = container[:yarn]
  yarn_lock_paths.each do |path|
    id = `docker create #{container_name}`.strip
    `docker cp #{id}:#{path} .`
    `docker rm -v #{id}`
    data = File.read(path.split('/')[-1])
    name_versions.concat(process_yarn(data))
  end
  $overall_yarn.concat(name_versions)
  make_sorted_hash(name_versions)
end

def process_yarn(data)
  result = []
  name = nil
  version_next = false
  data.each_line do |line|
    if version_next
      version_next = false
      version = line.split('"')[1]
      result << [name, version, nil]
    end
    if line[0] != " " and line[0] != '#' and line.strip != ""
      if line[0] == '"'
        part = line.split('"')[1]
        last_at = part.rindex('@')
        name = part[0..(last_at - 1)]
      else
        name = line.split('@')[0]
      end
      version_next = true
    end
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
  report << "-" * 80
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
  if $overall_gems.length > 0
    report << build_section("Ruby Gems", make_sorted_hash($overall_gems), false)
    report << "\n"
  end
  if $overall_yarn.length > 0
    report << build_section("Node Packages", make_sorted_hash($overall_yarn), false)
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
  report << build_section("Ruby Gems", extract_gems(container), false) if container[:gems]
  report << build_section("Node Packages", extract_yarn(container), false) if container[:yarn]
  report << "\n"
  report
end

def build_report(containers)
  report = ""
  report << "Individual Container Reports\n"
  report << "-" * 80
  report << "\n\n"
  containers.each do |container|
    report << build_container_report(container)
  end
  report
end

def check_alpine(client)
  resp = client.get('http://dl-cdn.alpinelinux.org/alpine/').body
  major, minor = ENV['ALPINE_VERSION'].split('.')
  major = major.to_i
  minor = minor.to_i
  if resp.include?(ENV['ALPINE_VERSION'])
    if resp.include?("#{major + 1}.0")
      puts "NOTE: Alpine has a new major version: #{major}.0. Read release notes at https://wiki.alpinelinux.org/wiki/Release_Notes_for_Alpine_#{major}.0.0"
    end
    if resp.include?("#{major}.#{minor + 1}")
      puts "NOTE: Alpine has a new minor version: #{major}.#{minor + 1}. Read release notes at https://alpinelinux.org/posts/Alpine-#{major}.#{minor + 1}.0-released.html"
    end
    resp = client.get("http://dl-cdn.alpinelinux.org/alpine/v#{ENV['ALPINE_VERSION']}/releases/armv7").body
    if resp.include?("alpine-virt-#{ENV['ALPINE_VERSION']}.#{ENV['ALPINE_BUILD'].to_i + 1}-armv7.iso")
      puts "NOTE: Alpine has a new patch version: #{ENV['ALPINE_VERSION']}.#{ENV['ALPINE_BUILD'].to_i + 1}"
    end
    if !resp.include?("alpine-virt-#{ENV['ALPINE_VERSION']}.#{ENV['ALPINE_BUILD']}-armv7.iso")
      puts "ERROR: Could not find Alpine build: #{ENV['ALPINE_VERSION']}.#{ENV['ALPINE_BUILD']}"
    end
  else
    puts "ERROR: Could not find Alpine build: #{ENV['ALPINE_VERSION']}"
  end
end

def check_minio(client, containers)
  container = containers.select { |val| val[:name].include?('openc3-minio') }[0]
  minio_version = container[:base_image].split(':')[-1]
  resp = client.get('https://registry.hub.docker.com/v2/repositories/minio/minio/tags?page_size=1024').body
  images = JSON.parse(resp)['results']
  versions = []
  images.each do |image|
    versions << image['name']
  end
  if versions.include?(minio_version)
    split_version = minio_version.split('.')
    minio_time = DateTime.parse(split_version[1])
    versions.each do |version|
      split_version = version.split('.')
      if split_version[0] == 'RELEASE'
        version_time = DateTime.parse(split_version[1])
        if version_time > minio_time
          puts "NOTE: Minio has a new version: #{version}, Current Version: #{minio_version}"
          return
        end
      end
    end
    puts "Minio up to date: #{minio_version}"
  else
    puts "ERROR: Could not find Minio image: #{minio_version}"
  end
end

def validate_versions(versions, version, name)
  if versions.include?(version)
    new_version = false
    major, minor, patch = version.split('.')
    if versions.include?("#{major.to_i + 1}.0")
      puts "NOTE: #{name} has a new major version: #{major.to_i + 1}, Current Version: #{version}"
      new_version = true
    end
    if versions.include?("#{major}.#{minor.to_i + 1}")
      puts "NOTE: #{name} has a new minor version: #{major}.#{minor.to_i + 1}, Current Version: #{version}"
      new_version = true
    end
    if versions.include?("#{major}.#{minor}.#{patch.to_i + 1}")
      puts "NOTE: #{name} has a new patch version: #{major}.#{minor}.#{patch.to_i + 1}, Current Version: #{version}"
      new_version = true
    end
    puts "#{name} is is up to date with #{version}" unless new_version
  else
    puts "ERROR: Could not find #{name} image: #{version}"
  end
end

def check_keycloak(client, containers)
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
  validate_versions(versions, version, 'keycloak')
end

def check_container_version(client, containers, repo_path)
  name = repo_path.split('/')[-1]
  container = containers.select { |val| val[:name].include?(name) }[0]
  version = container[:base_image].split(':')[-1]
  resp = client.get("https://registry.hub.docker.com/v2/repositories/#{repo_path}/tags?page_size=1024").body
  images = JSON.parse(resp)['results']
  versions = []
  images.each do |image|
    versions << image['name']
  end
  validate_versions(versions, version, name)
end

def check_tool_base(path, base_pkgs)
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
    unless existing.include?(latest)
      puts "Existing MaterialDesignIcons: #{existing}, doesn't match latest: #{latest}. Upgrading..."
      `curl https://cdnjs.cloudflare.com/ajax/libs/MaterialDesign-Webfont/#{latest}/css/materialdesignicons.min.css --output public/css/materialdesignicons-#{latest}.min.css`
      `curl https://cdnjs.cloudflare.com/ajax/libs/MaterialDesign-Webfont/#{latest}/css/materialdesignicons.css.map --output public/css/materialdesignicons.css.map`
      `curl https://cdnjs.cloudflare.com/ajax/libs/MaterialDesign-Webfont/#{latest}/fonts/materialdesignicons-webfont.eot --output public/fonts/materialdesignicons-webfont.eot`
      `curl https://cdnjs.cloudflare.com/ajax/libs/MaterialDesign-Webfont/#{latest}/fonts/materialdesignicons-webfont.ttf --output public/fonts/materialdesignicons-webfont.ttf`
      `curl https://cdnjs.cloudflare.com/ajax/libs/MaterialDesign-Webfont/#{latest}/fonts/materialdesignicons-webfont.woff --output public/fonts/materialdesignicons-webfont.woff`
      `curl https://cdnjs.cloudflare.com/ajax/libs/MaterialDesign-Webfont/#{latest}/fonts/materialdesignicons-webfont.woff2 --output public/fonts/materialdesignicons-webfont.woff2`
      FileUtils.rm(existing)

      # Now update the files with references to materialdesignicons
      files = %w(src/index.ejs src/index-allow-http.ejs)
      # The base also has to update index.html in openc3-tool-common
      files << "../packages/openc3-tool-common/public/index.html" unless path.include?('enterprise')
      files.each do |filename|
        ejs = File.read(filename)
        ejs.gsub!(/materialdesignicons-.+.min.css/, "materialdesignicons-#{latest}.min.css")
        File.open(filename, 'w') {|file| file.puts ejs }
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
      # Ensure we're only matching package names followed by numbers
      # This prevents vue- from matching vue-router-
      existing = Dir["public/js/#{package}-[0-9]*"]
      unless existing[0].include?(latest)
        puts "Existing #{package}: #{existing}, doesn't match latest: #{latest}. Upgrading..."
        additional = ''
        # Handle nuances in individual packages
        case package
        when 'single-spa'
          `curl https://cdnjs.cloudflare.com/ajax/libs/#{package}/#{latest}/system/#{package}.min.js --output public/js/#{package}-#{latest}.min.js`
          `curl https://cdnjs.cloudflare.com/ajax/libs/#{package}/#{latest}/system/#{package}.min.js.map --output public/js/#{package}-#{latest}.min.js.map`
        when 'vuetify'
          FileUtils.rm(Dir["public/css/vuetify-*"][0]) # Delete the existing vuetify css
          `curl https://cdnjs.cloudflare.com/ajax/libs/#{package}/#{latest}/#{package}.min.css --output public/css/#{package}-#{latest}.min.css`
          `curl https://cdnjs.cloudflare.com/ajax/libs/#{package}/#{latest}/#{package}.min.js --output public/js/#{package}-#{latest}.min.js`
        when 'regenerator-runtime'
          `curl https://cdn.jsdelivr.net/npm/#{package}@#{latest}/runtime.min.js --output public/js/#{package}-#{latest}.min.js`
        when 'keycloak-js'
          `curl https://cdn.jsdelivr.net/npm/#{package}@#{latest}/dist/keycloak.min.js --output public/js/#{package}-#{latest}.min.js`
          `curl https://cdn.jsdelivr.net/npm/#{package}@#{latest}/dist/keycloak.min.js.map --output public/js/#{package}-#{latest}.min.js.map`
        else
          `curl https://cdnjs.cloudflare.com/ajax/libs/#{package}/#{latest}/#{package}.min.js --output public/js/#{package}-#{latest}.min.js`
        end
        FileUtils.rm existing
        # Now update the files with references to <package>-<verison>.min.js
        %w(src/index.ejs src/index-allow-http.ejs).each do |filename|
          ejs = File.read(filename)
          ejs.gsub!(/#{package}-\d+\.\d+\.\d+\.min\.js/, "#{package}-#{latest}.min.js")
          File.open(filename, 'w') {|file| file.puts ejs }
        end
      end
    end
  end
end
