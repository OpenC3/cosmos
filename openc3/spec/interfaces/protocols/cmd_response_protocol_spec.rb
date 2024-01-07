# encoding: ascii-8bit

# Copyright 2024 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3'
require 'openc3/accessors/template_accessor'
require 'openc3/interfaces/protocols/cmd_response_protocol'
require 'openc3/interfaces/interface'
require 'openc3/streams/stream'
require 'openc3/utilities/logger'
require 'openc3/packets/packet_config'
require 'openc3/packets/telemetry'

module OpenC3
  describe CmdResponseProtocol do
    class CmdResponseStream < Stream
      def connect; end

      def connected?; true; end

      def disconnect; end

      def read_nonblock; []; end

      def write(buffer) $write_buffer = buffer; end

      def read; $read_buffer; end
    end

    before(:each) do
      @interface = StreamInterface.new
      allow(@interface).to receive(:connected?) { true }
      $write_buffer = ''
      $read_buffer = ''
      $read_cnt = 0
    end

    describe "disconnect" do
      it "unblocks writes waiting for responses" do
        @interface.instance_variable_set(:@stream, CmdResponseStream.new)
        @interface.add_protocol(CmdResponseProtocol, [], :READ_WRITE)
        packet = Packet.new('TGT', 'CMD')
        packet.template = "SOUR:VOLT"
        packet.response = ["TGT", "READ_VOLTAGE"]
        packet.restore_defaults
        # write blocks waiting for the response so spawn a thread
        thread = Thread.new { @interface.write(packet) }
        sleep 0.1
        @interface.disconnect
        sleep 0.1
        expect(thread.alive?).to be false
      end
    end

    describe "write" do
      it "works without a response" do
        @interface.instance_variable_set(:@stream, CmdResponseStream.new)
        @interface.add_protocol(CmdResponseProtocol, [], :READ_WRITE)
        packet = Packet.new('TGT', 'CMD')
        packet.append_item("VOLTAGE", 16, :UINT)
        packet.get_item("VOLTAGE").default = 1
        packet.append_item("CHANNEL", 16, :UINT)
        packet.get_item("CHANNEL").default = 2
        packet.template = "SOUR:VOLT <VOLTAGE>, (@<CHANNEL>)"
        packet.accessor = TemplateAccessor.new(packet)
        packet.restore_defaults
        @interface.write(packet)
        expect($write_buffer).to eql("SOUR:VOLT 1, (@2)")
      end

      it "logs an error if it doesn't receive a response" do
        @interface.instance_variable_set(:@stream, CmdResponseStream.new)
        @interface.add_protocol(CmdResponseProtocol, %w(1.5), :READ_WRITE)
        @interface.target_names = ['TGT']
        packet = Packet.new('TGT', 'CMD')
        packet.template = "GO"
        packet.response = ["TGT", "DATA"]
        packet.restore_defaults
        @interface.connect
        start = Time.now
        logger = class_double("OpenC3::Logger").as_stubbed_const(:transfer_nested_constants => true)
        expect(logger).to receive(:error).with("StreamInterface: Timeout waiting for response")
        @interface.write(packet)
        expect(Time.now - start).to be_within(0.1).of(1.5)
      end

      it "disconnects if it doesn't receive a response" do
        @interface.instance_variable_set(:@stream, CmdResponseStream.new)
        @interface.add_protocol(CmdResponseProtocol, %w(1.5 0.02 true), :READ_WRITE)
        @interface.target_names = ['TGT']
        packet = Packet.new('TGT', 'CMD')
        packet.template = "GO"
        packet.response = ["TGT", "DATA"]
        packet.restore_defaults
        @interface.connect
        start = Time.now
        expect { @interface.write(packet) }.to raise_error(/Timeout waiting for response/)
        expect(Time.now - start).to be_within(0.1).of(1.5)
      end

      it "doesn't expect responses for empty response fields" do
        @interface.instance_variable_set(:@stream, CmdResponseStream.new)
        @interface.add_protocol(CmdResponseProtocol, [], :READ_WRITE)
        @interface.target_names = ['TGT']
        packet = Packet.new('TGT', 'CMD')
        packet.template = "GO"
        packet.restore_defaults
        @interface.connect
        logger = class_double("OpenC3::Logger").as_stubbed_const(:transfer_nested_constants => true)
        expect(logger).to_not receive(:error)
        @interface.write(packet)
      end

      it "processes responses with no ID fields" do
        tf = Tempfile.new('unittest')
        tf.puts 'TELEMETRY TGT READ_VOLTAGE BIG_ENDIAN'
        tf.puts '  ACCESSOR TemplateAccessor'
        tf.puts '  TEMPLATE "<VOLTAGE>"'
        tf.puts '  APPEND_ITEM VOLTAGE 16 UINT'
        tf.close
        pc = PacketConfig.new
        pc.process_file(tf.path, "SYSTEM")
        telemetry = Telemetry.new(pc)
        tf.unlink

        allow(System).to receive_message_chain(:telemetry).and_return(telemetry)
        @interface.instance_variable_set(:@stream, CmdResponseStream.new)
        @interface.add_protocol(CmdResponseProtocol, [], :READ_WRITE)
        # Add extra target names to the interface to ensure we grab the correct one
        @interface.target_names = ['BLAH', 'TGT', 'OTHER']
        packet = Packet.new('TGT', 'CMD')
        packet.accessor = TemplateAccessor.new(packet)
        packet.append_item("VOLTAGE", 16, :UINT)
        packet.get_item("VOLTAGE").default = 11
        packet.append_item("CHANNEL", 16, :UINT)
        packet.get_item("CHANNEL").default = 1
        packet.template = "SOUR:VOLT <VOLTAGE>, (@<CHANNEL>)"
        packet.response = ["TGT", "READ_VOLTAGE"]
        packet.restore_defaults
        @interface.connect
        read_result = nil
        $read_buffer = "\x31\x30" # ASCII 31, 30 is '10'
        Thread.new { sleep(0.5); read_result = @interface.read }
        @interface.write(packet)
        sleep 0.55
        expect($write_buffer).to eql("SOUR:VOLT 11, (@1)")
        expect(read_result.read("VOLTAGE")).to eql(10)
      end
    end
  end
end
