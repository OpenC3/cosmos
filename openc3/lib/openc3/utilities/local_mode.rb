# encoding: ascii-8bit

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

require 'fileutils'
require 'json'
# require 'openc3/models/gem_model' # These are used but also create circular dependency
# require 'openc3/models/plugin_model' # These are used but also create circular dependency
require 'openc3/utilities/s3'


module OpenC3
  module LocalMode
    OPENC3_LOCAL_MODE_PATH = ENV['OPENC3_LOCAL_MODE_PATH'] || "/plugins"

    DEFAULT_PLUGINS = [
      'openc3-tool-admin',
      'openc3-tool-autonomic',
      'openc3-tool-base',
      'openc3-tool-calendar',
      'openc3-tool-cmdsender',
      'openc3-tool-cmdtlmserver',
      'openc3-tool-dataextractor',
      'openc3-tool-dataviewer',
      'openc3-tool-handbooks',
      'openc3-tool-limitsmonitor',
      'openc3-tool-packetviewer',
      'openc3-tool-scriptrunner',
      'openc3-tool-tablemanager',
      'openc3-tool-tlmgrapher',
      'openc3-tool-tlmviewer',
      'openc3-enterprise-tool-base',
      'openc3-enterprise-tool-admin',
    ]

    # Install plugins from local plugins folder
    def self.local_init
      if ENV['OPENC3_LOCAL_MODE'] and Dir.exist?(OPENC3_LOCAL_MODE_PATH)
        puts "Local init running: #{OPENC3_LOCAL_MODE_PATH} exists"
        Dir.each_child(OPENC3_LOCAL_MODE_PATH).each do |scope_dir|
          next unless File.directory?("#{OPENC3_LOCAL_MODE_PATH}/#{scope_dir}")
          puts "Local init found scope: #{scope_dir}"
          Dir.each_child("#{OPENC3_LOCAL_MODE_PATH}/#{scope_dir}") do |plugin_dir|
            full_folder_path = "#{OPENC3_LOCAL_MODE_PATH}/#{scope_dir}/#{plugin_dir}"
            next if plugin_dir == "targets_modified" or not File.directory?(full_folder_path)
            puts "Local init found plugin_dir: #{full_folder_path}"
            gems, plugin_instance = scan_plugin_dir(full_folder_path)

            if gems.length > 1
              puts "Local plugin folder contains more than one gem - skipping: #{full_folder_path}"
              next
            end

            if gems.length == 1 and plugin_instance
              # If one gem file and plugin_instance.json - Install instance
              load_plugin(gems[0], scope: scope_dir.upcase, plugin_hash_file: plugin_instance)
            elsif gems.length == 1
              # Else If just gem  - Install with default settings
              load_plugin(gems[0], scope: scope_dir.upcase)
            else
              puts "Local plugin folder contains no gem file - skipping: #{full_folder_path}"
            end
          end
        end
        sync_targets_modified()
        puts "Local init complete"
      else
        puts "Local init canceled: Local mode not enabled or #{OPENC3_LOCAL_MODE_PATH} does not exist"
      end
    end

    def self.scan_plugin_dir(path)
      gems = []
      plugin_instance = nil

      Dir.each_child(path) do |filename|
        full_path = "#{path}/#{filename}"
        if not File.directory?(full_path)
          if File.extname(filename) == '.gem'
            gems << full_path
          elsif filename == 'plugin_instance.json'
            plugin_instance = full_path
          end
        end
      end

      return gems, plugin_instance
    end

    def self.scan_local_mode
      if ENV['OPENC3_LOCAL_MODE'] and Dir.exist?(OPENC3_LOCAL_MODE_PATH)
        local_plugins = {}

        Dir.each_child(OPENC3_LOCAL_MODE_PATH) do |scope_dir|
          full_scope_dir = "#{OPENC3_LOCAL_MODE_PATH}/#{scope_dir}"
          next unless File.directory?(full_scope_dir)
          local_plugins[scope_dir] ||= {}
          Dir.each_child("#{OPENC3_LOCAL_MODE_PATH}/#{scope_dir}") do |plugin_dir|
            full_folder_path = "#{OPENC3_LOCAL_MODE_PATH}/#{scope_dir}/#{plugin_dir}"
            next if plugin_dir == "targets_modified" or not File.directory?(full_folder_path)
            gems, plugin_instance = scan_plugin_dir(full_folder_path)
            local_plugins[scope_dir][full_folder_path] = {gems: gems, plugin_instance: plugin_instance}
          end
        end

        return local_plugins
      end
      return {}
    end

    def self.analyze_local_mode(plugin_name:, scope:)
      if ENV['OPENC3_LOCAL_MODE'] and Dir.exist?(OPENC3_LOCAL_MODE_PATH)
        # We already know a plugin with this name doesn't exist in the models
        # Now need to determine if there is a highly likely candidate that has been
        # updated, so that we don't do an erroneous extra plugin install

        gem_name = plugin_name.split("__")[0].split('-')[0..-2].join('-')

        local_plugins = scan_local_mode()
        scope_plugins = local_plugins[scope]
        if scope_plugins
          # Scan models for same gem
          found_models = {}
          models = OpenC3::PluginModel.all(scope: scope)
          models.each do |name, details|
            model_gem_name = name.split("__")[0].split('-')[0..-2].join('-')
            found_models[name] = details if gem_name == model_gem_name
          end

          # Definitely new install if no found models
          return nil if found_models.length == 0

          # Scan local for same gem and try to match pairs
          found_local_plugins = {}
          scope_plugins.each do |folder_path, details|
            gems = details[:gems]
            plugin_instance = details[:plugin_instance]
            next if gems.length != 1

            local_gem_name = File.basename(gems[0]).split('-')[0..-2].join('-')
            if gem_name == local_gem_name
              # Gems match - Do the names match?
              data = File.read(plugin_instance)
              json = JSON.parse(data, :allow_nan => true, :create_additions => true)

              found = false
              found_models.each do |name, model_details|
                if json["name"] == name
                  # Matched pair
                  found = true
                  break
                end
              end

              if found
                found_models.delete(json["name"])
              else
                found_local_plugins[folder_path] = details
              end
            end
          end

          # At this point we only have unmatched plugins

          # Not a local mode install if no found local plugins
          return nil if found_local_plugins.length == 0

          # If we have any unmatched models, assume this should match the first
          found_models.each do |name, model_details|
            puts "Chose #{name} for update from local plugins"
            return model_details
          end
        end
      end
      return nil
    end

    # If old_plugin_name then this is an online upgrade
    def self.update_local_plugin(plugin_file_path, plugin_hash, old_plugin_name: nil, scope:)
      if ENV['OPENC3_LOCAL_MODE']
        variables = plugin_hash['variables']
        if variables
          variables.delete("target_name")
          variables.delete("microservice_name")
        end
        if plugin_file_path =~ Regexp.new("^#{OPENC3_LOCAL_MODE_PATH}/#{scope}/")
          # From local init - Always just update the exact one
          File.open(File.join(File.dirname(plugin_file_path), 'plugin_instance.json'), 'wb') do |file|
            file.write(JSON.pretty_generate(plugin_hash, :allow_nan => true))
          end
        else
          # From online install / update
          if Dir.exist?(OPENC3_LOCAL_MODE_PATH)
            # Try to find an existing local folder for this plugin
            found = false

            gem_name = File.basename(plugin_file_path).split('-')[0..-2].join('-')
            FileUtils.mkdir_p("#{OPENC3_LOCAL_MODE_PATH}/#{scope}")

            Dir.each_child("#{OPENC3_LOCAL_MODE_PATH}/#{scope}") do |plugin_dir|
              full_folder_path = "#{OPENC3_LOCAL_MODE_PATH}/#{scope}/#{plugin_dir}"
              next if plugin_dir == "targets_modified" or not File.directory?(full_folder_path)

              gems, plugin_instance = scan_plugin_dir(full_folder_path)
              next if gems.length > 1

              if gems.length == 1
                found_gem_name = File.basename(gems[0]).split('-')[0..-2].join('-')
                if found_gem_name == gem_name
                  # Same gem at least - Now see if same instance
                  if plugin_instance
                    if old_plugin_name
                      # And we're updating a plugin
                      data = File.read(plugin_instance)
                      json = JSON.parse(data, :allow_nan => true, :create_additions => true)
                      if json["name"] == old_plugin_name
                        # Found plugin to update
                        found = true
                        update_local_plugin_files(full_folder_path, plugin_file_path, plugin_hash, gem_name)
                      end
                    else
                      # New install of same plugin - Leave it alone
                    end
                  else
                    # No exiting instance.json, but we found the same gem
                    # This shouldn't happen without users using this wrong
                    # We will update
                    found = true
                    update_local_plugin_files(full_folder_path, plugin_file_path, plugin_hash, gem_name)
                  end
                end
              end
            end

            unless found
              # Then we will make a local version
              # Create a folder for this plugin and add gem and plugin_instance.json
              folder_name = gem_name
              count = 1
              while File.exist?("#{OPENC3_LOCAL_MODE_PATH}/#{scope}/#{folder_name}")
                folder_name = gem_name + "-" + count.to_s
                count += 1
              end
              full_folder_path = "#{OPENC3_LOCAL_MODE_PATH}/#{scope}/#{folder_name}"
              update_local_plugin_files(full_folder_path, plugin_file_path, plugin_hash, gem_name)
            end
          end
        end
      end
    end

    def self.update_local_plugin_files(full_folder_path, plugin_file_path, plugin_hash, gem_name)
      return if DEFAULT_PLUGINS.include?(gem_name)
      puts "Updating local plugin files: #{full_folder_path}"
      FileUtils.mkdir_p(full_folder_path)
      gems, plugin_instance = scan_plugin_dir(full_folder_path)
      gems.each do |gem|
        File.delete(gem)
      end
      temp_dir = Dir.mktmpdir
      begin
        unless File.exists?(plugin_file_path)
          plugin_file_path = OpenC3::GemModel.get(temp_dir, plugin_file_path)
        end
        File.open(File.join(full_folder_path, File.basename(plugin_file_path)), 'wb') do |file|
          data = File.read(plugin_file_path)
          file.write(data)
        end
        File.open(File.join(full_folder_path, 'plugin_instance.json'), 'wb') do |file|
          file.write(JSON.pretty_generate(plugin_hash, :allow_nan => true))
        end
      ensure
        FileUtils.remove_entry(temp_dir) if temp_dir and File.exist?(temp_dir)
      end
    end

    def self.remove_local_plugin(plugin_name, scope:)
      local_plugins = scan_local_mode()
      scope_local_plugins = local_plugins[scope]
      if scope_local_plugins
        scope_local_plugins.each do |full_folder_path, details|
          gems = details[:gems]
          plugin_instance = details[:plugin_instance]
          if gems.length == 1 and plugin_instance
            data = File.read(plugin_instance)
            json = JSON.parse(data, :allow_nan => true, :create_additions => true)
            instance_name = json['name']
            if plugin_name == instance_name
              puts "Removing local plugin files: #{full_folder_path}"
              File.delete(gems[0])
              File.delete(plugin_instance)
              break
            end
          end
        end
      end
    end

    def self.sync_targets_modified
      if ENV['OPENC3_LOCAL_MODE'] and Dir.exist?(OPENC3_LOCAL_MODE_PATH)
        rubys3_client = Aws::S3::Client.new

        # Ensure config bucket exists
        begin
          rubys3_client.head_bucket(bucket: 'config')
        rescue Aws::S3::Errors::NotFound
          rubys3_client.create_bucket(bucket: 'config')
        end

        scopes = ScopeModel.names()
        scopes.each do |scope|
          sync_with_minio(rubys3_client, scope: scope)
        end
      end
    end

    def self.modified_targets(scope:)
      targets = {}
      local_catalog = build_local_catalog(scope: scope)
      local_catalog.each do |key, size|
        split_key = key.split('/') # scope/targets_modified/target_name/*
        target_name = split_key[2]
        if target_name
          targets[target_name] = true
        end
      end
      return targets.keys
    end

    def self.modified_files(target_name, scope:)
      modified = []
      local_catalog = build_local_catalog(scope: scope)
      local_catalog.each do |key, size|
        split_key = key.split('/') # scope/targets_modified/target_name/*
        target_name = split_key[2]
        if target_name == target_name
          modified << split_key[3..-1].join('/')
        end
      end
      return modified
    end

    def self.delete_modified(target_name, scope:)
      full_path = "#{OPENC3_LOCAL_MODE_PATH}/#{scope}/#{target_name}"
      FileUtils.rm_rf(full_path)
    end

    def self.zip_target(target_name, zip, scope:)
      modified = modified_files(target_name, scope: scope)
      modified.each do |file_path|
        full_path = "#{OPENC3_LOCAL_MODE_PATH}/#{scope}/#{target_name}/#{file_path}"
        zip.add(file_path, full_path)
      end
    end

    def self.put_target_file(path, io_or_string, scope:)
      full_folder_path = "#{OPENC3_LOCAL_MODE_PATH}/#{path}"
      FileUtils.mkdir_p(File.dirname(full_folder_path))
      File.open(full_folder_path, 'wb') do |file|
        if String === io_or_string
          data = io_or_string
        else
          data = io_or_string.read
        end
        file.write(data)
      end
    end

    def self.open_local_file(path, scope:)
      full_path = "#{OPENC3_LOCAL_MODE_PATH}/#{scope}/targets_modified/#{path}"
      return File.open(full_path, 'rb') if File.exist?(full_path)
      return nil
    end

    def self.local_target_files(scope:, path_matchers:)
      files = []
      local_catalog = build_local_catalog(scope: scope)
      local_catalog.each do |key, size|
        split_key = key.split('/')
        found = false
        path_matchers.each do |path|
          if split_key.include?(path)
            found = true
            break
          end
        end
        next unless found
        files << split_key[2..-1].join('/')
      end
      return files
    end

    # Helper methods

    def self.sync_remote_to_local(rubys3_client, key)
      local_path = "#{OPENC3_LOCAL_MODE_PATH}/#{key}"
      FileUtils.mkdir_p(File.dirname(local_path))
      rubys3_client.get_object(bucket: 'config', key: key, response_target: local_path)
    end

    def self.sync_local_to_remote(rubys3_client, key)
      local_path = "#{OPENC3_LOCAL_MODE_PATH}/#{key}"
      File.open(local_path, 'rb') do |read_file|
        rubys3_client.put_object(bucket: 'config', key: key, body: read_file)
      end
    end

    def self.delete_local(key)
      local_path = "#{OPENC3_LOCAL_MODE_PATH}/#{key}"
      File.delete(local_path)
    end

    def self.delete_remote(rubys3_client, key)
      rubys3_client.delete_object(bucket: 'config', key: key)
    end

    # Returns equivalent names and sizes to remote catalog
    # {"scope/targets_modified/target_name/file" => size}
    def self.build_local_catalog(scope:)
      local_catalog = {}
      local_folder_path = "#{OPENC3_LOCAL_MODE_PATH}/#{scope}/targets_modified"
      prefix_length = "#{OPENC3_LOCAL_MODE_PATH}/".length
      FileUtils.mkdir_p(local_folder_path)
      Dir.glob(local_folder_path + "/**/*").each do |filename|
        next if File.directory?(filename)
        mod_filename = filename[prefix_length..-1]
        local_catalog[mod_filename] = File.size(filename)
      end
      return local_catalog
    end

    # Returns keys and sizes from remote catalog
    # {"scope/targets_modified/target_name/file" => size}
    def self.build_remote_catalog(rubys3_client, scope:)
      remote_catalog = {}
      bucket = 'config'
      prefix = "#{scope}/targets_modified"
      token = nil
      while true
        resp = rubys3_client.list_objects_v2({
          bucket: bucket,
          max_keys: 1000,
          prefix: prefix,
          continuation_token: token
        })

        resp.contents.each do |item|
          remote_catalog[item.key] = item.size
        end
        break unless resp.is_truncated
        token = resp.next_continuation_token
      end
      return remote_catalog
    end

    def self.sync_with_minio(rubys3_client, scope:)
      # Build catalogs
      local_catalog = build_local_catalog(scope: scope)
      remote_catalog = build_remote_catalog(rubys3_client, scope: scope)

      # Find and Handle Differences
      local_catalog.each do |key, size|
        remote_size = remote_catalog[key]
        if remote_size
          # Both files exist
          if ENV['OPENC3_LOCAL_MODE_SECONDARY']
            sync_remote_to_local(rubys3_client, key) if size != remote_size or ENV['OPENC3_LOCAL_MODE_FORCE_SYNC']
          else
            sync_local_to_remote(rubys3_client, key) if size != remote_size or ENV['OPENC3_LOCAL_MODE_FORCE_SYNC']
          end
        else
          # Remote is missing local file
          if ENV['OPENC3_LOCAL_MODE_SECONDARY'] and ENV['OPENC3_LOCAL_MODE_SYNC_REMOVE']
            delete_local(key)
          else
            # Go ahead and copy up to get in sync
            sync_local_to_remote(rubys3_client, key)
          end
        end
      end

      remote_catalog.each do |key, size|
        local_size = local_catalog[key]
        if local_size
          # Both files exist - Handled earlier
        else
          # Local is missing remote file
          if not ENV['OPENC3_LOCAL_MODE_SECONDARY'] and ENV['OPENC3_LOCAL_MODE_SYNC_REMOVE']
            delete_remote(rubys3_client, key)
          else
            # Go ahead and copy down to get in sync
            sync_remote_to_local(rubys3_client, key)
          end
        end
      end
    end

  end
end