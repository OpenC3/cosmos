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

# Set openc3 main gem version path
base_path = File.expand_path(File.join(__dir__, '..', '..'))
path = File.join(base_path, 'openc3', 'lib', 'openc3', 'version.rb')

puts "Getting the revision from git"
revision = `git rev-parse HEAD`.chomp
puts "Git revision: #{revision}"

version = ENV['OPENC3_RELEASE_VERSION'].to_s.dup
if version.length <= 0
  raise "Version is required"
end

split_version = version.to_s.split('.')
major = split_version[0]
minor = split_version[1]
if version =~ /[a-zA-Z]+/
  # Prerelease version
  is_prod_release = false
  remainder = split_version[2..-1].join(".")
  remainder.gsub!('-', '.pre.') # Rubygems replaces dashes with .pre.
  remainder_split = remainder.split('.')
  patch = remainder_split[0]
  other = remainder_split[1..-1].join('.')
  gem_version = "#{major}.#{minor}.#{patch}.#{other}"
else
  # Production Release Version
  is_prod_release = true
  patch = split_version[2]
  other = split_version[3..-1].join('.')
  gem_version = version
end

puts "Setting version to: #{version}"

# Update main rubygem version.rb
File.open(path, 'wb') do |file|
  file.puts "# encoding: ascii-8bit"
  file.puts ""
  file.puts "OPENC3_VERSION = '#{version}'"
  file.puts "module OpenC3"
  file.puts "  module Version"
  file.puts "    MAJOR = '#{major}'"
  file.puts "    MINOR = '#{minor}'"
  file.puts "    PATCH = '#{patch}'"
  file.puts "    OTHER = '#{other}'"
  file.puts "    BUILD = '#{revision}'"
  file.puts "  end"
  file.puts "  VERSION = '#{version}'"
  file.puts "  GEM_VERSION = '#{gem_version}'"
  file.puts "end"
end
puts "Updated: #{path}"

require path

gemspec_files = [
  'openc3/openc3.gemspec',
]

gemspec_files.each do |rel_path|
  full_path = File.join(base_path, rel_path)
  data = nil
  File.open(full_path, 'rb') do |file|
    data = file.read
  end
  mod_data = ''
  data.each_line do |line|
    if line =~ /s\.version =/
      mod_data << "  s.version = '#{gem_version}'\n"
    elsif line =~ /s\.add_runtime_dependency 'openc3'/
      mod_data << "  s.add_runtime_dependency 'openc3', '#{gem_version}'\n"
    else
      mod_data << line
    end
  end
  File.open(full_path, 'wb') do |file|
    file.write(mod_data)
  end
  puts "Updated: #{full_path}"
end

package_dot_json_files = [
  'openc3-cosmos-init/plugins/packages/openc3-tool-base/package.json',
  'openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/package.json',
  'openc3-cosmos-init/plugins/packages/openc3-cosmos-tool-admin/package.json',
  'openc3-cosmos-init/plugins/packages/openc3-cosmos-tool-bucketexplorer/package.json',
  'openc3-cosmos-init/plugins/packages/openc3-cosmos-tool-cmdsender/package.json',
  'openc3-cosmos-init/plugins/packages/openc3-cosmos-tool-cmdtlmserver/package.json',
  'openc3-cosmos-init/plugins/packages/openc3-cosmos-tool-dataextractor/package.json',
  'openc3-cosmos-init/plugins/packages/openc3-cosmos-tool-dataviewer/package.json',
  'openc3-cosmos-init/plugins/packages/openc3-cosmos-tool-handbooks/package.json',
  'openc3-cosmos-init/plugins/packages/openc3-cosmos-tool-iframe/package.json',
  'openc3-cosmos-init/plugins/packages/openc3-cosmos-tool-limitsmonitor/package.json',
  'openc3-cosmos-init/plugins/packages/openc3-cosmos-tool-packetviewer/package.json',
  'openc3-cosmos-init/plugins/packages/openc3-cosmos-tool-scriptrunner/package.json',
  'openc3-cosmos-init/plugins/packages/openc3-cosmos-tool-tablemanager/package.json',
  'openc3-cosmos-init/plugins/packages/openc3-cosmos-tool-tlmgrapher/package.json',
  'openc3-cosmos-init/plugins/packages/openc3-cosmos-tool-tlmviewer/package.json',
  'openc3-cosmos-init/plugins/packages/openc3-js-common/package.json',
  'openc3-cosmos-init/plugins/packages/openc3-vue-common/package.json',
  'openc3/templates/widget/package.json',
  'openc3/templates/tool_vue/package.json',
  'openc3/templates/tool_react/package.json',
  'openc3/templates/tool_angular/package.json',
  'openc3/templates/tool_svelte/package.json',
]

package_dot_json_files.each do |rel_path|
  full_path = File.join(base_path, rel_path)
  data = nil
  File.open(full_path, 'rb') do |file|
    data = file.read
  end
  mod_data = ''
  data.each_line do |line|
    if line =~ /\"version\":/
      mod_data << "  \"version\": \"#{version}\",\n"
    elsif is_prod_release and rel_path.start_with? 'openc3/templates/'
      # These dependencies should stay at a released version.
      # Stuff in 'openc3-cosmos-init' references these dependencies via the workspace, so no need to update here.
      if line =~ /\"@openc3\/js-common\":/
        mod_data << "    \"@openc3/js-common\": \"#{version}\""
        # Don't assume the line has a comma because it could be at the end
        if line.include?(',')
          mod_data << ",\n"
        else
          mod_data << "\n"
        end
      elsif line =~ /\"@openc3\/vue-common\":/
        mod_data << "    \"@openc3/vue-common\": \"#{version}\""
        # Don't assume the line has a comma because it could be at the end
        if line.include?(',')
          mod_data << ",\n"
        else
          mod_data << "\n"
        end
      end
    else
      mod_data << line
    end
  end
  File.open(full_path, 'wb') do |file|
    file.write(mod_data)
  end
  puts "Updated: #{full_path}"
end

shell_scripts = [
  'openc3-cosmos-init/plugins/docker-package-build.sh',
]

shell_scripts.each do |rel_path|
  full_path = File.join(base_path, rel_path)
  data = nil
  File.open(full_path, 'rb') do |file|
    data = file.read
  end
  mod_data = ''
  data.each_line do |line|
    if line =~ /OPENC3_RELEASE_VERSION=/
      mod_data << "OPENC3_RELEASE_VERSION=#{version}\n"
    else
      mod_data << line
    end
  end
  File.open(full_path, 'wb') do |file|
    file.write(mod_data)
  end
  puts "Updated: #{full_path}"
end

gemfiles = [
  'openc3-cosmos-cmd-tlm-api/Gemfile',
  'openc3-cosmos-script-runner-api/Gemfile',
]

gemfiles.each do |rel_path|
  full_path = File.join(base_path, rel_path)
  data = nil
  File.open(full_path, 'rb') do |file|
    data = file.read
  end
  mod_data = ''
  data.each_line do |line|
    if line =~ /gem 'openc3'/ and line !~ /:path/
      mod_data << "  gem 'openc3', '#{gem_version}'\n"
    else
      mod_data << line
    end
  end
  File.open(full_path, 'wb') do |file|
    file.write(mod_data)
  end
  puts "Updated: #{full_path}"
end

# Update python package version

python_files = [
  'openc3/python/pyproject.toml',
  'openc3/python/openc3/__version__.py'
]

python_files.each do |rel_path|
  full_path = File.join(base_path, rel_path)
  data = nil
  File.open(full_path, 'rb') do |file|
    data = file.read
  end
  mod_data = ''
  data.each_line do |line|
    if line =~ /__version__/
      mod_data << "__version__ = \"#{version}\"\n"
    elsif line =~ /^version =/
      mod_data << "version = \"#{version}\"\n"
    else
      mod_data << line
    end
  end
  File.open(full_path, 'wb') do |file|
    file.write(mod_data)
  end
  puts "Updated: #{full_path}"
end
