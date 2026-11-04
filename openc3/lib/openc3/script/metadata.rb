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

require 'openc3/script/extract'
require 'time'

module OpenC3
  module Script
    include Extract

    private

    # The metadata methods are deprecated. Define a telemetry packet for metadata
    # and set it with inject_tlm instead. See https://docs.openc3.com/docs/guides/metadata

    # @deprecated Use Data Extractor or Telemetry Grapher on a metadata packet instead.
    #   See https://docs.openc3.com/docs/guides/metadata
    # Gets all the metadata
    #
    # @return The result of the method call.
    def metadata_all(limit: 100, scope: $openc3_scope)
      warn "[DEPRECATION] `metadata_all` is deprecated. Please use Data Extractor or Telemetry Grapher instead."
      response = $api_server.request('get', "/openc3-api/metadata", query: { limit: limit }, scope: scope)
      # Non-existent just returns nil
      return nil if response.nil? || response.status != 200
      return JSON.parse(response.body, allow_nan: true, create_additions: true)
    end
    alias all_metadata metadata_all

    # @deprecated Use tlm or get_tlm_packet on a metadata packet instead.
    #   See https://docs.openc3.com/docs/guides/metadata
    # Gets metadata, default is latest if start is nil
    #
    # @return The result of the method call.
    def metadata_get(start: nil, scope: $openc3_scope)
      warn "[DEPRECATION] `metadata_get` is deprecated. Please use `tlm` or `get_tlm_packet` instead."
      return _metadata_get(start: start, scope: scope)
    end
    alias get_metadata metadata_get

    def _metadata_get(start: nil, scope: $openc3_scope)
      if start
        response = $api_server.request('get', "/openc3-api/metadata/#{start}", scope: scope)
      else
        response = $api_server.request('get', "/openc3-api/metadata/latest", scope: scope)
      end
      # Non-existent just returns nil
      return nil if response.nil? || response.status != 200
      return JSON.parse(response.body, allow_nan: true, create_additions: true)
    end

    # @deprecated Use inject_tlm on a metadata packet instead.
    #   See https://docs.openc3.com/docs/guides/metadata
    # Create a new metadata entry at the given start time or now if no start given
    #
    # @param metadata [Hash<Symbol, Variable>] A hash of metadata
    # @param start [Integer] Metadata time value as integer seconds from epoch
    # @param color [String] Events color to show on Calendar tool, if nil will be blue
    # @return The result of the method call.
    def metadata_set(metadata, start: nil, color: nil, scope: $openc3_scope)
      warn "[DEPRECATION] `metadata_set` is deprecated. Please use `inject_tlm` instead."
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

    # @deprecated Use inject_tlm with only the changed items instead.
    #   See https://docs.openc3.com/docs/guides/metadata
    # Updates existing metadata. If no start is given, updates latest metadata.
    #
    # @param metadata [Hash<Symbol, Variable>] A hash of metadata
    # @param start [Integer] Metadata time value as integer seconds from epoch
    # @param color [String] Events color to show on Calendar tool, if nil will be blue
    # @return The result of the method call.
    def metadata_update(metadata, start: nil, color: nil, scope: $openc3_scope)
      warn "[DEPRECATION] `metadata_update` is deprecated. Please use `inject_tlm` instead."
      unless metadata.is_a?(Hash)
        raise "metadata must be a Hash: #{metadata} is a #{metadata.class}"
      end
      if start.nil? # No start so grab latest
        existing = _metadata_get(scope: scope)
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

    # @deprecated Use the user input methods followed by inject_tlm instead.
    #   See https://docs.openc3.com/docs/guides/metadata
    # Requests the metadata from the user for a target
    def metadata_input(*args, **kwargs)
      warn "[DEPRECATION] `metadata_input` is deprecated. Please use the user input methods followed by `inject_tlm` instead."
      raise StandardError, "can only be used in Script Runner"
    end
    alias input_metadata metadata_input
  end
end
