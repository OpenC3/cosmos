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
require 'openc3/topics/router_topic'
require 'openc3/packets/packet'

module OpenC3
  describe RouterTopic do
    before(:each) do
      mock_redis()
    end

    describe "route_command" do
      it "routes an identified command to its target" do
        packet = Packet.new("INST", "ABORT")
        packet.buffer = "\x01\x02"
        expect(Topic).to receive(:write_topic).with("{DEFAULT__CMD}TARGET__INST",
          { 'target_name' => 'INST', 'cmd_name' => 'ABORT', 'cmd_buffer' => "\x01\x02" }, '*', 100)
        RouterTopic.route_command(packet, ["INST", "INST2"], scope: "DEFAULT")
      end

      it "routes an unidentified command to the only target, naming that target" do
        packet = Packet.new(nil, nil)
        packet.buffer = "\x01\x02"
        expect(Topic).to receive(:write_topic).with("{DEFAULT__CMD}TARGET__INST",
          { 'target_name' => 'INST', 'cmd_name' => 'UNKNOWN', 'cmd_buffer' => "\x01\x02" }, '*', 100)
        RouterTopic.route_command(packet, ["INST"], scope: "DEFAULT")
      end

      it "raises if an unidentified command has more than one possible target" do
        packet = Packet.new(nil, nil)
        packet.buffer = "\x01\x02"
        expect { RouterTopic.route_command(packet, ["INST", "INST2"], scope: "DEFAULT") }.to raise_error(/No route for command/)
      end
    end
  end
end
