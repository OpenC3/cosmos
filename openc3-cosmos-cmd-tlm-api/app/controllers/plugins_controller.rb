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
require 'openc3/models/plugin_model'
require 'down'
require 'fileutils'
require 'tmpdir'

class PluginsController < ModelController
  def initialize
    @model_class = OpenC3::PluginModel
  end

  # Add a new plugin
  def create(update = false)
    return unless authorization('admin')
    file = if params[:gem_url]
      tempfile = Down.download(params[:gem_url])
      original_filename = File.basename(params[:gem_url])
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
          result = OpenC3::PluginModel.install_phase1(gem_file_path, existing_variables: @existing_model['variables'], existing_plugin_txt_lines: @existing_model['plugin_txt_lines'], scope: scope)
        else
          result = OpenC3::PluginModel.install_phase1(gem_file_path, scope: scope)
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
