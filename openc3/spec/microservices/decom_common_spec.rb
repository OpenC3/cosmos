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

require 'spec_helper'
require 'openc3/microservices/decom_common'
require 'openc3/topics/telemetry_decom_topic'
require 'openc3/topics/limits_event_topic'

module OpenC3
  describe DecomCommon do
    before(:each) do
      mock_redis()
      setup_system()
      model = TargetModel.new(folder_name: 'INST', name: 'INST', scope: 'DEFAULT')
      model.create
      model.update_store(System.new(['INST'], File.join(SPEC_DIR, 'install', 'config', 'targets')))
      System.telemetry.limits_change_callback = proc { |*_args| }
    end

    def build_packet
      packet = System.telemetry.packet('INST', 'HEALTH_STATUS')
      packet.extra = nil
      packet.received_time = Time.now.sys
      packet
    end

    describe '.decom_and_publish' do
      it 'publishes to TelemetryDecomTopic and calls Packet#check_limits when check_limits: true' do
        packet = build_packet
        allow(TelemetryDecomTopic).to receive(:write_packet)
        subpackets = packet.subpacketize
        allow(packet).to receive(:subpacketize).and_return(subpackets)
        subpackets.each { |p| expect(p).to receive(:check_limits).with(System.limits_set) }

        published = DecomCommon.decom_and_publish(
          packet,
          scope: 'DEFAULT',
          target_names: ['INST'],
          logger: Logger.new,
          name: 'TEST',
          check_limits: true,
        )

        expect(published).to eq(subpackets.length)
        expect(TelemetryDecomTopic).to have_received(:write_packet).exactly(subpackets.length).times
      end

      it 'skips Packet#check_limits when check_limits: false' do
        packet = build_packet
        allow(TelemetryDecomTopic).to receive(:write_packet)
        subpackets = packet.subpacketize
        allow(packet).to receive(:subpacketize).and_return(subpackets)
        subpackets.each { |p| expect(p).not_to receive(:check_limits) }

        DecomCommon.decom_and_publish(
          packet,
          scope: 'DEFAULT',
          target_names: ['INST'],
          logger: Logger.new,
          name: 'TEST',
          check_limits: false,
        )
      end

      it 'invokes error_callback when Packet#process raises' do
        packet = build_packet
        processor = double(Processor).as_null_object
        expect(processor).to receive(:call).and_raise('bad processor')
        packet.processors['BAD'] = processor
        allow(TelemetryDecomTopic).to receive(:write_packet)

        captured = []
        DecomCommon.decom_and_publish(
          packet,
          scope: 'DEFAULT',
          target_names: ['INST'],
          logger: Logger.new,
          name: 'TEST',
          check_limits: false,
          error_callback: ->(e) { captured << e },
        )

        expect(captured.size).to eq(1)
        expect(captured.first.message).to eql('bad processor')
      end

      it 'routes subpackets through handle_subpacket' do
        parent = build_packet
        subpacket = build_packet
        allow(subpacket).to receive(:subpacket).and_return(true)
        allow(parent).to receive(:subpacketize).and_return([parent, subpacket])
        allow(TelemetryDecomTopic).to receive(:write_packet)

        # handle_subpacket calls TargetModel.sync_tlm_packet_counts as its last
        # step — observing it confirms the subpacket branch was taken.
        allow(System.telemetry).to receive(:identify_and_define_packet).and_return(subpacket)
        expect(TargetModel).to receive(:sync_tlm_packet_counts).at_least(:once)

        subpacket.stored = true
        DecomCommon.decom_and_publish(
          parent,
          scope: 'DEFAULT',
          target_names: ['INST'],
          logger: Logger.new,
          name: 'TEST',
          check_limits: false,
        )
      end

      it 'records decom_duration_seconds on the metric when provided' do
        packet = build_packet
        allow(TelemetryDecomTopic).to receive(:write_packet)
        metric = double('Metric')
        expect(metric).to receive(:set).with(hash_including(name: 'decom_duration_seconds'))

        DecomCommon.decom_and_publish(
          packet,
          scope: 'DEFAULT',
          target_names: ['INST'],
          logger: Logger.new,
          name: 'TEST',
          check_limits: false,
          metric: metric,
        )
      end
    end

    describe '.handle_subpacket' do
      let(:logger) { Logger.new }
      let(:parent) do
        p = System.telemetry.packet('INST', 'HEALTH_STATUS')
        p.received_time = Time.now.sys
        p.stored = false
        p.extra = nil
        p
      end
      let(:subpacket) do
        # Build a bare subpacket object. We stub all behavior so we control
        # the branch taken in handle_subpacket.
        sp = System.telemetry.packet('INST', 'HEALTH_STATUS').dup
        sp
      end

      before(:each) do
        allow(TargetModel).to receive(:sync_tlm_packet_counts)
      end

      # NOTE: handle_subpacket copies parent.stored onto subpacket.stored
      # before branching, so the "stored" toggle belongs on the parent.

      it 'follows the stored path (identify_and_define_packet)' do
        parent.stored = true
        expect(System.telemetry).to receive(:identify_and_define_packet).and_return(subpacket)
        expect(TargetModel).to receive(:sync_tlm_packet_counts)
        DecomCommon.handle_subpacket(parent, subpacket,
                                     target_names: ['INST'], scope: 'DEFAULT',
                                     logger: logger, name: 'TEST')
      end

      it 'warns and falls back to identify! when a pre-identified subpacket is unknown' do
        parent.stored = false
        allow(subpacket).to receive(:identified?).and_return(true)
        allow(System.telemetry).to receive(:update!).and_raise(RuntimeError, 'unknown')
        expect(System.telemetry).to receive(:identify!).and_return(subpacket)
        expect(logger).to receive(:warn).with(/Received unknown identified subpacket/)

        DecomCommon.handle_subpacket(parent, subpacket,
                                     target_names: ['INST'], scope: 'DEFAULT',
                                     logger: logger, name: 'TEST')
      end

      it 'takes the unidentified branch when identified? is false' do
        parent.stored = false
        allow(subpacket).to receive(:identified?).and_return(false)
        expect(System.telemetry).to receive(:identify!).and_return(subpacket)

        DecomCommon.handle_subpacket(parent, subpacket,
                                     target_names: ['INST'], scope: 'DEFAULT',
                                     logger: logger, name: 'TEST')
      end

      it 'falls back to UNKNOWN packet and warns when identification returns nil' do
        parent.stored = false
        allow(subpacket).to receive(:identified?).and_return(false)
        allow(System.telemetry).to receive(:identify!).and_return(nil)
        unknown = System.telemetry.packet('INST', 'HEALTH_STATUS').dup
        allow(unknown).to receive(:length).and_return(4)
        allow(unknown).to receive(:target_name).and_return('UNKNOWN')
        expect(System.telemetry).to receive(:update!).and_return(unknown)
        expect(logger).to receive(:warn).with(/packet length:/)

        result = DecomCommon.handle_subpacket(parent, subpacket,
                                              target_names: ['INST'], scope: 'DEFAULT',
                                              logger: logger, name: 'TEST')
        expect(result).to equal(unknown)
      end
    end
  end
end
