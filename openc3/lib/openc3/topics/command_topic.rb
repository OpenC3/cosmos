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

require 'openc3/topics/topic'
require 'openc3/utilities/store_queued'
require 'openc3/utilities/open_telemetry'

module OpenC3
  class CommandTopic < Topic
    COMMAND_ACK_TIMEOUT_S = 30

    def self.write_packet(packet, scope:)
      topic = "#{scope}__COMMAND__{#{packet.target_name}}__#{packet.packet_name}"
      msg_hash = { time: packet.packet_time.to_nsec_from_epoch,
                   received_time: packet.received_time.to_nsec_from_epoch,
                   target_name: packet.target_name,
                   packet_name: packet.packet_name,
                   received_count: packet.received_count,
                   stored: packet.stored.to_s,
                   buffer: packet.buffer(false) }
      EphemeralStoreQueued.write_topic(topic, msg_hash)
    end

    # @param command [Hash] Command hash structure read to be written to a topic
    def self.send_command(command, timeout: COMMAND_ACK_TIMEOUT_S, scope:, obfuscated_items: [])
      timeout = COMMAND_ACK_TIMEOUT_S unless timeout
      ack_topic = "{#{scope}__ACKCMD}TARGET__#{command['target_name']}"
      Topic.update_topic_offsets([ack_topic])
      # Save the existing cmd_params Hash and JSON generate before writing to the topic
      cmd_params = command['cmd_params']
      command['cmd_params'] = JSON.generate(command['cmd_params'].as_json(:allow_nan => true))
      OpenC3.inject_context(command)
      cmd_id = Topic.write_topic("{#{scope}__CMD}TARGET__#{command['target_name']}", command, '*', 100)
      command["cmd_params"] = cmd_params # Restore the original cmd_params Hash
      time = Time.now
      while (Time.now - time) < timeout
        Topic.read_topics([ack_topic]) do |_topic, _msg_id, msg_hash, _redis|
          if msg_hash["id"] == cmd_id
            if msg_hash["result"] == "SUCCESS"
              return command
            # Check for HazardousError which is a special case
            elsif msg_hash["result"].include?("HazardousError")
              raise_hazardous_error(msg_hash, command)
            elsif msg_hash["result"].include?("CriticalCmdError")
              raise_critical_cmd_error(msg_hash, command)
            else
              raise msg_hash["result"]
            end
          end
        end
      end
      raise "Timeout of #{timeout}s waiting for cmd ack"
    end

    ###########################################################################
    # PRIVATE implementation details
    ###########################################################################

    def self.raise_hazardous_error(msg_hash, command)
      _, description, formatted = msg_hash["result"].split("\n")
      # Create and populate a new HazardousError and raise it up
      # The _cmd method in script/commands.rb rescues this and calls prompt_for_hazardous
      error = HazardousError.new
      error.target_name = command["target_name"]
      error.cmd_name = command["cmd_name"]
      error.cmd_params = command["cmd_params"]
      error.hazardous_description = description
      error.formatted = formatted

      # No Logger.info because the error is already logged by the Logger.info "Ack Received ...
      raise error
    end

    def self.raise_critical_cmd_error(msg_hash, command)
      _, uuid = msg_hash["result"].split("\n")
      # Create and populate a new CriticalCmdError and raise it up
      # The _cmd method in script/commands.rb rescues this and calls prompt_for_critical_cmd
      error = CriticalCmdError.new
      error.uuid = uuid
      error.command = command
      raise error
    end
  end
end
