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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/script/extract'
require 'time'

module OpenC3
  module Script
    include Extract

    private

    def stash_set(key, value, scope: $openc3_scope)
      response = $api_server.request('post', '/openc3-api/stash', data: { key: key, value: value }, json: true, scope: scope)
      if response.nil? || response.code != 201
        raise "Failed to set stash"
      end
      return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
    end

    def stash_keys(scope: $openc3_scope)
      response = $api_server.request('get', "/openc3-api/stash_keys", scope: scope)
      if response.nil? || response.code != 201
        raise "Failed to get stash"
      end
      return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
    end

    def stash_get(key, scope: $openc3_scope)
      response = $api_server.request('get', "/openc3-api/stash/#{key}", scope: scope)
      if response.nil? || response.code != 201
        raise "Failed to get stash"
      end
      return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
    end

    def stash_all(scope: $openc3_scope)
      response = $api_server.request('get', "/openc3-api/stash", scope: scope)
      if response.nil? || response.code != 201
        raise "Failed to get stash"
      end
      return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
    end

    def stash_delete(scope: $openc3_scope)
      response = $api_server.request('get', "/openc3-api/stash", scope: scope)
      if response.nil? || response.code != 201
        raise "Failed to get stash"
      end
      return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
    end
  end
end
