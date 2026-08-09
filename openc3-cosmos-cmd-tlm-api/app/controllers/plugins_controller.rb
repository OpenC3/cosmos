# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/utilities/process_manager'
require 'openc3/models/plugin_store_model'
require 'openc3/models/plugin_model'
require 'openc3/models/setting_model'
require 'down'
require 'fileutils'
require 'tmpdir'
require 'digest'
require 'net/http'
require 'uri'

class PluginsController < ModelController
  def initialize
    @model_class = OpenC3::PluginModel
  end

  def check_localhost_reachability(gem_url, store_plugin_id)
    uri = URI.parse(gem_url)
    return gem_url unless ['localhost', '127.0.0.1'].include? uri.host

    api_key_setting = OpenC3::SettingModel.get(name: 'store_api_key', scope: 'DEFAULT')
    api_key = api_key_setting['data'] if api_key_setting

    test_url = "http://#{uri.host}:#{uri.port}/api/v1.2/cosmos_plugins/#{store_plugin_id}"
    begin
      uri_obj = URI(test_url)
      req = Net::HTTP::Get.new(uri_obj)
      req['Authorization'] = "Bearer #{api_key}" if api_key && !api_key.strip.empty?

      response = Net::HTTP.start(uri_obj.hostname, uri_obj.port) do |http|
        http.request(req)
      end
      return gem_url if response.code.to_i < 400
    rescue
      # localhost not reachable, try host.docker.internal
    end

    docker_gem_url = gem_url.gsub(uri.host, 'host.docker.internal')
    docker_test_url = test_url.gsub(uri.host, 'host.docker.internal')
    begin
      uri_obj = URI(docker_test_url)
      req = Net::HTTP::Get.new(uri_obj)
      req['Authorization'] = "Bearer #{api_key}" if api_key && !api_key.strip.empty?

      response = Net::HTTP.start(uri_obj.hostname, uri_obj.port) do |http|
        http.request(req)
      end
      return docker_gem_url if response.code.to_i < 400
    rescue
      # host.docker.internal not reachable either
    end

    nil # indicates unreachable download location
  end

  def show
    return unless authorization('system')
    if params[:id].downcase == 'all'
      plugins = @model_class.all(scope: params[:scope])
      # Enrich with per-plugin UV migration status (derived from filesystem, not stored in Redis).
      # Must run before the store data merge below, which adds keys that PluginModel.new doesn't accept.
      plugins.each do |_plugin_name, plugin|
        model = @model_class.new(**(plugin.transform_keys(&:to_sym)), scope: params[:scope])
        plugin['needs_uv_migration'] = model.needs_uv_migration?
      end
      OpenC3::PluginStoreModel.ensure_exists()
      store_plugins = OpenC3::PluginStoreModel.all()
      store_plugins = JSON.parse(store_plugins)
      if store_plugins.is_a?(Array) # as opposed to a Hash, which indicates an error
        plugins.each do |plugin_name, plugin|
          if plugin['store_plugin_id']
            store_plugin = store_plugins.find { |store_plugin| store_plugin['id'] == plugin['store_plugin_id'] }
            store_version_id = plugin['store_version_id'] || store_plugin['current_version_id']
            store_version = store_plugin['versions'].find { |store_version| store_version['id'] == store_version_id }
            plugin.merge!(store_version) if store_version
          end
        end
      end

      render json: plugins
    else
      plugin = @model_class.get(name: params[:id], scope: params[:scope])
      if plugin && plugin['store_plugin_id']
        store_plugin = OpenC3::PluginStoreModel.get_by_id(plugin['store_plugin_id'])
        store_version_id = plugin['store_version_id'] || store_plugin['current_version_id']
        store_version = store_plugin['versions'].find { |store_version| store_version['id'] == store_version_id }
        plugin.merge!(store_version) if store_version
      end

      render json: plugin
    end
  rescue StandardError => error
    render json: { status: 'error', message: error.message }, status: :internal_server_error
    logger.error(error.formatted)
  end

  # Add a new plugin
  def create(update = false)
    return unless authorization('admin')
    file = if params[:store_plugin_id]
      store_data = OpenC3::PluginStoreModel.get_by_id(params[:store_plugin_id])
      unless store_data.nil?
        store_version_id = params[:store_version_id] || store_data['current_version_id']
        store_version_id = Integer(store_version_id)
        store_version = store_data['versions'].find { |version| version['id'] == store_version_id }
      end
      if store_version.nil? || store_version['gem_url'].nil?
        render json: { status: 'error', message: 'Unable to fetch requested plugin version.' }, status: :internal_server_error
        return
      end

      # Try to find the correct hostname (in case it's localhost and needs to be host.docker.internal)
      adjusted_gem_url = check_localhost_reachability(store_version['gem_url'], params[:store_plugin_id])
      if adjusted_gem_url.nil?
        render json: { status: 'error', message: 'Gem could not be downloaded. Host is not reachable.' }, status: :internal_server_error
        return
      end

      api_key_setting = OpenC3::SettingModel.get(name: 'store_api_key', scope: 'DEFAULT')
      api_key = api_key_setting['data'] if api_key_setting

      if api_key && !api_key.strip.empty?
        tempfile = Down.download(adjusted_gem_url, headers: { 'Authorization' => "Bearer #{api_key}" })
      else
        tempfile = Down.download(adjusted_gem_url)
      end
      checksum = Digest::SHA256.file(tempfile.path).hexdigest.downcase
      expected = store_version['checksum'].downcase
      unless checksum == expected
        render json: { status: 'error', message: "Checksum verification failed. Expected #{expected} but got #{checksum}" }, status: :internal_server_error
        return
      end

      original_filename = File.basename(store_version['gem_filename'])
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
          result = OpenC3::PluginModel.install_phase1(gem_file_path, existing_variables: @existing_model['variables'], existing_plugin_txt_lines: @existing_model['plugin_txt_lines'], store_plugin_id: params[:store_plugin_id], store_version_id: params[:store_version_id], scope: scope)
        else
          result = OpenC3::PluginModel.install_phase1(gem_file_path, store_plugin_id: params[:store_plugin_id], store_version_id: params[:store_version_id], scope: scope)
        end
        render json: result
      rescue OpenC3::EmptyGemFileError => error
        render json: { status: 'error', message: error.message }, status: :bad_request
        logger.error(error.formatted)
      rescue Exception => error
        render json: { status: 'error', message: error.message }, status: :internal_server_error
        logger.error(error.formatted)
      ensure
        FileUtils.remove_entry_secure(temp_dir, true)
      end
    else
      logger.error("No file received")
      render json: { status: 'error', message: "No file received" }, status: :internal_server_error
    end
  end

  def update
    return unless authorization('admin')
    # Grab the existing plugin we're updating so we can display existing variables
    @existing_model = @model_class.get(name: params[:id], scope: params[:scope])
    create(true)
  end

  # Dry run before an upgrade: returns which modified files differ from the
  # incoming plugin's rendered content so the UI can warn the user that those
  # modifications will be superseded (a new Version History entry is created).
  def modified_diff
    return unless authorization('admin')
    begin
      scope = sanitize_params([:scope])
      return unless scope
      scope = scope[0]
      plugin_hash = JSON.parse(params[:plugin_hash])
      files = OpenC3::PluginModel.modified_diff(plugin_hash, scope: scope)
      render json: { files: files }
    rescue JSON::ParserError => error
      render json: { status: 'error', message: error.message }, status: :bad_request
    rescue Exception => error
      logger.error(error.formatted)
      render json: { status: 'error', message: error.message }, status: :internal_server_error
    end
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
      # Stamp the installing user server-side (never trust a client-supplied
      # username) so Version History can attribute plugin-upgrade versions of
      # modified files. Falls back to writing the body verbatim if it isn't
      # the expected JSON object.
      plugin_hash_body = params[:plugin_hash]
      begin
        parsed = JSON.parse(params[:plugin_hash])
        if parsed.is_a?(Hash)
          parsed['username'] = username()
          plugin_hash_body = JSON.generate(parsed)
        end
      rescue JSON::ParserError
        # leave plugin_hash_body as the original string
      end
      File.open(plugin_hash_file_path, 'wb') do |file|
        file.write(plugin_hash_body)
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
      render json: { status: 'error', message: error.message }, status: :internal_server_error
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
      render json: { status: 'error', message: error.message }, status: :internal_server_error
    end
  end

  # Migrate a legacy plugin from the shared Python venv to a per-plugin UV
  # virtual environment. Spawns `openc3cli migratetouv` as a background process.
  def migrate_to_uv
    return unless authorization('admin')
    begin
      id, scope = sanitize_params([:id, :scope])
      return unless id and scope
      result = OpenC3::ProcessManager.instance.spawn(
        ["ruby", "/openc3/bin/openc3cli", "migratetouv", id, scope],
        "plugin_migrate_to_uv", id, Time.now + 1.hour, scope: scope
      )
      render json: result.name
    rescue Exception => error
      logger.error(error.formatted)
      render json: { status: 'error', message: error.message }, status: :internal_server_error
    end
  end
end
