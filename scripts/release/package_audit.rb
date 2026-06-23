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

require_relative 'package_audit_lib'
require 'faraday'
require 'faraday/follow_redirects'
require 'dotenv'
Dotenv.overload # Overload existing so we use .env exclusively

version_tag = ARGV[0] || "latest"

# Get versions from the Dockerfiles
traefik_version = get_docker_version("openc3-traefik/Dockerfile")
valkey_version = get_docker_version("openc3-redis/Dockerfile")
versitygw_version = get_docker_version("openc3-buckets/Dockerfile", arg: 'OPENC3_VERSITYGW_VERSION')
tsdb_version = get_docker_version("openc3-tsdb/Dockerfile", arg: 'OPENC3_TSDB_VERSION')
alpine_version = ENV.fetch('ALPINE_VERSION', '3.23')
alpine_build = ENV.fetch('ALPINE_BUILD', '5')

# Manual list - MAKE SURE UP TO DATE especially base images
containers = [
  # This should match the values in the .env file
  { name: "openc3inc/openc3-ruby:#{version_tag}", base_image: "alpine:#{alpine_version}.#{alpine_build}", apk: true, gems: true, python: true },
  { name: "openc3inc/openc3-node:#{version_tag}", base_image: "openc3inc/openc3-ruby:#{version_tag}", apk: true },
  { name: "openc3inc/openc3-base:#{version_tag}", base_image: "openc3inc/openc3-ruby:#{version_tag}", apk: true, gems: true, python: true },
  { name: "openc3inc/openc3-cosmos-cmd-tlm-api:#{version_tag}", base_image: "openc3inc/openc3-base:#{version_tag}", apk: true, gems: true, python: true },
  { name: "openc3inc/openc3-cosmos-init:#{version_tag}", base_image: "openc3inc/openc3-base:#{version_tag}", apk: true, gems: true, python: true,
    pnpm: ["/openc3/plugins/pnpm-lock.yaml"] },
  { name: "openc3inc/openc3-operator:#{version_tag}", base_image: "openc3inc/openc3-base:#{version_tag}", apk: true, gems: true, python: true },
  { name: "openc3inc/openc3-cosmos-script-runner-api:#{version_tag}", base_image: "openc3inc/openc3-base:#{version_tag}", apk: true, gems: true, python: true },
  { name: "openc3inc/openc3-redis:#{version_tag}", base_image: "valkey:#{valkey_version}", apk: true },
  { name: "openc3inc/openc3-traefik:#{version_tag}", base_image: "traefik:#{traefik_version}", apk: true },
  { name: "openc3inc/openc3-buckets:#{version_tag}", base_image: "alpine:#{alpine_version}.#{alpine_build}", apk: true },
  { name: "openc3inc/openc3-tsdb:#{version_tag}", base_image: "tsdb:#{tsdb_version}", dnf: true },
]

client = Faraday.new do |f|
  f.response :follow_redirects
end

# Build reports (uses currently-running container images for the package inventory)
report = build_report(containers)
summary_report = build_summary_report(containers)

# Check for new versions of all third-party base images / binaries and prompt the
# user to apply each update inline. The previous version of this script only
# printed NOTEs; it now edits the Dockerfiles, .env, and build scripts.
check_alpine(client)
check_container_version(client, containers, 'traefik')
check_container_version(client, containers, 'redis') # valkey base image
new_versitygw = check_versitygw(client, versitygw_version)
check_tsdb(client, tsdb_version)
ruby_container = containers.find { |c| c[:name].include?('openc3-ruby') }
check_anycable(client, ruby_container[:name]) if ruby_container

# After per-image prompts, ensure the build scripts still match the Dockerfiles.
# Re-read the canonical version values in case they just changed.
check_build_files(
  new_versitygw || get_docker_version('openc3-buckets/Dockerfile', arg: 'OPENC3_VERSITYGW_VERSION'),
  get_docker_version('openc3-traefik/Dockerfile')
)

base_pkgs = %w(import-map-overrides pinia single-spa systemjs vue vue-router vuetify)
# FORCE=1 re-downloads the tool-base js/css even when it already matches
# package.json (and downloads fresh when the existing file was deleted).
check_tool_base('openc3-cosmos-init/plugins/packages/openc3-tool-base', base_pkgs, force: ENV['FORCE'] == '1')
puts "\n*** If you update a container version re-run to ensure there aren't additional updates! ***\n\n"

# Per-language outdated dependency prompts. Each helper enumerates outdated
# packages and asks the user yes/no before updating that single package.
%w(openc3 openc3-cosmos-cmd-tlm-api openc3-cosmos-script-runner-api).each do |dir|
  update_outdated_gems(File.join(__dir__, '..', '..', dir))
end

update_outdated_wheels(File.join(__dir__, '..', '..', 'openc3', 'python'))
update_outdated_requirements_txt(
  File.join(__dir__, '..', '..', 'openc3-cosmos-init', 'plugins', 'packages', 'openc3-cosmos-demo'),
  client
)

%w(openc3-cosmos-init/plugins playwright docs.openc3.com).each do |dir|
  update_outdated_pnpm(File.join(__dir__, '..', '..', dir), client)
end

File.open("openc3_package_report.txt", "w") do |file|
  file.write(summary_report)
  file.write(report)
end

# Commenting this out since the templates don't really need to be updated, and updates broke them over time
# puts "\n\nYou can run the following, but check that the templates still work if you do:"
# puts "cd openc3/templates/widget; pnpm install; pnpm update --interactive --latest; cd ../../.."
# puts "cd openc3/templates/tool_vue; pnpm install; pnpm update --interactive --latest; cd ../../.."
# puts "cd openc3/templates/tool_react; pnpm install; pnpm update --interactive --latest; cd ../../.."
# puts "cd openc3/templates/tool_angular; pnpm install; pnpm update --interactive --latest; cd ../../.."
# puts "cd openc3/templates/tool_svelte; pnpm install; pnpm update --interactive --latest; cd ../../.."

puts "\n\n*** If you update #{base_pkgs.join(', ')} then re-run! ***\n\n"
