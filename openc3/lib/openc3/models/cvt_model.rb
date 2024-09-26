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

require 'openc3/utilities/store'
require 'openc3/utilities/store_queued'
require 'openc3/models/target_model'

module OpenC3
  class CvtModel
    @@packet_cache = {}
    @@override_cache = {}

    VALUE_TYPES = [:RAW, :CONVERTED, :FORMATTED, :WITH_UNITS]
    def self.build_json_from_packet(packet)
      packet.decom
    end

    # Delete the current value table for a target
    def self.del(target_name:, packet_name:, scope: $openc3_scope)
      key = "#{scope}__tlm__#{target_name}"
      tgt_pkt_key = key + "__#{packet_name}"
      @@packet_cache[tgt_pkt_key] = nil
      Store.hdel(key, packet_name)
    end

    # Set the current value table for a target, packet
    def self.set(hash, target_name:, packet_name:, queued: false, scope: $openc3_scope)
      packet_json = JSON.generate(hash.as_json(:allow_nan => true))
      key = "#{scope}__tlm__#{target_name}"
      tgt_pkt_key = key + "__#{packet_name}"
      @@packet_cache[tgt_pkt_key] = [Time.now, hash]
      if queued
        StoreQueued.hset(key, packet_name, packet_json)
      else
        Store.hset(key, packet_name, packet_json)
      end
    end

    # Get the hash for packet in the CVT
    # Note: Does not apply overrides
    def self.get(target_name:, packet_name:, cache_timeout: nil, scope: $openc3_scope)
      key = "#{scope}__tlm__#{target_name}"
      tgt_pkt_key = key + "__#{packet_name}"
      now = Time.now
      if cache_timeout
        cache_time, hash = @@packet_cache[tgt_pkt_key]
        return hash if hash and (now - cache_time) < cache_timeout
      end
      packet = Store.hget(key, packet_name)
      raise "Packet '#{target_name} #{packet_name}' does not exist" unless packet
      hash = JSON.parse(packet, :allow_nan => true, :create_additions => true)
      @@packet_cache[tgt_pkt_key] = [now, hash]
      hash
    end

    # Set an item in the current value table
    def self.set_item(target_name, packet_name, item_name, value, type:, queued: false, scope: $openc3_scope)
      hash = get(target_name: target_name, packet_name: packet_name, cache_timeout: nil, scope: scope)
      case type
      when :WITH_UNITS
        hash["#{item_name}__U"] = value.to_s # WITH_UNITS should always be a string
      when :FORMATTED
        hash["#{item_name}__F"] = value.to_s # FORMATTED should always be a string
      when :CONVERTED
        hash["#{item_name}__C"] = value
      when :RAW
        hash[item_name] = value
      when :ALL
        hash["#{item_name}__U"] = value.to_s # WITH_UNITS should always be a string
        hash["#{item_name}__F"] = value.to_s # FORMATTED should always be a string
        hash["#{item_name}__C"] = value
        hash[item_name] = value
      else
        raise "Unknown type '#{type}' for #{target_name} #{packet_name} #{item_name}"
      end
      set(hash, target_name: target_name, packet_name: packet_name, queued: queued, scope: scope)
    end

    # Get an item from the current value table
    def self.get_item(target_name, packet_name, item_name, type:, cache_timeout: nil, scope: $openc3_scope)
      result, types = self._handle_item_override(target_name, packet_name, item_name, type: type, cache_timeout: cache_timeout, scope: scope)
      return result if result
      hash = get(target_name: target_name, packet_name: packet_name, cache_timeout: cache_timeout, scope: scope)
      hash.values_at(*types).each do |cvt_value|
        if cvt_value
          if type == :FORMATTED or type == :WITH_UNITS
            return cvt_value.to_s
          end
          return cvt_value
        end
      end
      # RECEIVED_COUNT is a special case where it is 0 if it doesn't exist
      # This allows scripts to check against the value to see if the packet was ever received
      if item_name == "RECEIVED_COUNT"
        return 0
      else
        return nil
      end
    end

    # Return all item values and limit state from the CVT
    #
    # @param items [Array<String>] Items to return. Must be formatted as TGT__PKT__ITEM__TYPE
    # @param stale_time [Integer] Time in seconds from Time.now that value will be marked stale
    # @return [Array] Array of values
    def self.get_tlm_values(items, stale_time: 30, cache_timeout: nil, scope: $openc3_scope)
      now = Time.now
      results = []
      lookups = []
      packet_lookup = {}
      overrides = {}
      # First generate a lookup hash of all the items represented so we can query the CVT
      items.each { |item| _parse_item(now, lookups, overrides, item, cache_timeout: cache_timeout, scope: scope) }

      now = now.to_f
      lookups.each do |target_packet_key, target_name, packet_name, value_keys|
        unless packet_lookup[target_packet_key]
          packet_lookup[target_packet_key] = get(target_name: target_name, packet_name: packet_name, cache_timeout: cache_timeout, scope: scope)
        end
        hash = packet_lookup[target_packet_key]
        item_result = []
        if value_keys.is_a?(Hash) # Set in _parse_item to indicate override
          item_result[0] = value_keys['value']
        else
          value_keys.each do |key|
            item_result[0] = hash[key]
            break if item_result[0] # We want the first value
          end
          # If we were able to find a value, try to get the limits state
          if item_result[0]
            if now - hash['RECEIVED_TIMESECONDS'] > stale_time
              item_result[1] = :STALE
            else
              # The last key is simply the name (RAW) so we can append __L
              # If there is no limits then it returns nil which is acceptable
              item_result[1] = hash["#{value_keys[-1]}__L"]
              item_result[1] = item_result[1].intern if item_result[1] # Convert to symbol
            end
          else
            raise "Item '#{target_name} #{packet_name} #{value_keys[-1]}' does not exist" unless hash.key?(value_keys[-1])
          end
        end
        results << item_result
      end
      results
    end

    # Return all the overrides
    # Note: Does not use cache to benefit from hgetall
    def self.overrides(scope: $openc3_scope)
      overrides = []
      TargetModel.names(scope: scope).each do |target_name|
        all = Store.hgetall("#{scope}__override__#{target_name}")
        next if all.nil? or all.empty?
        all.each do |packet_name, hash|
          items = JSON.parse(hash, :allow_nan => true, :create_additions => true)
          items.each do |key, value|
            item = {}
            item['target_name'] = target_name
            item['packet_name'] = packet_name
            item_name, value_type_key = key.split('__')
            item['item_name'] = item_name
            case value_type_key
            when 'U'
              item['value_type'] = 'WITH_UNITS'
            when 'F'
              item['value_type'] = 'FORMATTED'
            when 'C'
              item['value_type'] = 'CONVERTED'
            else
              item['value_type'] = 'RAW'
            end
            item['value'] = value
            overrides << item
          end
        end
      end
      overrides
    end

    # Override a current value table item such that it always returns the same value
    # for the given type
    def self.override(target_name, packet_name, item_name, value, type: :ALL, scope: $openc3_scope)
      hash = Store.hget("#{scope}__override__#{target_name}", packet_name)
      hash = JSON.parse(hash, :allow_nan => true, :create_additions => true) if hash
      hash ||= {} # In case the above didn't create anything
      case type
      when :ALL
        hash[item_name] = value
        hash["#{item_name}__C"] = value
        hash["#{item_name}__F"] = value.to_s
        hash["#{item_name}__U"] = value.to_s
      when :RAW
        hash[item_name] = value
      when :CONVERTED
        hash["#{item_name}__C"] = value
      when :FORMATTED
        hash["#{item_name}__F"] = value.to_s # Always a String
      when :WITH_UNITS
        hash["#{item_name}__U"] = value.to_s # Always a String
      else
        raise "Unknown type '#{type}' for #{target_name} #{packet_name} #{item_name}"
      end

      tgt_pkt_key = "#{scope}__tlm__#{target_name}__#{packet_name}"
      @@override_cache[tgt_pkt_key] = [Time.now, hash]
      Store.hset("#{scope}__override__#{target_name}", packet_name, JSON.generate(hash.as_json(:allow_nan => true)))
    end

    # Normalize a current value table item such that it returns the actual value
    def self.normalize(target_name, packet_name, item_name, type: :ALL, scope: $openc3_scope)
      hash = Store.hget("#{scope}__override__#{target_name}", packet_name)
      hash = JSON.parse(hash, :allow_nan => true, :create_additions => true) if hash
      hash ||= {} # In case the above didn't create anything
      case type
      when :ALL
        hash.delete(item_name)
        hash.delete("#{item_name}__C")
        hash.delete("#{item_name}__F")
        hash.delete("#{item_name}__U")
      when :RAW
        hash.delete(item_name)
      when :CONVERTED
        hash.delete("#{item_name}__C")
      when :FORMATTED
        hash.delete("#{item_name}__F")
      when :WITH_UNITS
        hash.delete("#{item_name}__U")
      else
        raise "Unknown type '#{type}' for #{target_name} #{packet_name} #{item_name}"
      end

      tgt_pkt_key = "#{scope}__tlm__#{target_name}__#{packet_name}"
      if hash.empty?
        @@override_cache.delete(tgt_pkt_key)
        Store.hdel("#{scope}__override__#{target_name}", packet_name)
      else
        @@override_cache[tgt_pkt_key] = [Time.now, hash]
        Store.hset("#{scope}__override__#{target_name}", packet_name, JSON.generate(hash.as_json(:allow_nan => true)))
      end
    end

    def self.determine_latest_packet_for_item(target_name, item_name, cache_timeout: nil, scope: $openc3_scope)
      item_map = TargetModel.get_item_to_packet_map(target_name, scope: scope)
      packet_names = item_map[item_name]
      raise "Item '#{target_name} LATEST #{item_name}' does not exist for scope: #{scope}" unless packet_names

      latest = -1
      latest_packet_name = nil
      packet_names.each do |packet_name|
        hash = get(target_name: target_name, packet_name: packet_name, cache_timeout: cache_timeout, scope: scope)
        if hash['PACKET_TIMESECONDS'] && hash['PACKET_TIMESECONDS'] > latest
          latest = hash['PACKET_TIMESECONDS']
          latest_packet_name = packet_name
        end
      end
      raise "Item '#{target_name} LATEST #{item_name}' does not exist for scope: #{scope}" if latest == -1
      return latest_packet_name
    end

    # PRIVATE METHODS

    def self._handle_item_override(target_name, packet_name, item_name, type:, cache_timeout:, scope: $openc3_scope)
      override_key = item_name
      types = []
      case type
      when :WITH_UNITS
        types = ["#{item_name}__U", "#{item_name}__F", "#{item_name}__C", item_name]
        override_key = "#{item_name}__U"
      when :FORMATTED
        types = ["#{item_name}__F", "#{item_name}__C", item_name]
        override_key = "#{item_name}__F"
      when :CONVERTED
        types = ["#{item_name}__C", item_name]
        override_key = "#{item_name}__C"
      when :RAW
        types = [item_name]
      else
        raise "Unknown type '#{type}' for #{target_name} #{packet_name} #{item_name}"
      end

      tgt_pkt_key = "#{scope}__tlm__#{target_name}__#{packet_name}"
      overrides = _get_overrides(Time.now, tgt_pkt_key, {}, target_name, packet_name, cache_timeout: cache_timeout, scope: scope)
      result = overrides[override_key]
      return result, types if result
      return nil, types
    end

    def self._get_overrides(now, tgt_pkt_key, overrides, target_name, packet_name, cache_timeout:, scope:)
      if cache_timeout
        cache_time, hash = @@override_cache[tgt_pkt_key]
        if hash and (now - cache_time) < cache_timeout
          overrides[tgt_pkt_key] = hash
          return hash
        end
      end
      override_data = Store.hget("#{scope}__override__#{target_name}", packet_name)
      if override_data
        hash = JSON.parse(override_data, :allow_nan => true, :create_additions => true)
        overrides[tgt_pkt_key] = hash
      else
        hash = {}
        overrides[tgt_pkt_key] = {}
      end
      @@override_cache[tgt_pkt_key] = [now, hash] # always update
      return hash
    end

    # parse item and update lookups with packet_name and target_name and keys
    # return an ordered array of hash with keys
    def self._parse_item(now, lookups, overrides, item, cache_timeout:, scope:)
      target_name, packet_name, item_name, value_type = item

      # We build lookup keys by including all the less formatted types to gracefully degrade lookups
      # This allows the user to specify WITH_UNITS and if there is no conversions it will simply return the RAW value
      case value_type.to_s
      when 'RAW'
        keys = [item_name]
      when 'CONVERTED'
        keys = ["#{item_name}__C", item_name]
      when 'FORMATTED'
        keys = ["#{item_name}__F", "#{item_name}__C", item_name]
      when 'WITH_UNITS'
        keys = ["#{item_name}__U", "#{item_name}__F", "#{item_name}__C", item_name]
      else
        raise "Unknown value type '#{value_type}'"
      end

      # Check the overrides cache for this target / packet
      tgt_pkt_key = "#{scope}__tlm__#{target_name}__#{packet_name}"
      _get_overrides(now, tgt_pkt_key, overrides, target_name, packet_name, cache_timeout: cache_timeout, scope: scope) unless overrides[tgt_pkt_key]

      # Set the result as a Hash to distinguish it from the key array and from an overridden Array value
      value = overrides[tgt_pkt_key][keys[0]]
      keys = {'value' => value} if value

      lookups << [tgt_pkt_key, target_name, packet_name, keys]
    end
  end
end
