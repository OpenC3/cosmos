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

require 'openc3/models/tool_model'

class ToolsController < ModelController
  def initialize
    @model_class = OpenC3::ToolModel
  end

  def show
    # No authorization required
    if params[:id].downcase == 'all'
      render json: @model_class.all(scope: params[:scope])
    else
      render json: @model_class.get(name: params[:id], scope: params[:scope])
    end
  end

  # Set the tools position in the list
  # Passed position is an integer index starting with 0 being first in the list
  def position
    return unless authorization('admin')
    @model_class.set_position(name: params[:id], position: params[:position], scope: params[:scope])
    head :ok
  end

  def importmap
    result = Hash.new
    result["imports"] = Hash.new

    tools = @model_class.all_scopes
    inline_tools = {}
    tools.each do |key, tool|
      if tool['import_map_items']
        tool['import_map_items'].each do |item_key, item|
          result["imports"][item_key] = item
        end
      end
      if tool['inline_url']
        result["imports"]["@openc3/tool-#{tool['folder_name']}"] = "/tools/#{tool['folder_name']}/#{tool['inline_url']}"
      end
    end
    render json: result
  end

  def auth
    url = ENV['OPENC3_KEYCLOAK_EXTERNAL_URL']
    unless url
      url = ENV['OPENC3_KEYCLOAK_URL']
      if url == "http://openc3-keycloak:8080"
        # Externally should be just /auth
        url = "/auth"
      end
    end
    realm = ENV['OPENC3_KEYCLOAK_REALM']
    realm = "openc3" unless realm
    render js: "var openc3_keycloak_url = \"#{url}\"; var openc3_keycloak_realm = \"#{realm}\"; var openc3_keycloak_client_id = \"#{ENV['OPENC3_API_CLIENT']}\""
  end
end
