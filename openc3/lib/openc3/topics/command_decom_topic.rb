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
      # Read additional value types using given_raw to avoid re-reading from buffer
      packet.sorted_items.each do |item|
        if item.hidden
          json_hash.delete(item.name)
        else
          given_raw = json_hash[item.name]
          json_hash[item.name + "__C"] = packet.read_item(item, :CONVERTED, packet.buffer, given_raw) if item.write_conversion or item.states
          json_hash[item.name + "__F"] = packet.read_item(item, :FORMATTED, packet.buffer, given_raw) if item.format_string
        end
      end
      msg_hash['json_data'] = JSON.generate(json_hash.as_json, allow_nan: true)
      msg_hash['extra'] = JSON.generate(packet.extra.as_json, allow_nan: true) if packet.extra
      EphemeralStoreQueued.write_topic(topic, msg_hash)
    end

    def self.get_cmd_item(target_name, packet_name, param_name, type: :FORMATTED, scope: $openc3_scope)
      msg_id, msg_hash = Topic.get_newest_message("#{scope}__DECOMCMD__{#{target_name}}__#{packet_name}")
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
