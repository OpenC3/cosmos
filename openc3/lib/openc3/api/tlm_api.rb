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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1963
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1957

require 'openc3/models/target_model'
require 'openc3/models/cvt_model'
require 'openc3/packets/packet'
require 'openc3/topics/telemetry_topic'
require 'openc3/topics/interface_topic'
require 'openc3/topics/decom_interface_topic'

module OpenC3
  module Api
    WHITELIST ||= []
    WHITELIST.concat([
                       'tlm',
                       'tlm_raw',
                       'tlm_formatted',
                       'tlm_with_units',
                       'tlm_variable', # DEPRECATED
                       'set_tlm',
                       'inject_tlm',
                       'override_tlm',
                       'get_overrides',
                       'normalize_tlm',
                       'get_tlm_buffer',
                       'get_tlm_packet',
                       'get_tlm_available',
                       'get_tlm_values',
                       'get_all_tlm',
                       'get_all_telemetry', # DEPRECATED
                       'get_all_tlm_names',
                       'get_all_telemetry_names', # DEPRECATED
                       'get_all_tlm_item_names',
                       'get_tlm',
                       'get_telemetry', # DEPRECATED
                       'get_item',
                       'subscribe_packets',
                       'get_packets',
                       'get_tlm_cnt',
                       'get_tlm_cnts',
                       'get_packet_derived_items',
                     ])

    # Request a telemetry item from a packet.
    #
    # Accepts two different calling styles:
    #   tlm("TGT PKT ITEM")
    #   tlm('TGT','PKT','ITEM')
    #
    # Favor the first syntax where possible as it is more succinct.
    #
    # @param args [String|Array<String>] See the description for calling style
    # @param type [Symbol] Telemetry type, :RAW, :CONVERTED (default), :FORMATTED, or :WITH_UNITS
    # @return [Object] The telemetry value formatted as requested
    def tlm(*args, type: :CONVERTED, cache_timeout: nil, manual: false, scope: $openc3_scope, token: $openc3_token)
      target_name, packet_name, item_name = _tlm_process_args(args, 'tlm', cache_timeout: cache_timeout, scope: scope)
      authorize(permission: 'tlm', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
      CvtModel.get_item(target_name, packet_name, item_name, type: type.intern, cache_timeout: cache_timeout, scope: scope)
    end

    def tlm_raw(*args, cache_timeout: nil, manual: false, scope: $openc3_scope, token: $openc3_token)
      tlm(*args, type: :RAW, cache_timeout: cache_timeout, manual: manual, scope: scope, token: token)
    end

    def tlm_formatted(*args, cache_timeout: nil, manual: false, scope: $openc3_scope, token: $openc3_token)
      tlm(*args, type: :FORMATTED, cache_timeout: cache_timeout, manual: manual, scope: scope, token: token)
    end

    def tlm_with_units(*args, cache_timeout: nil, manual: false, scope: $openc3_scope, token: $openc3_token)
      tlm(*args, type: :WITH_UNITS, cache_timeout: cache_timeout, manual: manual, scope: scope, token: token)
    end

    # @deprecated Use tlm with type:
    def tlm_variable(*args, cache_timeout: nil, manual: false, scope: $openc3_scope, token: $openc3_token)
      tlm(*args[0..-2], type: args[-1].intern, cache_timeout: cache_timeout, manual: manual, scope: scope, token: token)
    end

    # Set a telemetry item in the current value table.
    #
    # Note: If this is done while OpenC3 is currently receiving telemetry,
    # this value could get overwritten at any time. Thus this capability is
    # best used for testing or for telemetry items that are not received
    # regularly through the target interface.
    #
    # Accepts two different calling styles:
    #   set_tlm("TGT PKT ITEM = 1.0")
    #   set_tlm('TGT','PKT','ITEM', 10.0)
    #
    # Favor the first syntax where possible as it is more succinct.
    #
    # @param args [String|Array<String>] See the description for calling style
    # @param type [Symbol] Telemetry type, :RAW, :CONVERTED (default), :FORMATTED, or :WITH_UNITS
    def set_tlm(*args, type: :CONVERTED, manual: false, cache_timeout: nil, scope: $openc3_scope, token: $openc3_token)
      target_name, packet_name, item_name, value = _set_tlm_process_args(args, __method__, cache_timeout: cache_timeout, scope: scope)
      authorize(permission: 'tlm_set', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
      CvtModel.set_item(target_name, packet_name, item_name, value, type: type.intern, scope: scope)
    end

    # Injects a packet into the system as if it was received from an interface
    #
    # @param target_name [String] Target name of the packet
    # @param packet_name [String] Packet name of the packet
    # @param item_hash [Hash] Hash of item_name and value for each item you want to change from the current value table
    # @param type [Symbol] Telemetry type, :RAW, :CONVERTED (default), :FORMATTED, or :WITH_UNITS
    def inject_tlm(target_name, packet_name, item_hash = nil, type: :CONVERTED, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'tlm_set', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
      type = type.to_s.intern
      target_name = target_name.upcase
      packet_name = packet_name.upcase
      unless CvtModel::VALUE_TYPES.include?(type)
        raise "Unknown type '#{type}' for #{target_name} #{packet_name}"
      end

      if item_hash
        item_hash = item_hash.transform_keys(&:upcase)
        # Check that the items exist ... exceptions are raised if not
        items = TargetModel.packet_items(target_name, packet_name, item_hash.keys, scope: scope)
        if type == :CONVERTED
          # If the type is converted, check that the item states are valid
          item_hash.each do |item_name, item_value|
            item = items.find { |i| i['name'] == item_name.to_s.upcase }
            if item['states'] && !item['states'][item_value]
              raise "Unknown state '#{item_value}' for #{item['name']}, must be one of #{item['states'].keys.join(', ')}"
            end
          end
        end
      else
        # Check that the packet exists ... exceptions are raised if not
        TargetModel.packet(target_name, packet_name, scope: scope)
      end

      # See if this target has a tlm interface
      interface_name = nil
      InterfaceModel.all(scope: scope).each do |_name, interface|
        if interface['tlm_target_names'].include? target_name
          interface_name = interface['name']
          break
        end
      end

      # Use an interface microservice if it exists, other use the decom microservice
      if interface_name
        InterfaceTopic.inject_tlm(interface_name, target_name, packet_name, item_hash, type: type, scope: scope)
      else
        DecomInterfaceTopic.inject_tlm(target_name, packet_name, item_hash, type: type, scope: scope)
      end
    end

    # Override the current value table such that a particular item always
    # returns the same value (for a given type) even when new telemetry
    # packets are received from the target.
    #
    # Accepts two different calling styles:
    #   override_tlm("TGT PKT ITEM = 1.0")
    #   override_tlm('TGT','PKT','ITEM', 10.0)
    #
    # Favor the first syntax where possible as it is more succinct.
    #
    # @param args The args must either be a string followed by a value or
    #   three strings followed by a value (see the calling style in the
    #   description).
    # @param type [Symbol] Telemetry type, :ALL (default), :RAW, :CONVERTED, :FORMATTED, :WITH_UNITS
    def override_tlm(*args, type: :ALL, manual: false, scope: $openc3_scope, token: $openc3_token)
      target_name, packet_name, item_name, value = _set_tlm_process_args(args, __method__, scope: scope)
      authorize(permission: 'tlm_set', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
      CvtModel.override(target_name, packet_name, item_name, value, type: type.intern, scope: scope)
    end

    # Get the list of CVT overrides
    def get_overrides(manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'tlm', manual: manual, scope: scope, token: token)
      CvtModel.overrides(scope: scope)
    end

    # Normalize a telemetry item in a packet to its default behavior. Called
    # after override_tlm to restore standard processing.
    #
    # Accepts two different calling styles:
    #   normalize_tlm("TGT PKT ITEM")
    #   normalize_tlm('TGT','PKT','ITEM')
    #
    # Favor the first syntax where possible as it is more succinct.
    #
    # @param args The args must either be a string or three strings
    #   (see the calling style in the description).
    # @param type [Symbol] Telemetry type, :ALL (default), :RAW, :CONVERTED, :FORMATTED, :WITH_UNITS
    #   Also takes :ALL which means to normalize all telemetry types
    def normalize_tlm(*args, type: :ALL, manual: false, scope: $openc3_scope, token: $openc3_token)
      target_name, packet_name, item_name = _tlm_process_args(args, __method__, scope: scope)
      authorize(permission: 'tlm_set', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
      CvtModel.normalize(target_name, packet_name, item_name, type: type.intern, scope: scope)
    end

    # Returns the raw buffer for a telemetry packet.
    #
    # @param target_name [String] Name of the target
    # @param packet_name [String] Name of the packet
    # @return [Hash] telemetry hash with last telemetry buffer
    def get_tlm_buffer(*args, manual: false, scope: $openc3_scope, token: $openc3_token)
      target_name, packet_name = _extract_target_packet_names('get_tlm_buffer', *args)
      authorize(permission: 'tlm', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
      TargetModel.packet(target_name, packet_name, scope: scope)
      topic = "#{scope}__TELEMETRY__{#{target_name}}__#{packet_name}"
      msg_id, msg_hash = Topic.get_newest_message(topic)
      if msg_id
        msg_hash['buffer'] = msg_hash['buffer'].b
        return msg_hash
      end
      return nil
    end

    # Returns all the values (along with their limits state) for a packet.
    #
    # @param target_name [String] Name of the target
    # @param packet_name [String] Name of the packet
    # @param stale_time [Integer] Time in seconds from Time.now that packet will be marked stale
    # @param type [Symbol] Types returned, :RAW, :CONVERTED (default), :FORMATTED, or :WITH_UNITS
    # @return [Array<String, Object, Symbol|nil>] Returns an Array consisting
    #   of [item name, item value, item limits state] where the item limits
    #   state can be one of {OpenC3::Limits::LIMITS_STATES}
    def get_tlm_packet(*args, stale_time: 30, type: :CONVERTED, cache_timeout: nil, manual: false, scope: $openc3_scope, token: $openc3_token)
      target_name, packet_name = _extract_target_packet_names('get_tlm_packet', *args)
      authorize(permission: 'tlm', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
      packet = TargetModel.packet(target_name, packet_name, scope: scope)
      t = _validate_tlm_type(type)
      raise ArgumentError, "Unknown type '#{type}' for #{target_name} #{packet_name}" if t.nil?
      items = packet['items'].map { | item | item['name'].upcase }
      cvt_items = items.map { | item | [target_name, packet_name, item, type] }
      current_values = CvtModel.get_tlm_values(cvt_items, stale_time: stale_time, cache_timeout: cache_timeout, scope: scope)
      items.zip(current_values).map { | item , values | [item, values[0], values[1]]}
    end

    # Returns the available items from a list of requested screen items
    # This does the packet introspection to determine what is actually available
    # Like if you ask for WITH_UNITS but only RAW is available
    def get_tlm_available(items, manual: false, scope: $openc3_scope, token: $openc3_token)
      results = []
      items.each do |item|
        item_upcase = item.to_s.upcase
        target_name, orig_packet_name, item_name, value_type = item_upcase.split('__')
        packet_name = orig_packet_name
        raise ArgumentError, "items must be formatted as TGT__PKT__ITEM__TYPE" if target_name.nil? || packet_name.nil? || item_name.nil? || value_type.nil?
        if orig_packet_name == 'LATEST'
          # TODO: Do we need to lookup ALL the possible packets for this item?
          # We can have a large cache_timeout of 1 because all we're trying to do is lookup a packet
          packet_name = CvtModel.determine_latest_packet_for_item(target_name, item_name, cache_timeout: 1, scope: scope)
        end
        authorize(permission: 'tlm', target_name: target_name, packet_name: packet_name, scope: scope, token: token)
        begin
          item = TargetModel.packet_item(target_name, packet_name, item_name, scope: scope)
          if Packet::RESERVED_ITEM_NAMES.include?(item_name)
            value_type = 'RAW' # Must request the raw value when dealing with the reserved items
          end

          # QuestDB 9.0.0 only supports DOUBLE arrays: https://questdb.com/docs/concept/array/
          if item['array_size']
            # TODO: This needs work ... we're JSON encoding non numeric array values
            if item['data_type'] == 'STRING' or item['data_type'] == 'BLOCK'
              results << nil
              next
            end
            value_type = 'RAW'
          end

          case value_type
          when 'WITH_UNITS'
            if item['units']
              results << [target_name, orig_packet_name, item_name, 'WITH_UNITS'].join('__')
            elsif item['format_string']
              results << [target_name, orig_packet_name, item_name, 'FORMATTED'].join('__')
            elsif item['read_conversion'] or item['states']
              results << [target_name, orig_packet_name, item_name, 'CONVERTED'].join('__')
            else
              results << [target_name, orig_packet_name, item_name, 'RAW'].join('__')
            end
          when 'FORMATTED'
            if item['format_string']
              results << [target_name, orig_packet_name, item_name, 'FORMATTED'].join('__')
            elsif item['read_conversion'] or item['states']
              results << [target_name, orig_packet_name, item_name, 'CONVERTED'].join('__')
            else
              results << [target_name, orig_packet_name, item_name, 'RAW'].join('__')
            end
          when 'CONVERTED'
            if item['read_conversion'] or item['states']
              results << [target_name, orig_packet_name, item_name, 'CONVERTED'].join('__')
            else
              results << [target_name, orig_packet_name, item_name, 'RAW'].join('__')
            end
          else # RAW or unknown
            results << [target_name, orig_packet_name, item_name, 'RAW'].join('__')
          end

          # Tack on __LIMITS to notify that we have an available limits value
          if item['limits']['DEFAULT']
            results[-1] += '__LIMITS'
          end
        rescue RuntimeError => e
          results << nil
        end
      end
      results
    end

    # Returns all the item values (along with their limits state). The items
    # can be from any target and packet and thus must be fully qualified with
    # their target and packet names.
    #
    # @since 5.0.0
    # @param items [Array<String>] Array of items consisting of 'tgt__pkt__item__type'
    # @param stale_time [Integer] Time in seconds from Time.now that data will be marked stale
    # @return [Array<Object, Symbol>]
    #   Array consisting of the item value and limits state
    #   given as symbols such as :RED, :YELLOW, :STALE
    def get_tlm_values(items, stale_time: 30, cache_timeout: nil, manual: false, start_time: nil, end_time: nil, scope: $openc3_scope, token: $openc3_token)
      if !items.is_a?(Array)
        raise ArgumentError, "items must be array of strings: ['TGT__PKT__ITEM__TYPE', ...]"
      end
      packets = []
      cvt_items = []
      items.each_with_index do |item, index|
        if item.nil?
          # null items mean that it doesn't exist
          cvt_items[index] = nil
        else
          item_upcase = item.to_s.upcase
          target_name, packet_name, item_name, value_type, limits = item_upcase.split('__')
          raise ArgumentError, "items must be formatted as TGT__PKT__ITEM__TYPE" if target_name.nil? || packet_name.nil? || item_name.nil? || value_type.nil?
          if packet_name == 'LATEST' # Lookup packet_name in case of LATEST
            packet_name = CvtModel.determine_latest_packet_for_item(target_name, item_name, cache_timeout: cache_timeout, scope: scope)
          end
        end
        cvt_items[index] = [target_name, packet_name, item_name, value_type, limits]
        packets << [target_name, packet_name]
      end
      packets.uniq!
      packets.each do |target_name, packet_name|
        authorize(permission: 'tlm', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
      end
      CvtModel.get_tlm_values(cvt_items, stale_time: stale_time, cache_timeout: cache_timeout, start_time: start_time, end_time: end_time, scope: scope)
    end

    # Returns an array of all the telemetry packet hashes
    #
    # @since 5.0.0
    # @param target_name [String] Name of the target
    # @return [Array<Hash>] Array of all telemetry packet hashes
    def get_all_tlm(target_name, manual: false, scope: $openc3_scope, token: $openc3_token)
      target_name = target_name.upcase
      authorize(permission: 'tlm', target_name: target_name, manual: manual, scope: scope, token: token)
      TargetModel.packets(target_name, type: :TLM, scope: scope)
    end
    alias get_all_telemetry get_all_tlm

    # Returns an array of all the telemetry packet names
    #
    # @since 5.0.6
    # @param target_name [String] Name of the target
    # @return [Array<String>] Array of all telemetry packet names
    def get_all_tlm_names(target_name, hidden: false, manual: false, scope: $openc3_scope, token: $openc3_token)
      begin
        packets = get_all_tlm(target_name, manual: manual, scope: scope, token: token)
      rescue RuntimeError
        packets = []
      end
      names = []
      packets.each do |packet|
        if hidden
          names << packet['packet_name']
        else
          names << packet['packet_name'] unless packet['hidden']
        end
      end
      return names
    end
    alias get_all_telemetry_names get_all_tlm_names

    # Returns an array of all the item names for every packet in a target
    #
    # @param target_name [String] Name of the taret
    # @return [Array<String>] Array of all telemetry item names
    def get_all_tlm_item_names(target_name, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'tlm', target_name: target_name, manual: manual, scope: scope, token: token)
      begin
        items = TargetModel.all_item_names(target_name, scope: scope)
      rescue RuntimeError
        items = []
      end
      return items
    end

    # Returns a telemetry packet hash
    #
    # @since 5.0.0
    # @param target_name [String] Name of the target
    # @param packet_name [String] Name of the packet
    # @return [Hash] Telemetry packet hash
    def get_tlm(*args, manual: false, scope: $openc3_scope, token: $openc3_token)
      target_name, packet_name = _extract_target_packet_names('get_tlm', *args)
      authorize(permission: 'tlm', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
      TargetModel.packet(target_name, packet_name, scope: scope)
    end
    alias get_telemetry get_tlm

    # Returns a telemetry packet item hash
    #
    # @since 5.0.0
    # @param target_name [String] Name of the target
    # @param packet_name [String] Name of the packet
    # @param item_name [String] Name of the packet
    # @return [Hash] Telemetry packet item hash
    def get_item(*args, manual: false, scope: $openc3_scope, token: $openc3_token)
      target_name, packet_name, item_name = _extract_target_packet_item_names('get_item', *args)
      authorize(permission: 'tlm', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
      TargetModel.packet_item(target_name, packet_name, item_name, scope: scope)
    end

    # 2x double underscore since __ is reserved
    SUBSCRIPTION_DELIMITER = '____'

    # Subscribe to a list of packets. An ID is returned which is passed to
    # get_packets(id) to return packets.
    #
    # @param packets [Array<Array<String, String>>] Array of arrays consisting of target name, packet name
    # @return [String] ID which should be passed to get_packets
    def subscribe_packets(packets, manual: false, scope: $openc3_scope, token: $openc3_token)
      if !packets.is_a?(Array) || !packets[0].is_a?(Array)
        raise ArgumentError, "packets must be nested array: [['TGT','PKT'],...]"
      end

      results = {}
      packets.each do |target_name, packet_name|
        target_name = target_name.upcase
        packet_name = packet_name.upcase
        authorize(permission: 'tlm', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
        topic = "#{scope}__DECOM__{#{target_name}}__#{packet_name}"
        id, _ = Topic.get_newest_message(topic)
        results[topic] = id ? id : '0-0'
      end
      results.to_a.join(SUBSCRIPTION_DELIMITER)
    end
    # Alias the singular as well since that matches COSMOS 4
    alias subscribe_packet subscribe_packets

    # Get packets based on ID returned from subscribe_packet.
    # @param id [String] ID returned from subscribe_packets or last call to get_packets
    # @param block [Integer] Unused - Blocking must be implemented at the client
    # @param count [Integer] Maximum number of packets to return from EACH packet stream
    # @return [Array<String, Array<Hash>] Array of the ID and array of all packets found
    def get_packets(id, block: nil, count: 1000, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'tlm', manual: manual, scope: scope, token: token)
      # Split the list of topic, ID values and turn it into a hash for easy updates
      lookup = Hash[*id.split(SUBSCRIPTION_DELIMITER)]
      xread = Topic.read_topics(lookup.keys, lookup.values, nil, count) # Always don't block
      # Return the original ID and and empty array if we didn't get anything
      packets = []
      return [id, packets] if xread.empty?
      xread.each do |topic, data|
        data.each do |id, msg_hash|
          lookup[topic] = id # save the new ID
          json_hash = JSON.parse(msg_hash['json_data'], :allow_nan => true, :create_additions => true)
          msg_hash.delete('json_data')
          packets << msg_hash.merge(json_hash)
        end
      end
      return lookup.to_a.join(SUBSCRIPTION_DELIMITER), packets
    end

    # Get the receive count for a telemetry packet
    #
    # @param target_name [String] Name of the target
    # @param packet_name [String] Name of the packet
    # @return [Numeric] Receive count for the telemetry packet
    def get_tlm_cnt(*args, manual: false, scope: $openc3_scope, token: $openc3_token)
      target_name, packet_name = _extract_target_packet_names('get_tlm_cnt', *args)
      authorize(permission: 'system', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
      TargetModel.packet(target_name, packet_name, scope: scope)
      return TargetModel.get_telemetry_count(target_name, packet_name, scope: scope)
    end

    # Get the transmit counts for telemetry packets
    #
    # @param target_packets [Array<Array<String, String>>] Array of arrays containing target_name, packet_name
    # @return [Array<Numeric>] Receive count for the telemetry packets
    def get_tlm_cnts(target_packets, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', manual: manual, scope: scope, token: token)
      return TargetModel.get_telemetry_counts(target_packets, scope: scope)
    end

    # Get the list of derived telemetry items for a packet
    #
    # @param target_name [String] Target name
    # @param packet_name [String] Packet name
    # @return [Array<String>] All of the ignored telemetry items for a packet.
    def get_packet_derived_items(*args, manual: false, scope: $openc3_scope, token: $openc3_token)
      target_name, packet_name = _extract_target_packet_names('get_packet_derived_items', *args)
      authorize(permission: 'tlm', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
      packet = TargetModel.packet(target_name, packet_name, scope: scope)
      return packet['items'].select { |item| item['data_type'] == 'DERIVED' }.map { |item| item['name'] }
    end

    # PRIVATE

    def _extract_target_packet_names(method_name, *args)
      target_name = nil
      packet_name = nil
      case args.length
      when 1
        target_name, packet_name = args[0].upcase.split
      when 2
        target_name = args[0].upcase
        packet_name = args[1].upcase
      else
        # Invalid number of arguments
        raise "ERROR: Invalid number of arguments (#{args.length}) passed to #{method_name}()"
      end
      if target_name.nil? or packet_name.nil?
        raise "ERROR: Both target name and packet name required. Usage: #{method_name}(\"TGT PKT\") or #{method_name}(\"TGT\", \"PKT\")"
      end
      return [target_name, packet_name]
    end

    def _extract_target_packet_item_names(method_name, *args)
      target_name = nil
      packet_name = nil
      item_name = nil
      case args.length
      when 1
        target_name, packet_name, item_name = args[0].upcase.split
      when 3
        target_name = args[0].upcase
        packet_name = args[1].upcase
        item_name = args[2].upcase
      else
        # Invalid number of arguments
        raise "ERROR: Invalid number of arguments (#{args.length}) passed to #{method_name}()"
      end
      if target_name.nil? or packet_name.nil? or item_name.nil?
        raise "ERROR: Target name, packet name and item name are required. Usage: #{method_name}(\"TGT PKT ITEM\") or #{method_name}(\"TGT\", \"PKT\", \"ITEM\")"
      end
      return [target_name, packet_name, item_name]
    end

    def _validate_tlm_type(type)
      case type.intern
      when :RAW
        return ''
      when :CONVERTED
        return 'C'
      when :FORMATTED
        return 'F'
      when :WITH_UNITS
        return 'U'
      else
        return nil
      end
    end

    def _tlm_process_args(args, method_name, cache_timeout: nil, scope: $openc3_scope, token: $openc3_token)
      case args.length
      when 1
        target_name, packet_name, item_name = extract_fields_from_tlm_text(args[0])
      when 3
        target_name = args[0]
        packet_name = args[1]
        item_name = args[2]
      else
        # Invalid number of arguments
        raise "ERROR: Invalid number of arguments (#{args.length}) passed to #{method_name}()"
      end
      target_name = target_name.upcase
      packet_name = packet_name.upcase
      item_name = item_name.upcase

      if packet_name == 'LATEST'
        packet_name = CvtModel.determine_latest_packet_for_item(target_name, item_name, cache_timeout: cache_timeout, scope: scope)
      else
        # Determine if this item exists, it will raise appropriate errors if not
        TargetModel.packet_item(target_name, packet_name, item_name, scope: scope)
      end

      return [target_name, packet_name, item_name]
    end

    def _set_tlm_process_args(args, method_name, cache_timeout: nil, scope: $openc3_scope, token: $openc3_token)
      case args.length
      when 1
        target_name, packet_name, item_name, value = extract_fields_from_set_tlm_text(args[0])
      when 4
        target_name = args[0]
        packet_name = args[1]
        item_name = args[2]
        value = args[3]
      else
        # Invalid number of arguments
        raise "ERROR: Invalid number of arguments (#{args.length}) passed to #{method_name}()"
      end
      target_name = target_name.upcase
      packet_name = packet_name.upcase
      item_name = item_name.upcase

      if packet_name == 'LATEST'
        packet_name = CvtModel.determine_latest_packet_for_item(target_name, item_name, cache_timeout: cache_timeout, scope: scope)
      else
        # Determine if this item exists, it will raise appropriate errors if not
        TargetModel.packet_item(target_name, packet_name, item_name, scope: scope)
      end

      return [target_name, packet_name, item_name, value]
    end
  end
end
