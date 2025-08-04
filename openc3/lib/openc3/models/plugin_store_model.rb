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

require 'openc3/models/model'
require 'openc3/utilities/store'

module OpenC3
  class PluginStoreModel < Model
    PRIMARY_KEY = 'openc3_plugin_store'

    def self.set(plugin_store_data)
      Store.set(PRIMARY_KEY, plugin_store_data)
    end

    def self.all()
      Store.get(PRIMARY_KEY)
    end

    def self.plugin_store_error(message)
      Store.set(PRIMARY_KEY, [{
        date: Time.now.utc.iso8601,
        title: 'Plugin Store Error',
        body: message,
        error: true,
      }].to_json)
    end

    def self.get_by_id(id)
      plugins = JSON.parse(all()) rescue []
      plugins.find { |plugin| plugin["id"] == Integer(id) }
    end

    def self.update
      setting = SettingModel.get(name: 'store_url', scope: 'DEFAULT')
      store_url = setting['data'] if setting
      store_url = 'https://store.openc3.com' if store_url.nil? or store_url.strip.empty?
      conn = Faraday.new(
        url: store_url,
      )
      response = conn.get('/cosmos_plugins/json')
      if response.success?
        self.set(response.body)
      else
        self.plugin_store_error("Error contacting plugin store at #{store_url} (status: #{response.status})")
      end
    rescue Exception => e
      self.plugin_store_error("Error contacting plugin store at #{store_url}. #{e.message})")
    end

    def self.ensure_exists
      plugins = self.all()
      self.update() if plugins.nil? or plugins.length.zero? or plugins[0]['error']
    end
  end
end
