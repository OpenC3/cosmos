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
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1963
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1957

require 'openc3/models/target_model'
require 'openc3/models/cvt_model'
# require 'openc3/packets/packet' # Circular require
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
                       'tlm_with_units', # DEPRECATED
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
    # @param type [Symbol] Telemetry type, :RAW, :CONVERTED (default), :FORMATTED
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

    # @deprecated Use tlm_formatted
    def tlm_with_units(*args, cache_timeout: nil, manual: false, scope: $openc3_scope, token: $openc3_token)
      tlm(*args, type: :FORMATTED, cache_timeout: cache_timeout, manual: manual, scope: scope, token: token)
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
    # @param type [Symbol] Telemetry type, :RAW, :CONVERTED (default), :FORMATTED
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
    # @param type [Symbol] Telemetry type, :RAW, :CONVERTED (default), :FORMATTED
    # @param received_time [Integer, nil] Optional received time as nanoseconds since Unix epoch
    def inject_tlm(target_name, packet_name, item_hash = nil, type: :CONVERTED, stored: false, received_time: nil, manual: false, scope: $openc3_scope, token: $openc3_token)
      _tlm_reject_latest(packet_name.to_s.upcase, 'inject_tlm')
      authorize(permission: 'tlm_set', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
      type = type.to_s.intern
      target_name = target_name.upcase
      packet_name = packet_name.upcase
      unless CvtModel::VALUE_TYPES.include?(type)
        raise "Unknown type '#{type}' for #{target_name} #{packet_name} (inject_tlm)"
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
        InterfaceTopic.inject_tlm(interface_name, target_name, packet_name, item_hash, type: type, stored: stored, received_time: received_time, scope: scope)
      else
        DecomInterfaceTopic.inject_tlm(target_name, packet_name, item_hash, type: type, stored: stored, received_time: received_time, scope: scope)
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
    #   description). A packet name of LATEST overrides the item in every
    #   packet which contains it.
    # @param type [Symbol] Telemetry type, :ALL (default), :RAW, :CONVERTED, :FORMATTED
    def override_tlm(*args, type: :ALL, manual: false, scope: $openc3_scope, token: $openc3_token)
      target_name, packet_names, item_name, value = _set_tlm_process_args_all_packets(args, __method__, scope: scope)
      packet_names.each do |packet_name|
        authorize(permission: 'tlm_set', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
      end
      packet_names.each do |packet_name|
        CvtModel.override(target_name, packet_name, item_name, value, type: type.intern, scope: scope)
      end
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
    #   (see the calling style in the description). A packet name of LATEST
    #   normalizes the item in every packet which contains it.
    # @param type [Symbol] Telemetry type, :ALL (default), :RAW, :CONVERTED, :FORMATTED
    #   Also takes :ALL which means to normalize all telemetry types
    def normalize_tlm(*args, type: :ALL, manual: false, scope: $openc3_scope, token: $openc3_token)
      target_name, packet_names, item_name = _tlm_process_args_all_packets(args, __method__, scope: scope)
      packet_names.each do |packet_name|
        authorize(permission: 'tlm_set', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
      end
      packet_names.each do |packet_name|
        CvtModel.normalize(target_name, packet_name, item_name, type: type.intern, scope: scope)
      end
    end

    # Returns the raw buffer for a telemetry packet.
    #
    # @param target_name [String] Name of the target
    # @param packet_name [String] Name of the packet
    # @return [Hash] telemetry hash with last telemetry buffer
    def get_tlm_buffer(*args, manual: false, scope: $openc3_scope, token: $openc3_token, timeout: 5)
      target_name, packet_name = _extract_target_packet_names('get_tlm_buffer', *args)
      authorize(permission: 'tlm', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
      model = TargetModel.packet(target_name, packet_name, scope: scope)
      if model["subpacket"]
        msg_hash = DecomInterfaceTopic.get_tlm_buffer(target_name, packet_name, timeout: timeout, scope: scope)
        msg_hash['buffer'] = msg_hash['buffer'].b
        return msg_hash
      else
        topic = "#{scope}__TELEMETRY__{#{target_name}}__#{packet_name}"
        db_shard = Store.db_shard_for_target(target_name, scope: scope)
        msg_id, msg_hash = Topic.get_newest_message(topic, db_shard: db_shard)
        if msg_id
          msg_hash['buffer'] = msg_hash['buffer'].b
          return msg_hash
        end
      end
      return nil
    end

    # Returns all the values (along with their limits state) for a packet.
    #
    # @param target_name [String] Name of the target
    # @param packet_name [String] Name of the packet
    # @param stale_time [Integer] Time in seconds from Time.now that packet will be marked stale
    # @param type [Symbol] Types returned, :RAW, :CONVERTED (default), :FORMATTED
    # @return [Array<String, Object, Symbol|nil>] Returns an Array consisting
    #   of [item name, item value, item limits state] where the item limits
    #   state can be one of {OpenC3::Limits::LIMITS_STATES}
    def get_tlm_packet(*args, stale_time: 30, type: :CONVERTED, cache_timeout: nil, manual: false, scope: $openc3_scope, token: $openc3_token)
      target_name, packet_name = _extract_target_packet_names('get_tlm_packet', *args)
      authorize(permission: 'tlm', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
      packet = TargetModel.packet(target_name, packet_name, scope: scope)
      t = _validate_tlm_type(type)
      raise ArgumentError, "Unknown type '#{type}' for #{target_name} #{packet_name}" if t.nil?
      items = packet["items"].reject { | item | item["hidden"] }
      items = items.map { | item | item['name'].upcase }
      cvt_items = items.map { | item | [target_name, packet_name, item, type] }
      current_values = CvtModel.get_tlm_values(cvt_items, stale_time: stale_time, cache_timeout: cache_timeout, scope: scope)
      items.zip(current_values).map { | item , values | [item, values[0], values[1]]}
    end

    # Returns the available items from a list of requested screen items
    # This does the packet introspection to determine what is actually available
    # Like if you ask for FORMATTED but only RAW is available
    def get_tlm_available(items, manual: false, scope: $openc3_scope, token: $openc3_token)
      results = []
      items.each do |item|
        item_upcase = item.to_s.upcase
        target_name, orig_packet_name, item_name, value_type = item_upcase.split('__')
        packet_name = orig_packet_name
        raise ArgumentError, "items must be formatted as TGT__PKT__ITEM__TYPE" if target_name.nil? || packet_name.nil? || item_name.nil? || value_type.nil?
        if orig_packet_name == 'LATEST'
          # A LATEST item can come from any packet containing it. Report the best value
          # type and limits of any of them since the CVT falls back to the available
          # type and historical lookups check the type available in each packet.
          # We can have a large cache_timeout of 1 because all we're trying to do is lookup a packet
          packet_name = CvtModel.determine_latest_packet_for_item(target_name, item_name, cache_timeout: 1, scope: scope)
          packet_names = _tlm_packet_names(target_name, orig_packet_name, item_name, scope: scope)
        else
          packet_names = [packet_name]
        end
        authorize(permission: 'tlm', target_name: target_name, packet_name: packet_name, scope: scope, token: token)
        begin
          packet_items = packet_names.map { |name| TargetModel.packet_item(target_name, name, item_name, scope: scope) }
          available_type = packet_items.map { |packet_item| _tlm_available_value_type(packet_item, item_name, value_type) }.max_by { |type| VALUE_TYPE_ORDER.index(type) }
          results << [target_name, orig_packet_name, item_name, available_type].join('__')
          # Tack on __LIMITS to notify that we have an available limits value
          if packet_items.any? { |packet_item| packet_item['limits']['DEFAULT'] }
            results[-1] += '__LIMITS'
          end
        rescue RuntimeError
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
      items.each do |item|
        # get_tlm_available returns nil for items which don't exist and its result is
        # passed directly here, so nil is a placeholder which returns a nil value
        if item.nil?
          cvt_items << [nil, nil, nil, nil, nil]
          next
        end
        # get_tlm_available tacks on __LIMITS to indicate a limits value is available
        # so accept both TGT__PKT__ITEM__TYPE and TGT__PKT__ITEM__TYPE__LIMITS
        parts = item.to_s.upcase.split('__')
        raise ArgumentError, "items must be formatted as TGT__PKT__ITEM__TYPE" if parts.length < 4 || parts.length > 5
        target_name, packet_name, item_name, value_type, limits = parts
        if packet_name == 'LATEST'
          if start_time
            # The packet received most recently now isn't necessarily the one received most
            # recently at start_time so keep every candidate packet for _tlm_latest_history
            # Each packet must be queried for the value type and limits it has or the query fails
            candidates = _tlm_packet_names(target_name, packet_name, item_name, scope: scope).map do |candidate|
              packets << [target_name, candidate]
              candidate_item = TargetModel.packet_item(target_name, candidate, item_name, scope: scope)
              candidate_limits = (limits and candidate_item['limits']['DEFAULT']) ? limits : nil
              [target_name, candidate, item_name, _tlm_available_value_type(candidate_item, item_name, value_type), candidate_limits]
            end
            cvt_items << [target_name, packet_name, item_name, value_type, limits, candidates]
            next
          end
          packet_name = CvtModel.determine_latest_packet_for_item(target_name, item_name, cache_timeout: cache_timeout, scope: scope)
        end
        # NOTE: limits is required by the historical (start_time) QuestDB lookup
        cvt_items << [target_name, packet_name, item_name, value_type, limits]
        packets << [target_name, packet_name]
      end
      packets.uniq!
      packets.each do |target_name, packet_name|
        authorize(permission: 'tlm', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
      end
      if cvt_items.any? { |cvt_item| cvt_item.length == 6 }
        return _tlm_latest_history(cvt_items, start_time: start_time, end_time: end_time, cache_timeout: cache_timeout, scope: scope)
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
    def get_item(*args, manual: false, scope: $openc3_scope, token: $openc3_token, cache_timeout: nil)
      target_name, packet_name, item_name = _extract_target_packet_item_names('get_item', *args)
      if packet_name == 'LATEST'
        packet_name = CvtModel.determine_latest_packet_for_item(target_name, item_name, cache_timeout: cache_timeout, scope: scope)
      end
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
        _tlm_reject_latest(packet_name, 'subscribe_packets')
        authorize(permission: 'tlm', target_name: target_name, packet_name: packet_name, manual: manual, scope: scope, token: token)
        topic = "#{scope}__DECOM__{#{target_name}}__#{packet_name}"
        db_shard = Store.db_shard_for_target(target_name, scope: scope)
        id, = Topic.get_newest_message(topic, db_shard: db_shard)
        results[topic] = id ? id : '0-0'
      end
      results.to_a.join(SUBSCRIPTION_DELIMITER)
    end
    # Alias the singular as well since that matches COSMOS 4
    alias subscribe_packet subscribe_packets

    # Get packets based on ID returned from subscribe_packet.
    # Packets are ordered within each subscribed packet stream (target/packet pair)
    # but are NOT interleaved by time across streams. If chronological order across
    # streams is required, sort the returned array by the 'time' field. Sorting only
    # orders the current batch - packets across separate get_packets calls may still
    # arrive out of order, so subscribers needing global ordering must buffer and merge
    # across calls.
    # @param id [String] ID returned from subscribe_packets or last call to get_packets
    # @param block [Integer] Unused - Blocking must be implemented at the client
    # @param count [Integer] Maximum number of packets to return from EACH packet stream
    # @return [Array<String, Array<Hash>] Array of the ID and array of all packets found
    def get_packets(id, block: nil, count: 1000, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'tlm', manual: manual, scope: scope, token: token)
      # Split the list of topic, ID values and turn it into a hash for easy updates
      lookup = Hash[*id.split(SUBSCRIPTION_DELIMITER)]
      # Group topics by db_shard for multi-shard support
      db_shard_groups = {}
      lookup.each do |topic, offset|
        target_name = topic.match(/__\{?([^}_]+)\}?__/)[1] rescue nil
        db_shard = Store.db_shard_for_target(target_name, scope: scope)
        db_shard_groups[db_shard] ||= { topics: [], offsets: [] }
        db_shard_groups[db_shard][:topics] << topic
        db_shard_groups[db_shard][:offsets] << offset
      end
      xread = {}
      db_shard_groups.each do |db_shard, group|
        result = Topic.read_topics(group[:topics], group[:offsets], nil, count, db_shard: db_shard) # Always don't block
        xread.merge!(result) if result
      end
      # Return the original ID and and empty array if we didn't get anything
      packets = []
      return [id, packets] if xread.empty?
      xread.each do |topic, data|
        data.each do |id, msg_hash|
          lookup[topic] = id # save the new ID
          json_hash = JSON.parse(msg_hash['json_data'], allow_nan: true, create_additions: true)
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
      _tlm_reject_latest(packet_name, method_name)
      return [target_name, packet_name]
    end

    # LATEST picks a packet per item so it can't identify a whole packet
    def _tlm_reject_latest(packet_name, method_name)
      raise "ERROR: LATEST is not supported by #{method_name}(), specify a packet name" if packet_name == 'LATEST'
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
      when :FORMATTED, :WITH_UNITS
        return 'F'
      else
        return nil
      end
    end

    def _tlm_process_args(args, method_name, cache_timeout: nil, scope: $openc3_scope, token: $openc3_token)
      target_name, packet_name, item_name = _tlm_extract_args(args, method_name)
      packet_name = _tlm_resolve_packet_name(target_name, packet_name, item_name, cache_timeout: cache_timeout, scope: scope)
      return [target_name, packet_name, item_name]
    end

    def _set_tlm_process_args(args, method_name, cache_timeout: nil, scope: $openc3_scope, token: $openc3_token)
      target_name, packet_name, item_name, value = _set_tlm_extract_args(args, method_name)
      packet_name = _tlm_resolve_packet_name(target_name, packet_name, item_name, cache_timeout: cache_timeout, scope: scope)
      return [target_name, packet_name, item_name, value]
    end

    # Like _tlm_process_args but returns an array of packet names where LATEST
    # expands to every packet containing the item. Used by APIs which change
    # an item so the change applies wherever the item appears.
    def _tlm_process_args_all_packets(args, method_name, scope: $openc3_scope)
      target_name, packet_name, item_name = _tlm_extract_args(args, method_name)
      return [target_name, _tlm_packet_names(target_name, packet_name, item_name, scope: scope), item_name]
    end

    def _set_tlm_process_args_all_packets(args, method_name, scope: $openc3_scope)
      target_name, packet_name, item_name, value = _set_tlm_extract_args(args, method_name)
      return [target_name, _tlm_packet_names(target_name, packet_name, item_name, scope: scope), item_name, value]
    end

    def _tlm_extract_args(args, method_name)
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
      return [target_name.upcase, packet_name.upcase, item_name.upcase]
    end

    def _set_tlm_extract_args(args, method_name)
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
      return [target_name.upcase, packet_name.upcase, item_name.upcase, value]
    end

    # Resolve LATEST to the most recently received packet containing the item
    def _tlm_resolve_packet_name(target_name, packet_name, item_name, cache_timeout: nil, scope: $openc3_scope)
      if packet_name == 'LATEST'
        packet_name = CvtModel.determine_latest_packet_for_item(target_name, item_name, cache_timeout: cache_timeout, scope: scope)
      else
        # Determine if this item exists, it will raise appropriate errors if not
        TargetModel.packet_item(target_name, packet_name, item_name, scope: scope)
      end
      return packet_name
    end

    VALUE_TYPE_ORDER = %w(RAW CONVERTED FORMATTED).freeze

    # Returns the value type available for an item given the requested value type
    def _tlm_available_value_type(item, item_name, value_type)
      # Must request the raw value when dealing with the reserved items
      return 'RAW' if Packet::RESERVED_ITEM_NAMES.include?(item_name)
      # Arrays must be accessed as RAW since there's no conversion
      return 'RAW' if item['array_size']

      # This logic must match the logic in Packet#decom
      converted = (item['states'] or (item['read_conversion'] and item['data_type'] != 'DERIVED'))
      case value_type
      when 'FORMATTED', 'WITH_UNITS'
        return 'FORMATTED' if item['format_string'] or item['units']
        return converted ? 'CONVERTED' : 'RAW'
      when 'CONVERTED'
        return converted ? 'CONVERTED' : 'RAW'
      else # RAW or unknown
        return 'RAW'
      end
    end

    # Historical lookup where some items are LATEST. Those items have a 6th element
    # holding the item to look up in every packet which contains the item.
    def _tlm_latest_history(cvt_items, start_time:, end_time:, cache_timeout:, scope:)
      latest = cvt_items.each_index.select { |index| cvt_items[index].length == 6 }
      regular = cvt_items.each_index.reject { |index| cvt_items[index].length == 6 }

      if end_time
        # The QuestDB lookup ASOF JOINs every packet to the rows of the first, so
        # a range needs a regular item first to drive the rows. Without one keep
        # the realtime behavior of using the packet received most recently now.
        if regular.all? { |index| cvt_items[index][2].nil? }
          cvt_items = cvt_items.map do |target_name, packet_name, item_name, value_type, limits, _|
            packet_name = CvtModel.determine_latest_packet_for_item(target_name, item_name, cache_timeout: cache_timeout, scope: scope) if packet_name == 'LATEST'
            [target_name, packet_name, item_name, value_type, limits]
          end
          return CvtModel.tsdb_lookup(cvt_items, start_time: start_time, end_time: end_time, scope: scope)
        end

        query = []
        query_index = {}
        add = lambda { |query_item| query_index[query_item] ||= (query << query_item; query.length - 1) }
        positions = Array.new(cvt_items.length)
        regular.each { |index| positions[index] = add.call(cvt_items[index]) }
        latest.each do |index|
          positions[index] = cvt_items[index][5].map do |candidate|
            target_name, packet_name = candidate
            [add.call(candidate), add.call([target_name, packet_name, 'PACKET_TIMESECONDS', 'RAW', nil])]
          end
        end
        rows = CvtModel.tsdb_lookup(query, start_time: start_time, end_time: end_time, scope: scope, flatten: false)
        return rows unless rows.is_a?(Array) and rows.length > 0
        rows = rows.map do |row|
          positions.map do |position|
            next row[position] if position.is_a?(Integer)
            # Take the candidate with the newest packet time at this row
            _tlm_newest(position.map { |value_index, time_index| [row[time_index][0], row[value_index]] }) || [nil, nil]
          end
        end
        # Match tsdb_lookup which returns a flat array for a single row
        return rows.length == 1 ? rows[0] : rows
      end

      # A point in time returns the last row of the first packet before start_time
      # with the other packets ASOF JOINed at that row. A candidate packet received
      # after that row would be missed so query each candidate packet on its own.
      found = false
      row = Array.new(cvt_items.length) { [nil, nil] }
      unless regular.all? { |index| cvt_items[index][2].nil? }
        result = CvtModel.tsdb_lookup(regular.map { |index| cvt_items[index] }, start_time: start_time, scope: scope, flatten: false)
        if result.is_a?(Array) and result.length > 0
          found = true
          regular.each_with_index { |index, result_index| row[index] = result[0][result_index] }
        end
      end
      # Group the LATEST items by candidate packet so each packet is queried once
      by_packet = {}
      latest.each do |index|
        cvt_items[index][5].each do |candidate|
          target_name, packet_name = candidate
          (by_packet[[target_name, packet_name]] ||= {})[index] = candidate
        end
      end
      found_values = Hash.new { |hash, key| hash[key] = [] }
      by_packet.each do |(target_name, packet_name), packet_items|
        query = packet_items.values.uniq
        query << [target_name, packet_name, 'PACKET_TIMESECONDS', 'RAW', nil]
        result = CvtModel.tsdb_lookup(query, start_time: start_time, scope: scope, flatten: false)
        next unless result.is_a?(Array) and result.length > 0
        values = result[0]
        packet_items.each { |index, query_item| found_values[index] << [values[-1][0], values[query.index(query_item)]] }
      end
      found_values.each do |index, candidates|
        value = _tlm_newest(candidates)
        next unless value
        found = true
        row[index] = value
      end
      return found ? row : {}
    end

    # Return the value with the newest time from [time, value] pairs, or nil
    def _tlm_newest(candidates)
      candidates.select { |time, _| time }.max_by { |time, _| time }&.last
    end

    # Expand LATEST to every packet containing the item
    def _tlm_packet_names(target_name, packet_name, item_name, scope: $openc3_scope)
      if packet_name == 'LATEST'
        packet_names = TargetModel.get_item_to_packet_map(target_name, scope: scope)[item_name]
        raise "Item '#{target_name} LATEST #{item_name}' does not exist for scope: #{scope}" unless packet_names
        return packet_names
      else
        # Determine if this item exists, it will raise appropriate errors if not
        TargetModel.packet_item(target_name, packet_name, item_name, scope: scope)
        return [packet_name]
      end
    end
  end
end
