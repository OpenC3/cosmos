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

require 'time'
require 'thread'
require 'openc3/microservices/microservice'
require 'openc3/microservices/interface_decom_common'
require 'openc3/topics/telemetry_decom_topic'
require 'openc3/topics/limits_event_topic'

module OpenC3
  class LimitsResponseThread
    def initialize(microservice_name:, queue:, logger:, metric:, scope:)
      @microservice_name = microservice_name
      @queue = queue
      @logger = logger
      @metric = metric
      @scope = scope
      @count = 0
      @error_count = 0
      @metric.set(name: 'limits_response_total', value: @count, type: 'counter')
      @metric.set(name: 'limits_response_error_total', value: @error_count, type: 'counter')
    end

    def start
      @thread = Thread.new do
        run()
      rescue Exception => e
        @logger.error "#{@microservice_name}: Limits Response thread died: #{e.formatted}"
        raise e
      end
      ThreadManager.instance.register(@thread, stop_object: self)
    end

    def stop
      if @thread
        OpenC3.kill_thread(self, @thread)
        @thread = nil
      end
    end

    def graceful_kill
      @queue << [nil, nil, nil]
    end

    def run
      while true
        packet, item, old_limits_state = @queue.pop()
        break if packet.nil?

        begin
          item.limits.response.call(packet, item, old_limits_state)
        rescue Exception => e
          @error_count += 1
          @metric.set(name: 'limits_response_error_total', value: @error_count, type: 'counter')
          @logger.error "#{packet.target_name} #{packet.packet_name} #{item.name} Limits Response Exception!"
          @logger.error "Called with old_state = #{old_limits_state}, new_state = #{item.limits.state}"
          @logger.error e.filtered
        end

        @count += 1
        @metric.set(name: 'limits_response_total', value: @count, type: 'counter')
      end
    end
  end

  class DecomMicroservice < Microservice
    include InterfaceDecomCommon
    LIMITS_STATE_INDEX = { RED_LOW: 0, YELLOW_LOW: 1, YELLOW_HIGH: 2, RED_HIGH: 3, GREEN_LOW: 4, GREEN_HIGH: 5 }

    def initialize(*args)
      super(*args)
      # Should only be one target, but there might be multiple decom microservices for a given target
      # First Decom microservice has no number in the name
      if @name =~ /__DECOM__/
        @topics << "#{@scope}__DECOMINTERFACE__{#{@target_names[0]}}"
      end
      Topic.update_topic_offsets(@topics)
      System.telemetry.limits_change_callback = method(:limits_change_callback)
      LimitsEventTopic.sync_system(scope: @scope)
      @error_count = 0
      @metric.set(name: 'decom_total', value: @count, type: 'counter')
      @metric.set(name: 'decom_error_total', value: @error_count, type: 'counter')
      @limits_response_queue = Queue.new
      @limits_response_thread = nil
    end

    def run
      @limits_response_thread = LimitsResponseThread.new(microservice_name: @name, queue: @limits_response_queue, logger: @logger, metric: @metric, scope: @scope)
      @limits_response_thread.start()

      setup_microservice_topic()
      while true
        break if @cancel_thread

        begin
          OpenC3.in_span("read_topics") do
            Topic.read_topics(@topics) do |topic, msg_id, msg_hash, redis|
              break if @cancel_thread
              if topic == @microservice_topic
                microservice_cmd(topic, msg_id, msg_hash, redis)
              elsif topic =~ /__DECOMINTERFACE/
                if msg_hash.key?('inject_tlm')
                  handle_inject_tlm(msg_hash['inject_tlm'])
                  next
                end
                if msg_hash.key?('build_cmd')
                  handle_build_cmd(msg_hash['build_cmd'], msg_id)
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

      @limits_response_thread.stop()
      @limits_response_thread = nil
    end

    def decom_packet(_topic, msg_id, msg_hash, _redis)
      OpenC3.in_span("decom_packet") do
        msgid_seconds_from_epoch = msg_id.split('-')[0].to_i / 1000.0
        delta = Time.now.to_f - msgid_seconds_from_epoch
        @metric.set(name: 'decom_topic_delta_seconds', value: delta, type: 'gauge', unit: 'seconds', help: 'Delta time between data written to stream and decom start')

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        target_name = msg_hash["target_name"]
        packet_name = msg_hash["packet_name"]

        packet = System.telemetry.packet(target_name, packet_name)
        packet.stored = ConfigParser.handle_true_false(msg_hash["stored"])
        # Note: Packet time will be recalculated as part of decom so not setting
        packet.received_time = Time.from_nsec_from_epoch(msg_hash["received_time"].to_i)
        packet.received_count = msg_hash["received_count"].to_i
        extra = msg_hash["extra"]
        if extra and extra.length > 0
          extra = JSON.parse(extra, allow_nan: true, create_additions: true)
          packet.extra = extra
        end
        packet.buffer = msg_hash["buffer"]
        # Processors are user code points which must be rescued
        # so the TelemetryDecomTopic can write the packet
        begin
          packet.process # Run processors
        rescue Exception => e
          @error_count += 1
          @metric.set(name: 'decom_error_total', value: @error_count, type: 'counter')
          @error = e
          @logger.error e.message
        end
        # Process all the limits and call the limits_change_callback (as necessary)
        # check_limits also can call user code in the limits response
        # but that is rescued separately in the limits_change_callback
        packet.check_limits(System.limits_set)

        # This is what actually decommutates the packet and updates the CVT
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
      # Make a copy because packet_time is frozen
      packet_time = packet.packet_time.dup
      if value
        message = "#{packet.target_name} #{packet.packet_name} #{item.name} = #{value} is #{item.limits.state}"
        if item.limits.values
          values = item.limits.values[System.limits_set]
          # Check if the state is RED_LOW, YELLOW_LOW, YELLOW_HIGH, RED_HIGH, GREEN_LOW, GREEN_HIGH
          if LIMITS_STATE_INDEX[item.limits.state]
            # Directly index into the values and return the value
            message += " (#{values[LIMITS_STATE_INDEX[item.limits.state]]})"
          elsif item.limits.state == :GREEN
            # If we're green we display the green range (YELLOW_LOW - YELLOW_HIGH)
            message += " (#{values[1]} to #{values[2]})"
          elsif item.limits.state == :BLUE
            # If we're blue we display the blue range (GREEN_LOW - GREEN_HIGH)
            message += " (#{values[4]} to #{values[5]})"
          end
        end
      else
        message = "#{packet.target_name} #{packet.packet_name} #{item.name} is disabled"
      end

      # Include the packet_time in the log json but not the log message
      time = { packet_time: packet_time.utc.iso8601(6) }
      if log_change
        case item.limits.state
        when :BLUE, :GREEN, :GREEN_LOW, :GREEN_HIGH
          # Only print INFO messages if we're changing ... not on initialization
          @logger.info(message, other: time) if old_limits_state
        when :YELLOW, :YELLOW_LOW, :YELLOW_HIGH
          @logger.warn(message, other: time, type: Logger::NOTIFICATION)
        when :RED, :RED_LOW, :RED_HIGH
          @logger.error(message, other: time, type: Logger::ALERT)
        end
      end

      # The openc3_limits_events topic can be listened to for all limits events, it is a continuous stream
      event = { type: :LIMITS_CHANGE, target_name: packet.target_name, packet_name: packet.packet_name,
                item_name: item.name, old_limits_state: old_limits_state.to_s, new_limits_state: item.limits.state.to_s,
                time_nsec: packet_time.to_nsec_from_epoch, message: message.to_s }
      LimitsEventTopic.write(event, scope: @scope)

      if item.limits.response
        copied_packet = packet.deep_copy
        copied_item = packet.items[item.name]
        @limits_response_queue << [copied_packet, copied_item, old_limits_state]
      end
    end
  end
end

if __FILE__ == $0
  OpenC3::DecomMicroservice.run
  ThreadManager.instance.shutdown
  ThreadManager.instance.join
end