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
require 'openc3/microservices/interface_decom_common'

module OpenC3
  describe InterfaceDecomCommon do
    class InjectTlmReceivedTimeHarness
      include InterfaceDecomCommon

      def initialize
        @scope = 'DEFAULT'
      end
    end

    before(:each) do
      @handler = InjectTlmReceivedTimeHarness.new
      @telemetry = double('Telemetry')
      @packet = double('Packet', target_name: 'INST', packet_name: 'HEALTH_STATUS')
      allow(@packet).to receive(:write)
      allow(@packet).to receive(:stored=)
      allow(@packet).to receive(:received_count=)
      allow(System).to receive(:telemetry).and_return(@telemetry)
      allow(@telemetry).to receive(:packet).with('INST', 'HEALTH_STATUS').and_return(@packet)
      allow(TargetModel).to receive(:increment_telemetry_count).and_return(1)
      allow(TelemetryTopic).to receive(:write_packet)
    end

    def inject(received_time)
      @handler.handle_inject_tlm(JSON.generate({
        'target_name' => 'INST',
        'packet_name' => 'HEALTH_STATUS',
        'item_hash' => nil,
        'type' => 'CONVERTED',
        'stored' => false,
        'received_time' => received_time
      }, allow_nan: true))
    end

    it 'uses a supplied received time in nanoseconds since Unix epoch' do
      received_time = 1_609_459_200_123_456_000
      expect(@packet).to receive(:received_time=).with(Time.from_nsec_from_epoch(received_time).sys)

      inject(received_time)
    end

    it 'preserves Unix epoch zero as a supplied received time' do
      expect(@packet).to receive(:received_time=).with(Time.from_nsec_from_epoch(0).sys)

      inject(0)
    end
  end
end
