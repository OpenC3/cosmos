# encoding: ascii-8bit

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

require 'openc3/topics/topic'

module OpenC3
  class DecomInterfaceTopic < Topic
    def self.build_cmd(target_name, cmd_name, cmd_params, range_check, raw, scope:)
      data = {}
      data['target_name'] = target_name.to_s.upcase
      data['cmd_name'] = cmd_name.to_s.upcase
      data['cmd_params'] = cmd_params
      data['range_check'] = range_check
      data['raw'] = raw
      # DecomMicroservice is listening to the DECOMINTERFACE topic and is responsible
      # for actually building the command. This was deliberate to allow this to work
      # with or without an interface.
      decom_id = Topic.write_topic("#{scope}__DECOMINTERFACE__{#{target_name}}",
          { 'build_cmd' => JSON.generate(data, allow_nan: true) }, '*', 100)
      timeout = 5 # Arbitrary 5s timeout
      ack_topic = "{#{scope}__ACKCMD}TARGET__#{target_name}"
      time = Time.now
      while (Time.now - time) < timeout
        Topic.read_topics([ack_topic]) do |topic, msg_id, msg_hash, redis|
          if msg_hash["id"] == decom_id
            if msg_hash["result"] == "SUCCESS"
              return msg_hash
            else
              raise msg_hash["message"]
            end
          end
        end
      end
      raise "Timeout of #{timeout}s waiting for cmd ack. Does target '#{target_name}' exist?"
    end

    def self.inject_tlm(target_name, packet_name, item_hash = nil, type: :CONVERTED, scope:)
      data = {}
      data['target_name'] = target_name.to_s.upcase
      data['packet_name'] = packet_name.to_s.upcase
      data['item_hash'] = item_hash
      data['type'] = type
      Topic.write_topic("#{scope}__DECOMINTERFACE__{#{target_name}}",
          { 'inject_tlm' => JSON.generate(data, allow_nan: true) }, '*', 100)
    end
  end
end
