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
        body: message
      }].to_json)
    end

    def self.get_by_id(id)
      plugins = JSON.parse(all()) rescue []
      plugins.find { |plugin| plugin["id"] == Integer(id) }
    end
  end
end
