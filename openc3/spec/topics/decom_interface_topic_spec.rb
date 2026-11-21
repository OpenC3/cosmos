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
require 'openc3/topics/decom_interface_topic'

module OpenC3
  describe DecomInterfaceTopic do
    before(:each) do
      mock_redis()
      allow(Topic).to receive(:write_topic).and_return('decom_id')
      allow(Topic).to receive(:update_topic_offsets)
      msg_hash = { 'id' => 'decom_id', 'result' => "Required command parameter 'INST COLLECT TYPE' not given" }
      allow(Topic).to receive(:read_topics).and_yield('ack_topic', 'msg_id', msg_hash, 'redis')
    end

    # The error happened in the decom microservice so the API shouldn't log
    # a backtrace of the ack loop
    it "raises errors from build_cmd without a backtrace" do
      expect {
        DecomInterfaceTopic.build_cmd('INST', 'COLLECT', {}, true, false, scope: 'DEFAULT')
      }.to raise_error(RuntimeError, "Required command parameter 'INST COLLECT TYPE' not given") do |error|
        expect(error.backtrace).to eql []
      end
    end

    it "raises errors from inject_tlm and get_tlm_buffer without a backtrace" do
      expect {
        DecomInterfaceTopic.inject_tlm('INST', 'HEALTH_STATUS', { 'TEMP1' => 1 }, scope: 'DEFAULT')
      }.to raise_error(RuntimeError) { |error| expect(error.backtrace).to eql [] }
      expect {
        DecomInterfaceTopic.get_tlm_buffer('INST', 'HEALTH_STATUS', scope: 'DEFAULT')
      }.to raise_error(RuntimeError) { |error| expect(error.backtrace).to eql [] }
    end
  end
end
