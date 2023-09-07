# Copyright 2022 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os
from openc3.environment import OPENC3_LOCAL_MODE_PATH


class LocalMode:
    LOCAL_MODE_PATH = OPENC3_LOCAL_MODE_PATH or "/plugins"
    DEFAULT_PLUGINS = [
        "openc3-cosmos-tool-admin",
        "openc3-cosmos-tool-autonomic",
        "openc3-cosmos-tool-bucketexplorer",
        "openc3-cosmos-tool-calendar",
        "openc3-cosmos-tool-cmdsender",
        "openc3-cosmos-tool-cmdtlmserver",
        "openc3-cosmos-tool-dataextractor",
        "openc3-cosmos-tool-dataviewer",
        "openc3-cosmos-tool-handbooks",
        "openc3-cosmos-tool-limitsmonitor",
        "openc3-cosmos-tool-packetviewer",
        "openc3-cosmos-tool-scriptrunner",
        "openc3-cosmos-tool-tablemanager",
        "openc3-cosmos-tool-tlmgrapher",
        "openc3-cosmos-tool-tlmviewer",
        "openc3-cosmos-enterprise-tool-admin",
        "openc3-enterprise-tool-base",
        "openc3-tool-base",
    ]

    # # Install plugins from local plugins folder
    # # Can only be used from openc3cli because calls top_level load_plugin
    # def self.local_init:
    #   if ENV['OPENC3_LOCAL_MODE'] and Dir.exist?(OPENC3_LOCAL_MODE_PATH):
    #     puts "Local init running: {OPENC3_LOCAL_MODE_PATH} exists"
    #      for scope_dir in Dir.each_child(OPENC3_LOCAL_MODE_PATH):
    #       next if not File.directory?("{OPENC3_LOCAL_MODE_PATH}/{scope_dir}")
    #       puts "Local init found scope: {scope_dir}"
    #       Dir.each_child("{OPENC3_LOCAL_MODE_PATH}/{scope_dir}") do |plugin_dir|
    #         full_folder_path = "{OPENC3_LOCAL_MODE_PATH}/{scope_dir}/{plugin_dir}"
    #         if plugin_dir == "targets_modified" or plugin_dir == "tool_config" ||:
    #            plugin_dir == "settings" or !File.directory?(full_folder_path)
    #           next
    #         puts "Local init found plugin_dir: {full_folder_path}"
    #         gems, plugin_instance = scan_plugin_dir(full_folder_path)

    #         if len(gems) > 1:
    #           puts "Local plugin folder contains more than one gem - skipping: {full_folder_path}"
    #           next

    #         if len(gems) == 1 and plugin_instance:
    #           # If one gem file and plugin_instance.json - Install instance
    #           load_plugin(gems[0], scope: scope_dir.upper(), plugin_hash_file: plugin_instance)
    #         elif: len(gems) == 1:
    #           # Else If just gem  - Install with default settings
    #           load_plugin(gems[0], scope: scope_dir.upper())
    #         else:
    #           puts "Local plugin folder contains no gem file - skipping: {full_folder_path}"
    #     sync_targets_modified()
    #     sync_tool_config()
    #     sync_settings()
    #     puts "Local init complete"
    #   else:
    #     puts "Local init canceled: Local mode not enabled or {OPENC3_LOCAL_MODE_PATH} does not exist"

    # @classmethod
    # def scan_plugin_dir(cls, path):
    #   gems = []
    #   plugin_instance = None

    #   Dir.each_child(path) do |filename|
    #     full_path = "{path}/{filename}"
    #     if not File.directory?(full_path):
    #       if File.extname(filename) == '.gem':
    #         gems.append(full_path)
    #       elif: filename == 'plugin_instance.json':
    #         plugin_instance = full_path

    #   return gems, plugin_instance

    # def self.scan_local_mode:
    #   if ENV['OPENC3_LOCAL_MODE'] and Dir.exist?(OPENC3_LOCAL_MODE_PATH):
    #     local_plugins = {}

    #     Dir.each_child(OPENC3_LOCAL_MODE_PATH) do |scope_dir|
    #       full_scope_dir = "{OPENC3_LOCAL_MODE_PATH}/{scope_dir}"
    #       next if not File.directory?(full_scope_dir)
    #       local_plugins[scope_dir] ||= {}
    #       Dir.each_child("{OPENC3_LOCAL_MODE_PATH}/{scope_dir}") do |plugin_dir|
    #         full_folder_path = "{OPENC3_LOCAL_MODE_PATH}/{scope_dir}/{plugin_dir}"
    #         if plugin_dir == "targets_modified" or not File.directory?(full_folder_path):
    #             next
    #         gems, plugin_instance = scan_plugin_dir(full_folder_path)
    #         local_plugins[scope_dir][full_folder_path] = {gems: gems, plugin_instance: plugin_instance}

    #     return local_plugins
    #   return {}

    # @classmethod
    # def analyze_local_mode(cls, plugin_name:, scope:):
    #   if ENV['OPENC3_LOCAL_MODE'] and Dir.exist?(OPENC3_LOCAL_MODE_PATH):
    #     # We already know a plugin with this name doesn't exist in the models
    #     # Now need to determine if there is a highly likely candidate that has been
    #     # updated, so that we don't do an erroneous extra plugin install

    #     gem_name = plugin_name.split("__")[0].split('-')[0..-2].join('-')

    #     local_plugins = scan_local_mode()
    #     scope_plugins = local_plugins[scope]
    #     if scope_plugins:
    #       # Scan models for same gem
    #       found_models = {}
    #       models = OpenC3:'P'luginModel.all(scope: scope)
    #        for name, details in models:
    #         model_gem_name = name.split("__")[0].split('-')[0..-2].join('-')
    #         if gem_name == model_gem_name:
    #             found_models[name] = details

    #       # Definitely new install if no found models
    #       if len(found_models) == 0:
    #           return None

    #       # Scan local for same gem and try to match pairs
    #       found_local_plugins = {}
    #        for folder_path, details in scope_plugins:
    #         gems = details[:gems]
    #         plugin_instance = details[:plugin_instance]
    #         next if not plugin_instance
    #         if len(gems) != 1:
    #             next

    #         local_gem_name = File.basename(gems[0]).split('-')[0..-2].join('-')
    #         if gem_name == local_gem_name:
    #           # Gems match - Do the names match?
    #           data = File.read(plugin_instance)
    #           json = json.loads(data)

    #           found = False
    #            for name, model_details in found_models:
    #             if json["name"] == name:
    #               # Matched pair
    #               found = True
    #               break

    #           if found # names match:
    #             # Remove from the list because we have a matched set
    #             # (local plugin_instance name and plugin model name)
    #             found_models.delete(json["name"])
    #           else:
    #             # Found a local plugin with the right gem, but a different name
    #             found_local_plugins[folder_path] = details

    #       # At this point we only have unmatched plugins in found_models

    #       # Not a local mode install if no found local plugins
    #       if len(found_local_plugins) == 0:
    #           return None

    #       # If we have any unmatched models, assume this should match the first
    #       # (found_models are existing installed plugins with the same gem but
    #       # a different name)
    #        for name, model_details in found_models:
    #         puts "Choosing {name} for update from local plugins"
    #         return model_details
    #   return None

    # # If old_plugin_name then this is an online upgrade
    # @classmethod
    # def update_local_plugin(cls, plugin_file_path, plugin_hash, old_plugin_name: None, scope:):
    #   if ENV['OPENC3_LOCAL_MODE'] and Dir.exist?(OPENC3_LOCAL_MODE_PATH):
    #     variables = plugin_hash['variables']
    #     if variables:
    #        for name in PluginModel:'RESERVED_VARIABLE_NAMES':
    #         variables.delete(name)
    #     if plugin_file_path =~ Regexp("^{OPENC3_LOCAL_MODE_PATH}/{scope}/"):
    #       # From local init - Always just update the exact one
    #       File.open(File.join(File.dirname(plugin_file_path), 'plugin_instance.json'), 'wb') do |file|
    #         file.write(JSON.pretty_generate(plugin_hash))
    #     else:
    #       # From online install / update
    #       # Or init install of container plugin
    #       # Try to find an existing local folder for this plugin
    #       found = False

    #       gem_name = File.basename(plugin_file_path).split('-')[0..-2].join('-')
    #       FileUtils.mkdir_p("{OPENC3_LOCAL_MODE_PATH}/{scope}")

    #       Dir.each_child("{OPENC3_LOCAL_MODE_PATH}/{scope}") do |plugin_dir|
    #         full_folder_path = "{OPENC3_LOCAL_MODE_PATH}/{scope}/{plugin_dir}"
    #         if plugin_dir == "targets_modified" or not File.directory?(full_folder_path):
    #             next

    #         gems, plugin_instance = scan_plugin_dir(full_folder_path)
    #         if len(gems) > 1:
    #             next

    #         if len(gems) == 1:
    #           found_gem_name = File.basename(gems[0]).split('-')[0..-2].join('-')
    #           if found_gem_name == gem_name:
    #             # Same gem at least - Now see if same instance
    #             if plugin_instance:
    #               if old_plugin_name:
    #                 # And we're updating a plugin
    #                 data = File.read(plugin_instance)
    #                 json = json.loads(data)
    #                 if json["name"] == old_plugin_name:
    #                   # Found plugin to update
    #                   found = True
    #                   update_local_plugin_files(full_folder_path, plugin_file_path, plugin_hash, gem_name)
    #               else:
    #                 # New install of same plugin - Leave it alone
    #             else:
    #               # No exiting instance.json, but we found the same gem
    #               # This shouldn't happen without users using this wrong
    #               # We will update
    #               found = True
    #               update_local_plugin_files(full_folder_path, plugin_file_path, plugin_hash, gem_name)

    #       if not found
    #         # Then we will make a local version
    #         # Create a folder for this plugin and add gem and plugin_instance.json
    #         folder_name = gem_name
    #         count = 1
    #         while File.exist?("{OPENC3_LOCAL_MODE_PATH}/{scope}/{folder_name}")
    #           folder_name = gem_name + "-" + str(count)
    #           count += 1
    #         full_folder_path = "{OPENC3_LOCAL_MODE_PATH}/{scope}/{folder_name}"
    #         update_local_plugin_files(full_folder_path, plugin_file_path, plugin_hash, gem_name)

    # @classmethod
    # def update_local_plugin_files(cls, full_folder_path, plugin_file_path, plugin_hash, gem_name):
    #   if DEFAULT_PLUGINS.include?(gem_name):
    #       return
    #   puts "Updating local plugin files: {full_folder_path}"
    #   FileUtils.mkdir_p(full_folder_path)
    #   gems, _ = scan_plugin_dir(full_folder_path)
    #    for gem in gems:
    #     File.delete(gem)
    #   temp_dir = Dir.mktmpdir
    #   try:
    #     if not File.exist?(plugin_file_path)
    #       plugin_file_path = OpenC3:'G'emModel.get(plugin_file_path)
    #     File.open(File.join(full_folder_path, File.basename(plugin_file_path)), 'wb') do |file|
    #       data = File.read(plugin_file_path)
    #       file.write(data)
    #     File.open(File.join(full_folder_path, 'plugin_instance.json'), 'wb') do |file|
    #       file.write(JSON.pretty_generate(plugin_hash))
    #   ensure
    #     if temp_dir and File.exist?(temp_dir):
    #         FileUtils.remove_entry(temp_dir)

    # @classmethod
    # def remove_local_plugin(cls, plugin_name, scope:):
    #   local_plugins = scan_local_mode()
    #   scope_local_plugins = local_plugins[scope]
    #   if scope_local_plugins:
    #      for full_folder_path, details in scope_local_plugins:
    #       gems = details[:gems]
    #       plugin_instance = details[:plugin_instance]
    #       if len(gems) == 1 and plugin_instance:
    #         data = File.read(plugin_instance)
    #         json = json.loads(data)
    #         instance_name = json['name']
    #         if plugin_name == instance_name:
    #           puts "Removing local plugin files: {full_folder_path}"
    #           File.delete(gems[0])
    #           File.delete(plugin_instance)
    #           if Dir.empty?(File.dirname(gems[0])):
    #             FileUtils.rm_rf(File.dirname(gems[0]))
    #           break

    # def self.sync_targets_modified:
    #   bucket = Bucket.getClient()
    #   scopes = ScopeModel.names()
    #    for scope in scopes:
    #     sync_with_bucket(bucket, scope: scope)

    # @classmethod
    # def modified_targets(cls, scope:):
    #   targets = {}
    #   local_catalog = build_local_catalog(scope: scope)
    #    for key, size in local_catalog:
    #     split_key = key.split('/') # scope/targets_modified/target_name/*
    #     target_name = split_key[2]
    #     if target_name:
    #       targets[target_name] = True
    #   return targets.keys.sort

    # @classmethod
    # def modified_files(cls, target_name, scope:):
    #   modified = []
    #   local_catalog = build_local_catalog(scope: scope)
    #    for key, size in local_catalog:
    #     split_key = key.split('/') # scope/targets_modified/target_name/*
    #     local_target_name = split_key[2]
    #     if target_name == local_target_name:
    #       modified.append(split_key[3:].join('/'))
    #   # Paths do not include target name
    #   return modified.sort

    # @classmethod
    # def delete_modified(cls, target_name, scope:):
    #   full_path = "{OPENC3_LOCAL_MODE_PATH}/{scope}/targets_modified/{target_name}"
    #   FileUtils.rm_rf(full_path)

    # @classmethod
    # def zip_target(cls, target_name, zip, scope:):
    #   modified = modified_files(target_name, scope: scope)
    #    for file_path in modified:
    #     full_path = "{OPENC3_LOCAL_MODE_PATH}/{scope}/targets_modified/{target_name}/{file_path}"
    #     zip.add(file_path, full_path)

    @classmethod
    def put_target_file(cls, path, io_or_string, scope):
        full_folder_path = f"{OPENC3_LOCAL_MODE_PATH}/{path}"
        os.makedirs(os.path.dirname(full_folder_path), exist_ok=True)
        flags = "w"
        if type(io_or_string) == bytes:
            flags += "b"
        with open(full_folder_path, flags) as file:
            if hasattr(io_or_string, "read"):
                data = io_or_string.read()
            else:  # str or bytes
                data = io_or_string
            file.write(data)

    @classmethod
    def open_local_file(cls, path, scope):
        try:
            full_path = f"{cls.LOCAL_MODE_PATH}/{scope}/targets_modified/{path}"
            return open(full_path, "rb")
        except OSError:
            return None

    # @classmethod
    # def local_target_files(cls, scope:, path_matchers:, include_temp: False):
    #   files = []
    #   local_catalog = build_local_catalog(scope: scope)
    #    for key, size in local_catalog:
    #     split_key = key.split('/')
    #     # DEFAULT/targets_modified/__TEMP__/YYYY_MM_DD_HH_MM_SS_mmm_temp.rb
    #     # See target_file.rb TEMP_FOLDER
    #     if split_key[2] === '__TEMP__':
    #       if include_temp:
    #           files.append(split_key[2:].join('/'))
    #       next
    #     if path_matchers:
    #       found = False
    #        for path in path_matchers:
    #         if split_key.include?(path):
    #           found = True
    #           break
    #       next if not found
    #     files.append(split_key[2:].join('/'))
    #   return files.sort

    # @classmethod
    # def sync_tool_config(cls, ):
    #   scopes = ScopeModel.names()
    #    for scope in scopes:
    #      for config in Dir["{OPENC3_LOCAL_MODE_PATH}/{scope}/tool_config/**/*.json"]:
    #       parts = config.split('/')
    #       puts "Syncing tool_config {parts[-2]} {File.basename(config)}"
    #       data = File.read(config)
    #       try:
    #         # Parse just to ensure we have valid JSON
    #         json.loads(data)
    #         # Only save if the parse was successful
    #         ToolConfigModel.save_config(parts[-2], File.basename(config, '.json'), data, scope: scope, local_mode: False)
    #       except: JSON:'P'arserError : error
    #         puts "Unable to initialize tool config due to {error.message}"

    # @classmethod
    # def save_tool_config(cls, scope, tool, name, data):
    #   json = json.loads(data)
    #   config_path = "{OPENC3_LOCAL_MODE_PATH}/{scope}/tool_config/{tool}/{name}.json"
    #   FileUtils.mkdir_p(File.dirname(config_path))
    #   File.open(config_path, 'w') do |file|
    #     file.write(JSON.pretty_generate(json))

    # @classmethod
    # def delete_tool_config(cls, scope, tool, name):
    #   FileUtils.rm_f("{OPENC3_LOCAL_MODE_PATH}/{scope}/tool_config/{tool}/{name}.json")

    # @classmethod
    # def sync_settings(cls, ):
    #   scopes = ScopeModel.names()
    #    for scope in scopes:
    #      for config in Dir["{OPENC3_LOCAL_MODE_PATH}/{scope}/settings/*.json"]:
    #       name = File.basename(config, ".json")
    #       puts "Syncing setting {name}"
    #       # Anything can be stored in settings so read and set directly
    #       data = File.read(config)
    #       SettingModel.set({ name: name, data: data }, scope: scope)

    # @classmethod
    # def save_setting(cls, scope, name, data):
    #   config_path = "{OPENC3_LOCAL_MODE_PATH}/{scope}/settings/{name}.json"
    #   FileUtils.mkdir_p(File.dirname(config_path))
    #   # Anything can be stored as a setting so write it out directly
    #   File.write(config_path, data)

    # # Helper methods

    # @classmethod
    # def sync_remote_to_local(cls, bucket, key):
    #   local_path = "{OPENC3_LOCAL_MODE_PATH}/{key}"
    #   FileUtils.mkdir_p(File.dirname(local_path))
    #   bucket.get_object(bucket: ENV['OPENC3_CONFIG_BUCKET'], key: key, path: local_path)

    # @classmethod
    # def sync_local_to_remote(cls, bucket, key):
    #   local_path = "{OPENC3_LOCAL_MODE_PATH}/{key}"
    #   File.open(local_path, 'rb') do |read_file|
    #     bucket.put_object(bucket: ENV['OPENC3_CONFIG_BUCKET'], key: key, body: read_file)

    # @classmethod
    # def delete_local(cls, key):
    #   local_path = "{OPENC3_LOCAL_MODE_PATH}/{key}"
    #   if File.exist?(local_path):
    #       File.delete(local_path)
    #   None

    # @classmethod
    # def delete_remote(cls, bucket, key):
    #   bucket.delete_object(bucket: ENV['OPENC3_CONFIG_BUCKET'], key: key)

    # # Returns equivalent names and sizes to remote catalog
    # # {"scope/targets_modified/target_name/file" => size}
    # @classmethod
    # def build_local_catalog(cls, scope:):
    #   local_catalog = {}
    #   local_folder_path = "{OPENC3_LOCAL_MODE_PATH}/{scope}/targets_modified"
    #   prefix_length = "{OPENC3_LOCAL_MODE_PATH}/".length
    #   FileUtils.mkdir_p(local_folder_path)
    #   Dir.glob(local_folder_path + "/**/*").each do |filename|
    #     if File.directory?(filename):
    #         next
    #     mod_filename = filename[prefix_length:]
    #     local_catalog[mod_filename] = File.size(filename)
    #   return local_catalog

    # # Returns keys and sizes from remote catalog
    # # {"scope/targets_modified/target_name/file" => size}
    # @classmethod
    # def build_remote_catalog(cls, bucket, scope:):
    #   remote_catalog = {}
    #   prefix = "{scope}/targets_modified"
    #   resp = bucket.list_objects(
    #     bucket: ENV['OPENC3_CONFIG_BUCKET'],
    #     prefix: prefix,
    #   )
    #    for item in resp:
    #     remote_catalog[item.key] = item.size
    #   return remote_catalog

    # @classmethod
    # def sync_with_bucket(cls, bucket, scope:):
    #   # Build catalogs
    #   local_catalog = build_local_catalog(scope: scope)
    #   remote_catalog = build_remote_catalog(bucket, scope: scope)

    #   # Find and Handle Differences
    #    for key, size in local_catalog:
    #     remote_size = remote_catalog[key]
    #     if remote_size:
    #       # Both files exist
    #       if ENV['OPENC3_LOCAL_MODE_SECONDARY']:
    #         if size != remote_size or ENV['OPENC3_LOCAL_MODE_FORCE_SYNC']:
    #             sync_remote_to_local(bucket, key)
    #       else:
    #         if size != remote_size or ENV['OPENC3_LOCAL_MODE_FORCE_SYNC']:
    #             sync_local_to_remote(bucket, key)
    #     else:
    #       # Remote is missing local file
    #       if ENV['OPENC3_LOCAL_MODE_SECONDARY'] and ENV['OPENC3_LOCAL_MODE_SYNC_REMOVE']:
    #         delete_local(key)
    #       else:
    #         # Go ahead and copy up to get in sync
    #         sync_local_to_remote(bucket, key)

    #    for key, size in remote_catalog:
    #     local_size = local_catalog[key]
    #     if local_size:
    #       # Both files exist - Handled earlier
    #     else:
    #       # Local is missing remote file
    #       if not ENV['OPENC3_LOCAL_MODE_SECONDARY'] and ENV['OPENC3_LOCAL_MODE_SYNC_REMOVE']:
    #         delete_remote(bucket, key)
    #       else:
    #         # Go ahead and copy down to get in sync
    #         sync_remote_to_local(bucket, key)
