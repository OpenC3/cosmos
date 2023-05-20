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

require 'openc3/microservices/microservice'
require 'openc3/microservices/interface_decom_common'
require 'openc3/topics/telemetry_decom_topic'
require 'openc3/topics/limits_event_topic'
require 'openc3/topics/notifications_topic'
require 'openc3/models/notification_model'

module OpenC3
  class DecomMicroservice < Microservice
    include InterfaceDecomCommon

    def initialize(*args)
      super(*args)
      # Should only be one target, but there might be multiple decom microservices for a given target
      # First Decom microservice has no number in the name
      if @name =~ /__DECOM__/
        @topics << "#{scope}__DECOMINTERFACE__{#{@target_names[0]}}"
      end
      Topic.update_topic_offsets(@topics)
      System.telemetry.limits_change_callback = method(:limits_change_callback)
      LimitsEventTopic.sync_system(scope: @scope)
      @error_count = 0
      @metric.set(name: 'decom_total', value: @count, type: 'counter')
      @metric.set(name: 'decom_error_total', value: @error_count, type: 'counter')
    end

    def run
      while true
        break if @cancel_thread

        begin
          OpenC3.in_span("read_topics") do
            Topic.read_topics(@topics) do |topic, msg_id, msg_hash, redis|
              break if @cancel_thread

              if topic =~ /__DECOMINTERFACE/
                if msg_hash.key?('inject_tlm')
                  handle_inject_tlm(msg_hash['inject_tlm'])
                  next
                end
                if msg_hash.key?('build_cmd')
                  handle_build_cmd(msg_hash['build_cmd'])
                  next
                end
              else
                decom_packet(topic, msg_id, msg_hash, redis)
                @metric.set(name: 'decom_total', value: @count, type: 'counter')
              end
              @count += 1
            end
          end
          LimitsEventTopic.sync_system_thread_body(scope: @scope)
        rescue => e
          @error_count += 1
          @metric.set(name: 'decom_error_total', value: @error_count, type: 'counter')
          @error = e
          @logger.error("Decom error: #{e.formatted}")
        end
      end
    end

    def decom_packet(topic, msg_id, msg_hash, _redis)
      OpenC3.in_span("decom_packet") do
        msgid_seconds_from_epoch = msg_id.split('-')[0].to_i / 1000.0
        delta = Time.now.to_f - msgid_seconds_from_epoch
        @metric.set(name: 'decom_topic_delta_seconds', value: delta, type: 'gauge', unit: 'seconds', help: 'Delta time between data written to stream and decom start')

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        target_name = msg_hash["target_name"]
        packet_name = msg_hash["packet_name"]

        packet = System.telemetry.packet(target_name, packet_name)
        packet.stored = ConfigParser.handle_true_false(msg_hash["stored"])
        packet.received_time = Time.from_nsec_from_epoch(msg_hash["received_time"].to_i)
        packet.received_count = msg_hash["received_count"].to_i
        packet.buffer = msg_hash["buffer"]
        packet.check_limits(System.limits_set) # Process all the limits and call the limits_change_callback (as necessary)

        TelemetryDecomTopic.write_packet(packet, scope: @scope)
        diff = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start # seconds as a float
        @metric.set(name: 'decom_duration_seconds', value: diff, type: 'gauge', unit: 'seconds')
      end
    end

    # Called when an item in any packet changes limits states.
    #
    # @param packet [Packet] Packet which has had an item change limits state
    # @param item [PacketItem] The item which has changed limits state
    # @param old_limits_state [Symbol] The previous state of the item. See
    #   {PacketItemLimits#state}
    # @param value [Object] The current value of the item
    # @param log_change [Boolean] Whether to log this limits change event
    def limits_change_callback(packet, item, old_limits_state, value, log_change)
      return if @cancel_thread
      packet_time = packet.packet_time
      message = "#{packet.target_name} #{packet.packet_name} #{item.name} = #{value} is #{item.limits.state}"
      message << " (#{packet.packet_time.sys.formatted})" if packet_time

      time_nsec = packet_time ? packet_time.to_nsec_from_epoch : Time.now.to_nsec_from_epoch
      if log_change
        case item.limits.state
        when :BLUE, :GREEN, :GREEN_LOW, :GREEN_HIGH
          @logger.info message
        when :YELLOW, :YELLOW_LOW, :YELLOW_HIGH
          @logger.warn message
        when :RED, :RED_LOW, :RED_HIGH
          notification = NotificationModel.new(
            time: time_nsec,
            severity: "critical",
            url: "/tools/limitsmonitor",
            title: "#{packet.target_name} #{packet.packet_name} #{item.name} out of limits",
            body: "Item went into #{item.limits.state} limit status."
          )
          NotificationsTopic.write_notification(notification.as_json(:allow_nan => true), scope: @scope)
          @logger.error message
        end
      end

      # The openc3_limits_events topic can be listened to for all limits events, it is a continuous stream
      event = { type: :LIMITS_CHANGE, target_name: packet.target_name, packet_name: packet.packet_name,
                item_name: item.name, old_limits_state: old_limits_state.to_s, new_limits_state: item.limits.state.to_s,
                time_nsec: time_nsec, message: message.to_s }
      LimitsEventTopic.write(event, scope: @scope)

      if item.limits.response
        begin
          item.limits.response.call(packet, item, old_limits_state)
        rescue Exception => e
          @error = e
          @logger.error "#{packet.target_name} #{packet.packet_name} #{item.name} Limits Response Exception!"
          @logger.error "Called with old_state = #{old_limits_state}, new_state = #{item.limits.state}"
          @logger.error e.formatted
        end
      end
    end
  end
end

OpenC3::DecomMicroservice.run if __FILE__ == $0
