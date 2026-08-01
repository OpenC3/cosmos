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

require 'openc3/topics/topic'
require 'openc3/utilities/store_queued'

module OpenC3
  class CommandDecomTopic < Topic
    def self.write_packet(packet, scope:)
      topic = "#{scope}__DECOMCMD__{#{packet.target_name}}__#{packet.packet_name}"
      msg_hash = { time: packet.packet_time.to_nsec_from_epoch,
                   received_time: packet.received_time.to_nsec_from_epoch,
                   target_name: packet.target_name,
                   packet_name: packet.packet_name,
                   stored: packet.stored.to_s,
                   received_count: packet.received_count }
      # Read all RAW values at once - optimized by accessor
      json_hash = packet.read_items(packet.sorted_items)
      # Items with a write conversion have already been transformed by the time the
      # value lands in the buffer, so reading the buffer back does not recover what
      # the user actually commanded. Use the given values (as passed to build_cmd)
      # for those items. Raw commands bypass the write conversions entirely so their
      # given values are raw and must not be logged as converted.
      given_values = packet.raw ? nil : packet.given_values
      given_values = given_values.transform_keys { |key| key.to_s.upcase } if given_values
      # Read additional value types using given_raw to avoid re-reading from buffer
      packet.sorted_items.each do |item|
        if item.hidden
          json_hash.delete(item.name)
        else
          given_raw = json_hash[item.name]
          if item.write_conversion or item.states
            if item.write_conversion and given_values and given_values.key?(item.name)
              json_hash[item.name + "__C"] = given_values[item.name]
            else
              json_hash[item.name + "__C"] = packet.read_item(item, :CONVERTED, packet.buffer, given_raw)
            end
          end
          json_hash[item.name + "__F"] = packet.read_item(item, :FORMATTED, packet.buffer, given_raw) if item.format_string
        end
      end
      msg_hash['json_data'] = JSON.generate(json_hash.as_json, allow_nan: true)
      msg_hash['extra'] = JSON.generate(packet.extra.as_json, allow_nan: true) if packet.extra
      db_shard = Store.db_shard_for_target(packet.target_name, scope: scope)
      EphemeralStoreQueued.instance(db_shard: db_shard).write_topic(topic, msg_hash)
    end

    def self.get_cmd_item(target_name, packet_name, param_name, type: :FORMATTED, scope: $openc3_scope)
      db_shard = Store.db_shard_for_target(target_name, scope: scope)
      msg_id, msg_hash = Topic.get_newest_message("#{scope}__DECOMCMD__{#{target_name}}__#{packet_name}", db_shard: db_shard)
      if msg_id
        if param_name == 'RECEIVED_COUNT'
          msg_hash['received_count'].to_i
        else
          json = msg_hash['json_data']
          hash = JSON.parse(json, allow_nan: true, create_additions: true)
          # Start from the most complex down to the basic raw value
          value = hash["#{param_name}__F"]
          return value if value && (type == :WITH_UNITS || type == :FORMATTED)

          value = hash["#{param_name}__C"]
          return value if value && (type == :WITH_UNITS || type == :FORMATTED || type == :CONVERTED)

          return hash[param_name]
        end
      end
    end
  end
end
