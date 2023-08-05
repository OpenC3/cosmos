# Copyright 2023 OpenC3, Inc.
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

import json
import operator
from openc3.utilities.store import Store
from openc3.models.model import Model
from openc3.models.target_model import TargetModel
from openc3.environment import OPENC3_SCOPE


class CvtModel(Model):
    VALUE_TYPES = ["RAW", "CONVERTED", "FORMATTED", "WITH_UNITS"]
    # def self.build_json_from_packet(packet)
    #   packet.decom
    # end

    # # Delete the current value table for a target
    # def self.del(target_name:, packet_name:, scope: $openc3_scope)
    #   Store.hdel("#{scope}__tlm__#{target_name}", packet_name)
    # end

    # # Set the current value table for a target, packet
    # def self.set(hash, target_name:, packet_name:, scope: $openc3_scope)
    #   Store.hset("#{scope}__tlm__#{target_name}", packet_name, JSON.generate(hash.as_json(:allow_nan => true)))
    # end

    @classmethod
    def get(cls, target_name, packet_name, scope=OPENC3_SCOPE):
        """Get the hash for packet in the CVT"""
        packet = Store.hget(f"{scope}__tlm__{target_name}", packet_name)
        if not packet:
            raise RuntimeError(f"Packet '{target_name} {packet_name}' does not exist")
        return json.loads(packet)

    # Set an item in the current value table
    @classmethod
    def set_item(
        cls, target_name, packet_name, item_name, value, type, scope=OPENC3_SCOPE
    ):
        hash = cls.get(target_name=target_name, packet_name=packet_name, scope=scope)
        match type:
            case "WITH_UNITS":
                hash["#{item_name}__U"] = str(
                    value
                )  # WITH_UNITS should always be a string
            case "FORMATTED":
                hash["#{item_name}__F"] = str(
                    value
                )  # FORMATTED should always be a string
            case "CONVERTED":
                hash["#{item_name}__C"] = value
            case "RAW":
                hash[item_name] = value
            case "ALL":
                hash["#{item_name}__U"] = str(
                    value
                )  # WITH_UNITS should always be a string
                hash["#{item_name}__F"] = str(
                    value
                )  # FORMATTED should always be a string
                hash["#{item_name}__C"] = value
                hash[item_name] = value
            case _:
                raise RuntimeError(
                    "Unknown type '#{type}' for #{target_name} #{packet_name} #{item_name}"
                )
        Store.hset(f"{scope}__tlm__{target_name}", packet_name, json.dumps(hash))

    # Get an item from the current value table
    @classmethod
    def get_item(cls, target_name, packet_name, item_name, type, scope=OPENC3_SCOPE):
        override_key = item_name
        types = []
        match type:
            case "WITH_UNITS":
                types = [
                    "#{item_name}__U",
                    "#{item_name}__F",
                    "#{item_name}__C",
                    item_name,
                ]
                override_key = "#{item_name}__U"
            case "FORMATTED":
                types = ["#{item_name}__F", "#{item_name}__C", item_name]
                override_key = "#{item_name}__F"
            case "CONVERTED":
                types = ["#{item_name}__C", item_name]
                override_key = "#{item_name}__C"
            case "RAW":
                types = [item_name]
            case _:
                raise RuntimeError(
                    f"Unknown type '{type}' for {target_name} {packet_name} {item_name}"
                )
        overrides = Store.hget(f"{scope}__override__{target_name}", packet_name)
        if overrides:
            result = json.loads(overrides)[override_key]
            if result:
                return result
        hash = cls.get(target_name, packet_name, scope)
        for result in operator.itemgetter(*types)(hash):
            if result:
                if type == "FORMATTED" or type == "WITH_UNITS":
                    return str(result)
                return result
        return None

    #     # Return all item values and limit state from the CVT
    #     #
    #     # @param items [Array<String>] Items to return. Must be formatted as TGT__PKT__ITEM__TYPE
    #     # @param stale_time [Integer] Time in seconds from Time.now that value will be marked stale
    #     # @return [Array] Array of values
    #     def self.get_tlm_values(items, stale_time: 30, scope: $openc3_scope)
    #       now = Time.now.sys.to_f
    #       results = []
    #       lookups = []
    #       packet_lookup = {}
    #       overrides = {}
    #       # First generate a lookup hash of all the items represented so we can query the CVT
    #       items.each { |item| _parse_item(lookups, overrides, item, scope: scope) }

    #       lookups.each do |target_packet_key, target_name, packet_name, value_keys|
    #         unless packet_lookup[target_packet_key]
    #           packet_lookup[target_packet_key] = get(target_name: target_name, packet_name: packet_name, scope: scope)
    #         end
    #         hash = packet_lookup[target_packet_key]
    #         item_result = []
    #         if value_keys.is_a?(Hash) # Set in _parse_item to indicate override
    #           item_result[0] = value_keys['value']
    #         else
    #           value_keys.each do |key|
    #             item_result[0] = hash[key]
    #             break if item_result[0] # We want the first value
    #           end
    #           # If we were able to find a value, try to get the limits state
    #           if item_result[0]
    #             if now - hash['RECEIVED_TIMESECONDS'] > stale_time
    #               item_result[1] = :STALE
    #             else
    #               # The last key is simply the name (RAW) so we can append __L
    #               # If there is no limits then it returns nil which is acceptable
    #               item_result[1] = hash["#{value_keys[-1]}__L"]
    #               item_result[1] = item_result[1].intern if item_result[1] # Convert to symbol
    #             end
    #           else
    #             raise "Item '#{target_name} #{packet_name} #{value_keys[-1]}' does not exist" unless hash.key?(value_keys[-1])
    #           end
    #         end
    #         results << item_result
    #       end
    #       results
    #     end

    @classmethod
    def overrides(cls, scope=OPENC3_SCOPE):
        """Return all the overrides"""
        overrides = []
        for target_name in TargetModel.names(scope):
            all = Store.hgetall(f"{scope}__override__{target_name}")
            if not all:
                continue
            for packet_name, hash in all:
                items = json.loads(hash)
                for key, value in items.items():
                    item = {}
                    item["target_name"] = target_name
                    item["packet_name"] = packet_name
                    item_name, value_type_key = key.split("__")
                    item["item_name"] = item_name
                    match value_type_key:
                        case "U":
                            item["value_type"] = "WITH_UNITS"
                        case "F":
                            item["value_type"] = "FORMATTED"
                        case "C":
                            item["value_type"] = "CONVERTED"
                        case _:
                            item["value_type"] = "RAW"
                    item["value"] = value
                    overrides.append(item)
        return overrides

    @classmethod
    def override(
        cls, target_name, packet_name, item_name, value, type="ALL", scope=OPENC3_SCOPE
    ):
        """Override a current value table item such that it always returns the same value for the given type"""
        hash = Store.hget(f"{scope}__override__{target_name}", packet_name)
        if hash:
            hash = json.loads(hash)
        if not hash:
            hash = {}
        match type:
            case "ALL":
                hash[item_name] = value
                hash[f"{item_name}__C"] = value
                hash[f"{item_name}__F"] = str(value)
                hash[f"{item_name}__U"] = str(value)
            case "RAW":
                hash[item_name] = value
            case "CONVERTED":
                hash[f"{item_name}__C"] = value
            case "FORMATTED":
                hash[f"{item_name}__F"] = str(value)  # Always a String
            case "WITH_UNITS":
                hash[f"{item_name}__U"] = str(value)  # Always a String
            case _:
                raise RuntimeError(
                    f"Unknown type '{type}' for {target_name} {packet_name} {item_name}"
                )
        Store.hset(f"{scope}__override__{target_name}", packet_name, json.dumps(hash))

    # Normalize a current value table item such that it returns the actual value
    @classmethod
    def normalize(
        cls, target_name, packet_name, item_name, type="ALL", scope=OPENC3_SCOPE
    ):
        hash = Store.hget(f"{scope}__override__{target_name}", packet_name)
        if hash:
            hash = json.loads(hash)
        if not hash:
            hash = {}
        match type:
            case "ALL":
                hash.pop(item_name)
                hash.pop(f"{item_name}__C")
                hash.pop(f"{item_name}__F")
                hash.pop(f"{item_name}__U")
            case "RAW":
                hash.pop(item_name)
            case "CONVERTED":
                hash.pop(f"{item_name}__C")
            case "FORMATTED":
                hash.pop(f"{item_name}__F")
            case "WITH_UNITS":
                hash.pop(f"{item_name}__U")
            case _:
                raise RuntimeError(
                    f"Unknown type '{type}' for {target_name} {packet_name} {item_name}"
                )
        if not hash:
            Store.hdel(f"{scope}__override__{target_name}", packet_name)
        else:
            Store.hset(
                f"{scope}__override__{target_name}", packet_name, json.dumps(hash)
            )


#     # PRIVATE METHODS

#     # parse item and update lookups with packet_name and target_name and keys
#     # return an ordered array of hash with keys
#     def self._parse_item(lookups, overrides, item, scope:)
#       target_name, packet_name, item_name, value_type = item.split('__')

#       # We build lookup keys by including all the less formatted types to gracefully degrade lookups
#       # This allows the user to specify WITH_UNITS and if there is no conversions it will simply return the RAW value
#       case value_type
#       when 'RAW'
#         keys = [item_name]
#       when 'CONVERTED'
#         keys = ["#{item_name}__C", item_name]
#       when 'FORMATTED'
#         keys = ["#{item_name}__F", "#{item_name}__C", item_name]
#       when 'WITH_UNITS'
#         keys = ["#{item_name}__U", "#{item_name}__F", "#{item_name}__C", item_name]
#       else
#         raise "Unknown value type '#{value_type}'"
#       end
#       tgt_pkt_key = "#{target_name}__#{packet_name}"
#       # Check the overrides cache for this target / packet
#       unless overrides[tgt_pkt_key]
#         override_data = Store.hget("#{scope}__override__#{target_name}", packet_name)
#         if override_data
#           overrides[tgt_pkt_key] = JSON.parse(override_data, :allow_nan => true, :create_additions => true)
#         else
#           overrides[tgt_pkt_key] = {}
#         end
#       end
#       if overrides[tgt_pkt_key][keys[0]]
#         # Set the result as a Hash to distingish it from the key array and from an overridden Array value
#         keys = {'value' => overrides[tgt_pkt_key][keys[0]]}
#       end
#       lookups << [tgt_pkt_key, target_name, packet_name, keys]
