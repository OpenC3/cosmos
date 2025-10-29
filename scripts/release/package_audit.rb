# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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
require 'faraday'
require 'faraday/follow_redirects'
require 'dotenv'
Dotenv.overload # Overload existing so we use .env exclusively

version_tag = ARGV[0] || "latest"

# Get versions from the Dockerfiles
traefik_version = get_docker_version("openc3-traefik/Dockerfile")
redis_version = get_docker_version("openc3-redis/Dockerfile")
mc_version = get_docker_version("openc3-cosmos-init/Dockerfile", arg: 'OPENC3_MC_RELEASE')
minio_version = get_docker_version("openc3-minio/Dockerfile", arg: 'OPENC3_MINIO_RELEASE')
minio_ubi_version = get_docker_version("openc3-minio/Dockerfile-ubi", arg: 'OPENC3_MINIO_RELEASE')
if minio_version != minio_ubi_version
  puts "WARN: minio versions for standard and UBI do not match: #{minio_version} != #{minio_ubi_version}"
end
go_version = get_docker_version("openc3-minio/Dockerfile", arg: 'GO_VERSION')

# Manual list - MAKE SURE UP TO DATE especially base images
containers = [
  # This should match the values in the .env file
  { name: "openc3inc/openc3-ruby:#{version_tag}", base_image: "alpine:#{ENV['ALPINE_VERSION']}.#{ENV['ALPINE_BUILD']}", apk: true, gems: true, python: true },
  { name: "openc3inc/openc3-node:#{version_tag}", base_image: "openc3inc/openc3-ruby:#{version_tag}", apk: true },
  { name: "openc3inc/openc3-base:#{version_tag}", base_image: "openc3inc/openc3-ruby:#{version_tag}", apk: true, gems: true, python: true },
  { name: "openc3inc/openc3-cosmos-cmd-tlm-api:#{version_tag}", base_image: "openc3inc/openc3-base:#{version_tag}", apk: true, gems: true, python: true },
  { name: "openc3inc/openc3-cosmos-init:#{version_tag}", base_image: "openc3inc/openc3-base:#{version_tag}", apk: true, gems: true, python: true,
    pnpm: ["/openc3/plugins/pnpm-lock.yaml"] },
  { name: "openc3inc/openc3-operator:#{version_tag}", base_image: "openc3inc/openc3-base:#{version_tag}", apk: true, gems: true, python: true },
  { name: "openc3inc/openc3-cosmos-script-runner-api:#{version_tag}", base_image: "openc3inc/openc3-base:#{version_tag}", apk: true, gems: true, python: true },
  { name: "openc3inc/openc3-redis:#{version_tag}", base_image: "redis:#{redis_version}", apt: true },
  { name: "openc3inc/openc3-traefik:#{version_tag}", base_image: "traefik:#{traefik_version}", apk: true },
  { name: "openc3inc/openc3-minio:#{version_tag}", base_image: "golang:#{go_version}-alpine#{ENV['ALPINE_VERSION']}", apk: true },
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

client = Faraday.new do |f|
  f.response :follow_redirects
end

# Build reports
report = build_report(containers, client)
summary_report = build_summary_report(containers)

# Now check for latest versions
check_build_files(mc_version, minio_version, traefik_version)
check_alpine(client)
check_container_version(client, containers, 'traefik')
check_minio(client, containers, mc_version, minio_version, go_version)
check_container_version(client, containers, 'redis')
base_pkgs = %w(import-map-overrides single-spa systemjs vue vue-router vuetify vuex)
check_tool_base('openc3-cosmos-init/plugins/packages/openc3-tool-base', base_pkgs)
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

# Check the wheels
Dir.chdir(File.join(__dir__, '../../openc3/python')) do
  puts "\nChecking outdated wheels in openc3/python:"
  puts `poetry show -o`
end
Dir.chdir(File.join(__dir__, '../../openc3-cosmos-init/plugins/packages/openc3-cosmos-demo')) do
  puts "\nChecking outdated wheels in openc3-cosmos-demo:"
  puts `python -m venv venv; source venv/bin/activate; pip install -r requirements.txt; pip list --outdated; deactivate; rm -rf venv`
end

File.open("openc3_package_report.txt", "w") do |file|
  file.write(summary_report)
  file.write(report)
end

puts "\n\nRun the following:"
puts "cd openc3-cosmos-init/plugins; pnpm install; pnpm update --interactive --latest --recursive; cd ../.."
puts "cd playwright; pnpm install; pnpm update --interactive --latest; cd .."
puts "cd docs.openc3.com; pnpm install; pnpm update --interactive --latest; cd .."

# Commenting this out since the templates don't really need to be updated, and updates broke them over time
# puts "\n\nYou can run the following, but check that the templates still work if you do:"
# puts "cd openc3/templates/widget; pnpm install; pnpm update --interactive --latest; cd ../../.."
# puts "cd openc3/templates/tool_vue; pnpm install; pnpm update --interactive --latest; cd ../../.."
# puts "cd openc3/templates/tool_react; pnpm install; pnpm update --interactive --latest; cd ../../.."
# puts "cd openc3/templates/tool_angular; pnpm install; pnpm update --interactive --latest; cd ../../.."
# puts "cd openc3/templates/tool_svelte; pnpm install; pnpm update --interactive --latest; cd ../../.."

puts "\n\n*** If you update #{base_pkgs.join(', ')} then re-run! ***\n\n"
