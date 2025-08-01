# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/utilities/process_manager'
require 'openc3/models/plugin_store_model'
require 'openc3/models/plugin_model'
require 'down'
require 'fileutils'
require 'tmpdir'
require 'digest'

class PluginsController < ModelController
  def initialize
    @model_class = OpenC3::PluginModel
  end

  def show
    return unless authorization('system')
    if params[:id].downcase == 'all'
      store_plugins = OpenC3::PluginStoreModel.all()
      store_plugins = JSON.parse(store_plugins)
      plugins = @model_class.all(scope: params[:scope])
      plugins.each do |plugin_name, plugin|
        if plugin['store_id']
          store_data = store_plugins.find { |store_plugin| store_plugin['id'] == plugin['store_id'] }
          plugin.merge!(store_data) if store_data
        end
      end

      render json: plugins
    else
      plugin = @model_class.get(name: params[:id], scope: params[:scope])
      if plugin && plugin['store_id']
        store_data = OpenC3::PluginStoreModel.get_by_id(plugin['store_id'])
        plugin.merge!(store_data) if store_data
      end

      render json: plugin
    end
  rescue StandardError => error
    render json: { status: 'error', message: error.message }, status: 500
    logger.error(error.formatted)
  end

  # Add a new plugin
  def create(update = false)
    return unless authorization('admin')
    file = if params[:store_id]
      store_data = OpenC3::PluginStoreModel.get_by_id(params[:store_id])
      if store_data.nil? || store_data['gem_url'].nil?
        render json: { status: 'error', message: 'Unable to fetch requested plugin.' }, status: 500
        return
      end
      tempfile = Down.download(store_data['gem_url'])
      original_filename = File.basename(store_data['gem_url'])

      checksum = Digest::SHA256.file(tempfile.path).hexdigest.downcase
      expected = store_data['checksum'].downcase
      unless checksum == expected
        render json: { status: 'error', message: "Checksum verification failed. Expected #{expected} but got #{checksum}" }, status: 500
        return
      end

      tempfile
    else
      params[:plugin]
    end
    if file
      tempfile = file.tempfile unless tempfile
      original_filename = file.original_filename unless original_filename
      scope = sanitize_params([:scope])
      return unless scope
      scope = scope[0]
      temp_dir = Dir.mktmpdir
      begin
        gem_file_path = temp_dir + '/' + original_filename
        FileUtils.cp(tempfile.path, gem_file_path)
        if @existing_model
          result = OpenC3::PluginModel.install_phase1(gem_file_path, existing_variables: @existing_model['variables'], existing_plugin_txt_lines: @existing_model['plugin_txt_lines'], store_id: params[:store_id], scope: scope)
        else
          result = OpenC3::PluginModel.install_phase1(gem_file_path, store_id: params[:store_id], scope: scope)
        end
        render json: result
      rescue Exception => error
        render json: { status: 'error', message: error.message }, status: 500
        logger.error(error.formatted)
      ensure
        FileUtils.remove_entry_secure(temp_dir, true)
      end
    else
      logger.error("No file received")
      render json: { status: 'error', message: "No file received" }, status: 500
    end
  end

  def update
    return unless authorization('admin')
    # Grab the existing plugin we're updating so we can display existing variables
    @existing_model = @model_class.get(name: params[:id], scope: params[:scope])
    create(true)
  end

  def install
    return unless authorization('admin')
    begin
      scope = sanitize_params([:scope])
      return unless scope
      scope = scope[0]
      temp_dir = Dir.mktmpdir
      plugin_hash_filename = Dir::Tmpname.create(['plugin-instance-', '.json']) {}
      plugin_hash_file_path = File.join(temp_dir, File.basename(plugin_hash_filename))
      File.open(plugin_hash_file_path, 'wb') do |file|
        file.write(params[:plugin_hash])
      end

      gem_name = sanitize_params([:id])
      return unless gem_name
      gem_name = gem_name[0].split("__")[0]
      result = OpenC3::ProcessManager.instance.spawn(
        ["ruby", "/openc3/bin/openc3cli", "load", gem_name, scope, plugin_hash_file_path, "force"], # force install
        "plugin_install", params[:id], Time.now + 1.hour, temp_dir: temp_dir, scope: scope
      )
      render json: result.name
    rescue Exception => error
      logger.error(error.formatted)
      render json: { status: 'error', message: error.message }, status: 500
    end
  end

  def destroy
    return unless authorization('admin')
    begin
      id, scope = sanitize_params([:id, :scope])
      return unless id and scope
      result = OpenC3::ProcessManager.instance.spawn(["ruby", "/openc3/bin/openc3cli", "unload", id, scope], "plugin_uninstall", id, Time.now + 1.hour, scope: scope)
      render json: result.name
    rescue Exception => error
      logger.error(error.formatted)
      render json: { status: 'error', message: error.message }, status: 500
    end
  end
end
