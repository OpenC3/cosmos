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

require 'openc3/config/meta_config_parser'

class ScriptAutocompleteController < ApplicationController
  CMD_KEYWORDS = %w(cmd cmd_no_range_check cmd_no_hazardous_check cmd_no_checks
                    cmd_raw cmd_raw_no_range_check cmd_raw_no_hazardous_check cmd_raw_no_checks)

  TLM_KEYWORDS = %w(set_tlm override_tlm normalize_tlm tlm
                    limits_enabled? enable_limits disable_limits
                    check check_tolerance wait wait_tolerance wait_check wait_check_tolerance)

  def reserved_item_names
    render json: OpenC3::Packet::RESERVED_ITEM_NAMES
  end

  def keywords
    keywords = case params[:type].upcase
    when 'CMD'
      CMD_KEYWORDS
    when 'TLM'
      TLM_KEYWORDS
    when 'SCREEN'
      screen_keywords()
    else
      []
    end
    render json: keywords
  end

  def ace_autocomplete_data
    return unless authorization('system')
    autocomplete_data = build_autocomplete_data(params[:type], params[:scope])
    response.headers['Cache-Control'] = 'must-revalidate' # TODO: Browser is ignoring this and not caching anything for some reason. Future enhancement
    render json: autocomplete_data
  end

  # private

  def screen_keywords
    keywords = []
    yaml = OpenC3::MetaConfigParser.load(File.join(OpenC3::PATH, 'data', 'config', 'screen.yaml'))
    yaml.each do |keyword, data|
      if data['collection']
        keywords.concat(data['collection'].keys)
      end
      if keyword == keyword.upcase
        keywords << keyword
      end
    end
    keywords
  end

  def build_autocomplete_data(type, scope)
    targets = OpenC3::TargetModel.all(scope: scope)
    @target_names = targets.keys
    autocomplete_data = []
    if type.upcase == 'SCREEN'
      yaml = OpenC3::MetaConfigParser.load(File.join(OpenC3::PATH, 'data', 'config', 'screen.yaml'))
      yaml.each do |keyword, data|
        if data['collection']
          data['collection'].each do |keyword, data|
            screen_to_autocomplete_hash(autocomplete_data, keyword, data)
          end
        end
        if keyword == keyword.upcase
          screen_to_autocomplete_hash(autocomplete_data, keyword, data)
        end
      end
    else
      targets.each do |target_name, target_info|
        OpenC3::TargetModel.packets(target_name, type: type.upcase.intern, scope: scope).each do |packet|
          packet_to_autocomplete_hashes(autocomplete_data, packet, target_info, type)
        end
      end
      autocomplete_data.sort_by { |packet| packet[:caption] }
    end
    autocomplete_data
  end

  def screen_to_autocomplete_hash(autocomplete_data, keyword, data)
    # The snippet is what gets put in the file when you autocomplete
    # Thus we put the keyword with all the parameters surround by <>
    # e.g. SCREEN <Width> <Height> <Polling Period>
    # Example of building snippets:
    # https://github.com/ajaxorg/ace/blob/23c3c6067ed55518b4560214f35b5f03378c441a/src/snippets_test.js
    snippet = keyword.dup

    tpi = false
    params = []
    if data['parameters']
      data['parameters'].each_with_index do |param, index|
        # map to Ace autocomplete data syntax to allow tabbing through items: "${position:defaultValue}"
        if param['values'].is_a? Array
          snippet << " ${#{index + 1}|#{param['values'].join(',')}|}"
          params << param['values'].to_h { |value| ["#{value}", param['description']] }
        else
          if param['required']
            snippet << " ${#{index + 1}:#{param['name']}}"
            params << { "#{param['name']}": param['description'] }
          else
            snippet << " ${#{index + 1}:<#{param['name']}>}"
            params << { "<#{param['name']}>": param['description'] }
          end

          # Look for "Target name" which always has "Packet name" and "Item name" following
          # If so we set tpi to true which means this is going to use params not snippets
          tpi = true if param['name'] == "Target name"
        end
      end
      # Automatically add all the settings so they're aware ... they can delete later
      if data['settings']
        data['settings'].each do |key, value|
          if value['parameters']
            snippet << ("\n  SETTING #{key} " +
              value['parameters'].map {|param| "<#{param['name']}>" }.join(' '))
          else
            snippet << "\n  SETTING #{key}"
          end
        end
      end
    elsif data['collection']
      # Create option drop down list
      snippet << " ${1|#{data['collection'].keys.join(',')}|}"
    end
    if tpi
      # This structure is totally dependent on the ACE editor snippet structure
      # In this case we do autocomplete over the various parameters
      # See screenCompleter.js for usage
      autocomplete_data <<
        {
          caption: keyword,
          meta: data['summary'],
          value: "#{keyword} ",
          command: 'startAutocomplete',
          params: params
        }
    else
      # This structure is totally dependent on the ACE editor snippet structure
      # In this case we insert the snippet rather than autocomplete the parameters
      # See screenCompleter.js for usage
      autocomplete_data <<
        {
          caption: keyword,
          meta: data['summary'],
          snippet: snippet,
        }
    end
  end
  # caption: 'LABELVALUE',
  # meta: 'Displays a LABEL with the item name followed by a VALUE',
  # value: 'LABELVALUE ',
  # command: 'startAutocomplete',
  # params: [
  #   { '<Target Name>': 1 },
  #   { '<Packet Name>': 1 },
  #   { '<Item Name>': 1 },
  #   { RAW: 1, CONVERTED: 1, FORMATTED: 1, WITH_UNITS: 1 },
  #   { '<Number of characters>': 1 },
  # ],

  def target_packet_name(packet)
    "#{packet['target_name']} #{packet['packet_name']}"
  end

  def packet_to_autocomplete_hashes(autocomplete_data, packet, target_info, type)
    if type.upcase == 'TLM'
      packet['items'].each do |item|
        autocomplete_data <<
          {
            :caption => "#{target_packet_name(packet)} #{item['name']}",
            :snippet => "#{target_packet_name(packet)} #{item['name']}",
            :meta => 'telemetry',
          }
      end
    else
      # There's only one autocomplete option for each command packet
      autocomplete_data <<
        {
          :caption => target_packet_name(packet),
          :snippet => build_cmd_snippet(packet, target_info),
          :meta => 'command',
        }
    end
  end

  # Example of building snippets:
  # https://github.com/ajaxorg/ace/blob/23c3c6067ed55518b4560214f35b5f03378c441a/src/snippets_test.js
  def build_cmd_snippet(packet, target_info)
    snippet = target_packet_name(packet)
    filtered_items = packet['items'].select do |item|
      !OpenC3::Packet::RESERVED_ITEM_NAMES.include?(item['name']) and !target_info['ignored_parameters'].include?(item['name'])
    end
    if filtered_items.any?
      params = filtered_items.each_with_index.map do |item, index|
        if item['data_type'] == 'BLOCK'
          # Unpack binary data to uppercase hex string
          default = "0x#{item['default'].unpack('H*').first.upcase}"
        elsif item['data_type'] == 'STRING'
          default = "'#{item['default']}'" || ''
        else
          default = item['default'] || 0
        end
        if item.key? 'states'
          default_state = item['states'].find { |_key, val| val['value'] == default }
          default = default_state[0] if default_state
        end
        # map to Ace autocomplete data syntax to allow tabbing through items: "staticText ${position:defaultValue}"
        "#{item['name']} ${#{index + 1}:#{default}}"
      end
      return "#{snippet} with #{params.join(', ')}"
    end
    snippet
  end
end
