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

require_relative 'package_audit_lib'
require 'dotenv'
Dotenv.overload # Overload existing so we use .env exclusivly

version_tag = ARGV[0] || "latest"

# Get versions from the Dockerfiles
traefik_version = get_docker_version("openc3-traefik/Dockerfile")
redis_version = get_docker_version("openc3-redis/Dockerfile")
minio_version = get_docker_version("openc3-minio/Dockerfile")

# Manual list - MAKE SURE UP TO DATE especially base images
containers = [
  # This should match the values in the .env file
  { name: "openc3inc/openc3-ruby:#{version_tag}", base_image: "alpine:#{ENV['ALPINE_VERSION']}.#{ENV['ALPINE_BUILD']}", apk: true, gems: true },
  { name: "openc3inc/openc3-node:#{version_tag}", base_image: "openc3inc/openc3-ruby:#{version_tag}", apk: true },
  { name: "openc3inc/openc3-base:#{version_tag}", base_image: "openc3inc/openc3-ruby:#{version_tag}", apk: true, gems: true },
  { name: "openc3inc/openc3-cosmos-cmd-tlm-api:#{version_tag}", base_image: "openc3inc/openc3-base:#{version_tag}", apk: true, gems: true },
  { name: "openc3inc/openc3-cosmos-init:#{version_tag}", base_image: "openc3inc/openc3-base:#{version_tag}", apk: true, gems: true,
    yarn: ["/openc3/plugins/yarn.lock", "/openc3/plugins/yarn-tool-base.lock"] },
  { name: "openc3inc/openc3-operator:#{version_tag}", base_image: "openc3inc/openc3-base:#{version_tag}", apk: true, gems: true },
  { name: "openc3inc/openc3-cosmos-script-runner-api:#{version_tag}", base_image: "openc3inc/openc3-base:#{version_tag}", apk: true, gems: true },
  { name: "openc3inc/openc3-redis:#{version_tag}", base_image: "redis:#{redis_version}", apt: true },
  { name: "openc3inc/openc3-traefik:#{version_tag}", base_image: "traefik:#{traefik_version}", apk: true },
  { name: "openc3inc/openc3-minio:#{version_tag}", base_image: "minio/minio:#{minio_version}", rpm: true },
]

# Update the bundles
Dir.chdir(File.join(__dir__, '../../openc3')) do
  `rm Gemfile.lock 2>&1`
  `bundle update`
end
Dir.chdir(File.join(__dir__, '../../openc3-cosmos-cmd-tlm-api')) do
  `rm Gemfile.lock 2>&1`
  `bundle update`
end
Dir.chdir(File.join(__dir__, '../../openc3-cosmos-script-runner-api')) do
  `rm Gemfile.lock 2>&1`
  `bundle update`
end

# Build reports
report = build_report(containers)
summary_report = build_summary_report(containers)

# Now check for latest versions
client = HTTPClient.new
check_alpine(client)
check_container_version(client, containers, 'library/traefik')
check_minio(client, containers)
check_container_version(client, containers, 'library/redis')
base_pkgs = %w(regenerator-runtime single-spa vue vue-router vuetify vuex)
check_tool_base('openc3-cosmos-init/plugins/openc3-tool-base', base_pkgs)

puts "\n*** If you update a container version re-run to ensure there aren't additional updates! ***\n\n"

# Check the bundles
Dir.chdir(File.join(__dir__, '../../openc3')) do
  puts "\nChecking outdated gems in openc3:"
  puts `bundle outdated`
end
Dir.chdir(File.join(__dir__, '../../openc3-cosmos-cmd-tlm-api')) do
  puts "\nChecking outdated gems in openc3-cosmos-cmd-tlm-api:"
  puts `bundle outdated`
end
Dir.chdir(File.join(__dir__, '../../openc3-cosmos-script-runner-api')) do
  puts "\nChecking outdated gems in openc3-cosmos-script-runner-api:"
  puts `bundle outdated`
end

File.open("openc3_package_report.txt", "w") do |file|
  file.write(summary_report)
  file.write(report)
end

puts "\n\nRun the following:"
puts "cd openc3-cosmos-init/plugins; yarn install; yarn upgrade-interactive --latest; cd ../.."
puts "cd openc3-cosmos-init/plugins/openc3-tool-base; yarn install; yarn upgrade-interactive --latest; cd ../../.."
puts "cd openc3/templates/widget; yarn install; yarn upgrade-interactive --latest; cd ../../.."
puts "\n\n*** If you update #{base_pkgs.join(', ')} then re-run! ***\n\n"
