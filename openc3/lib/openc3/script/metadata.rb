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

    # Gets all the metadata
    #
    # @return The result of the method call.
    def metadata_all(limit: 100, scope: $openc3_scope)
      response = $api_server.request('get', "/openc3-api/metadata", query: { limit: limit }, scope: scope)
      # Non-existent just returns nil
      return nil if response.nil? || response.status != 200
      return JSON.parse(response.body, allow_nan: true, create_additions: true)
    end
    alias all_metadata metadata_all

    # Gets metadata, default is latest if start is nil
    #
    # @return The result of the method call.
    def metadata_get(start: nil, scope: $openc3_scope)
      if start
        response = $api_server.request('get', "/openc3-api/metadata/#{start}", scope: scope)
      else
        response = $api_server.request('get', "/openc3-api/metadata/latest", scope: scope)
      end
      # Non-existent just returns nil
      return nil if response.nil? || response.status != 200
      return JSON.parse(response.body, allow_nan: true, create_additions: true)
    end
    alias get_metadata metadata_get

    # Create a new metadata entry at the given start time or now if no start given
    #
    # @param metadata [Hash<Symbol, Variable>] A hash of metadata
    # @param start [Integer] Metadata time value as integer seconds from epoch
    # @param color [String] Events color to show on Calendar tool, if nil will be blue
    # @return The result of the method call.
    def metadata_set(metadata, start: nil, color: nil, scope: $openc3_scope)
      unless metadata.is_a?(Hash)
        raise "metadata must be a Hash: #{metadata} is a #{metadata.class}"
      end
      color = '#003784' unless color
      data = { color: color, metadata: metadata }
      data[:start] = start.iso8601 unless start.nil?
      response = $api_server.request('post', '/openc3-api/metadata', data: data, json: true, scope: scope)
      if response.nil?
        raise "Failed to set metadata due to #{response.status}"
      elsif response.status == 409
        raise "Metadata overlaps existing metadata. Did you metadata_set within 1s of another?"
      elsif response.status != 201
        raise "Failed to set metadata due to #{response.status}"
      end
      return JSON.parse(response.body, allow_nan: true, create_additions: true)
    end
    alias set_metadata metadata_set

    # Updates existing metadata. If no start is given, updates latest metadata.
    #
    # @param metadata [Hash<Symbol, Variable>] A hash of metadata
    # @param start [Integer] Metadata time value as integer seconds from epoch
    # @param color [String] Events color to show on Calendar tool, if nil will be blue
    # @return The result of the method call.
    def metadata_update(metadata, start: nil, color: nil, scope: $openc3_scope)
      unless metadata.is_a?(Hash)
        raise "metadata must be a Hash: #{metadata} is a #{metadata.class}"
      end
      if start.nil? # No start so grab latest
        existing = get_metadata()
        start = existing['start']
        color = existing['color'] unless color
        metadata = existing['metadata'].merge(metadata)
      else
        color = '#003784' unless color
      end
      data = { :color => color, :metadata => metadata }
      data[:start] = Time.at(start).iso8601
      response = $api_server.request('put', "/openc3-api/metadata/#{start}", data: data, json: true, scope: scope)
      if response.nil? || response.status != 200
        raise "Failed to update metadata"
      end
      return JSON.parse(response.body, allow_nan: true, create_additions: true)
    end
    alias update_metadata metadata_update

    # Requests the metadata from the user for a target
    def metadata_input(*args, **kwargs)
      raise StandardError "can only be used in Script Runner"
    end
    alias input_metadata metadata_input
  end
end
