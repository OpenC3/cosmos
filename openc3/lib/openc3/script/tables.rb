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

module OpenC3
  module Script
    private

    def table_create_binary(definition, scope: $openc3_scope)
      post_data = {}
      post_data['definition'] = definition
      response = $api_server.request('post', '/openc3-api/tables/generate', json: true, data: post_data, scope: scope)
      return _tables_handle_response(response, 'Failed to create binary')
    end

    def table_create_report(filename, definition, table_name: nil, scope: $openc3_scope)
      post_data = {}
      post_data['binary'] = filename
      post_data['definition'] = definition
      post_data['table_name'] = table_name if table_name
      response = $api_server.request('post', '/openc3-api/tables/report', json: true, data: post_data, scope: scope)
      return _tables_handle_response(response, 'Failed to create report')
    end

    # Helper method to handle the response
    def _tables_handle_response(response, error_message)
      return nil if response.nil?
      if response.status >= 400
        result = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
        raise "#{error_message} due to #{result['message']}"
      end
      return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
    end
  end
end
