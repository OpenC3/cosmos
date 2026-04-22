# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/system/system'
require 'openc3/microservices/interface_microservice'
require 'openc3/topics/telemetry_decom_topic'
require 'openc3/models/target_model'

module OpenC3
  # Shared decom pipeline used by DecomMicroservice (live telemetry) and
  # ReingestJob (historical raw log replay). The reingest path passes
  # check_limits: false so historical data does not re-fire limits events.
  module DecomCommon
    module_function

    # Decommutate a Packet and publish it on the TelemetryDecomTopic. This is the
    # step that lands data in the CVT and in the Python TsdbMicroservice → QuestDB.
    #
    # @param packet [Packet] A fully buffered Packet. Caller sets received_time,
    #   received_count, stored, extra, buffer.
    # @param scope [String] Scope name.
    # @param target_names [Array<String>] Used when a subpacket must be re-identified.
    # @param logger [Logger] Destination for warnings.
    # @param name [String] Identifier used in subpacket warning messages
    #   (microservice name, or "REINGEST:<job_id>").
    # @param check_limits [Boolean] When false, skips the Packet#check_limits call.
    #   Reingest passes false so historical data does not re-fire limits events.
    # @param metric [Metric, nil] Optional; when set, records decom_duration_seconds.
    # @param error_callback [Proc, nil] Called as error_callback.call(exception) when
    #   Packet#process or Packet#check_limits raises. The microservice uses this to
    #   bump its decom_error_total metric.
    # @return [Integer] Number of (sub)packets published.
    def decom_and_publish(packet, scope:, target_names:, logger:, name:,
                          check_limits: true, metric: nil, error_callback: nil)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC) if metric
      published = 0

      packet_and_subpackets = packet.subpacketize
      packet_and_subpackets.each do |packet_or_subpacket|
        if packet_or_subpacket.subpacket
          packet_or_subpacket = handle_subpacket(packet, packet_or_subpacket,
                                                 target_names: target_names,
                                                 scope: scope,
                                                 logger: logger,
                                                 name: name)
        end

        begin
          packet_or_subpacket.process
        rescue Exception => e
          error_callback&.call(e)
          logger.error e.message
        end

        packet_or_subpacket.check_limits(System.limits_set) if check_limits

        TelemetryDecomTopic.write_packet(packet_or_subpacket, scope: scope)
        published += 1
      end

      if metric
        diff = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        metric.set(name: 'decom_duration_seconds', value: diff, type: 'gauge', unit: 'seconds')
      end

      published
    end

    # Identify a subpacket and (except for stored telemetry) update the CVT.
    # Extracted from DecomMicroservice so reingest can handle subpackets too.
    def handle_subpacket(packet, subpacket, target_names:, scope:, logger:, name:)
      subpacket.received_time = packet.received_time
      subpacket.stored = packet.stored
      subpacket.extra = packet.extra

      if subpacket.stored
        identified_subpacket = System.telemetry.identify_and_define_packet(subpacket, target_names, subpackets: true)
      else
        if subpacket.identified?
          begin
            identified_subpacket = System.telemetry.update!(subpacket.target_name,
                                                            subpacket.packet_name,
                                                            subpacket.buffer)
          rescue RuntimeError
            logger.warn "#{name}: Received unknown identified subpacket: #{subpacket.target_name} #{subpacket.packet_name}"
            subpacket.target_name = nil
            subpacket.packet_name = nil
            identified_subpacket = System.telemetry.identify!(subpacket.buffer,
                                                              target_names, subpackets: true)
          end
        else
          identified_subpacket = System.telemetry.identify!(subpacket.buffer,
                                                            target_names, subpackets: true)
        end
      end

      if identified_subpacket
        identified_subpacket.received_time = subpacket.received_time
        identified_subpacket.stored = subpacket.stored
        identified_subpacket.extra = subpacket.extra
        subpacket = identified_subpacket
      else
        unknown_subpacket = System.telemetry.update!('UNKNOWN', 'UNKNOWN', subpacket.buffer)
        unknown_subpacket.received_time = subpacket.received_time
        unknown_subpacket.stored = subpacket.stored
        unknown_subpacket.extra = subpacket.extra
        subpacket = unknown_subpacket
        num_bytes_to_print = [InterfaceMicroservice::UNKNOWN_BYTES_TO_PRINT, subpacket.length].min
        data = subpacket.buffer(false)[0..(num_bytes_to_print - 1)]
        prefix = data.each_byte.map { |byte| sprintf("%02X", byte) }.join()
        logger.warn "#{name} #{subpacket.target_name} packet length: #{subpacket.length} starting with: #{prefix}"
      end

      TargetModel.sync_tlm_packet_counts(subpacket, target_names, scope: scope)
      subpacket
    end
  end
end
