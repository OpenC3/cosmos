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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/interfaces/protocols/slip_protocol'
require 'openc3/interfaces/interface'
require 'openc3/streams/stream'

module OpenC3
  describe SlipProtocol do

    class SlipStream < Stream
      def connect; end
      def connected?; true; end
      def disconnect; end
      def read; $buffer; end
      def write(data); $buffer = data; end
    end

    before(:each) do
      @interface = StreamInterface.new
      allow(@interface).to receive(:connected?) { true }
      $buffer = ''
    end

    describe "initialize" do
      it "complains if given invalid params" do
        expect {
          @interface.add_protocol(SlipProtocol, ["5.1234"],:READ_WRITE)
        }.to raise_error(/invalid value for Integer/)
        expect {
          @interface.add_protocol(SlipProtocol, [nil, nil],:READ_WRITE)
        }.to raise_error(/read_strip_characters must be true or false/)
        expect {
          @interface.add_protocol(SlipProtocol, [nil, true, nil],:READ_WRITE)
        }.to raise_error(/read_enable_escaping must be true or false/)
        expect {
          @interface.add_protocol(SlipProtocol, [nil, true, true, nil],:READ_WRITE)
        }.to raise_error(/write_enable_escaping must be true or false/)
        expect {
          @interface.add_protocol(SlipProtocol, [nil, true, true, true, "5.1234"],:READ_WRITE)
        }.to raise_error(/invalid value for Integer/)
        expect {
          @interface.add_protocol(SlipProtocol, [nil, true, true, true, "0xC0", "5.1234"],:READ_WRITE)
        }.to raise_error(/invalid value for Integer/)
        expect {
          @interface.add_protocol(SlipProtocol, [nil, true, true, true, "0xC0", "0xDB", "5.1234"],:READ_WRITE)
        }.to raise_error(/invalid value for Integer/)
        expect {
          @interface.add_protocol(SlipProtocol, [nil, true, true, true, "0xC0", "0xDB", "0xDC", "5.1234"],:READ_WRITE)
        }.to raise_error(/invalid value for Integer/)
      end

      it "handles proper params" do
        protocol = @interface.add_protocol(SlipProtocol, ["0xC0", "false", "true", "false", "0xC0", "0xDB", "0xDC", "0xDD"],:READ_WRITE)
        expect(protocol.instance_variable_get(:@start_char)).to eq "\xC0"
        expect(protocol.instance_variable_get(:@read_strip_characters)).to eq false
        expect(protocol.instance_variable_get(:@read_enable_escaping)).to eq true
        expect(protocol.instance_variable_get(:@write_enable_escaping)).to eq false
        expect(protocol.instance_variable_get(:@end_char)).to eq "\xC0"
        expect(protocol.instance_variable_get(:@esc_char)).to eq "\xDB"
        expect(protocol.instance_variable_get(:@esc_end_char)).to eq "\xDC"
        expect(protocol.instance_variable_get(:@esc_esc_char)).to eq "\xDD"
        expect(protocol.instance_variable_get(:@replace_end)).to eq "\xDB\xDC"
        expect(protocol.instance_variable_get(:@replace_esc)).to eq "\xDB\xDD"
      end
    end

    describe "read" do
      it "handles multiple reads" do
        $index = 0
        class TerminatedSlipStream < SlipStream
          def read
            case $index
            when 0
              $index += 1
              "\x01\x02"
            when 1
              $index += 1
              "\xC0"
            end
          end
        end

        @interface.instance_variable_set(:@stream, TerminatedSlipStream.new)
        @interface.add_protocol(SlipProtocol, [], :READ_WRITE)
        packet = @interface.read
        expect(packet.buffer).to eql("\x01\x02")
      end

      it "handles multiple reads and packets" do
        $index = 0
        class MultiTerminatedSlipStream < SlipStream
          def read
            case $index
            when 0
              $index += 1
              "\xC0"
            when 1
              $index += 1
              "\x01\x02"
            when 2
              $index += 1
              "\xC0"
            when 3
              $index += 1
              "\xC0\x03\x04"
            when 4
              $index += 1
              "\x01\x02"
            when 5
              $index += 1
              "\xC0"
            end
          end
        end

        @interface.instance_variable_set(:@stream, MultiTerminatedSlipStream.new)
        @interface.add_protocol(SlipProtocol, ["0xC0"], :READ_WRITE)
        packet = @interface.read
        expect(packet.buffer).to eql("\x01\x02")
        packet = @interface.read
        expect(packet.buffer).to eql("\x03\x04\x01\x02")
      end

      it "handles empty packets" do
        @interface.instance_variable_set(:@stream, SlipStream.new)
        @interface.add_protocol(SlipProtocol, [], :READ_WRITE)
        $buffer = "\xC0\x01\x02\xC0"
        packet = @interface.read
        expect(packet.buffer.length).to eql 0
        packet = @interface.read
        expect(packet.buffer).to eql("\x01\x02")
      end

      it "handles no start_char pattern" do
        @interface.instance_variable_set(:@stream, SlipStream.new)
        @interface.add_protocol(SlipProtocol, [], :READ_WRITE)
        $buffer = "\x00\x01\x02\xC0\x44\x02\x03"
        packet = @interface.read
        expect(packet.buffer).to eql("\x00\x01\x02")
      end

      it "handles a start_char inside the packet" do
        @interface.instance_variable_set(:@stream, SlipStream.new)
        @interface.add_protocol(SlipProtocol, ["0xC0", false], :READ_WRITE)
        $buffer = "\xC0\x00\x01\x02\xC0\x44\x02\x03"
        packet = @interface.read
        expect(packet.buffer).to eql("\xC0\x00\x01\x02\xC0")
      end

      it "handles bad data before the packet" do
        @interface.instance_variable_set(:@stream, SlipStream.new)
        @interface.add_protocol(SlipProtocol, ["0xC0", false], :READ_WRITE)
        $buffer = "\x00\x01\x02\xC0\x44\x02\x03\xC0"
        packet = @interface.read
        expect(packet.buffer).to eql("\xC0\x44\x02\x03\xC0")
      end

      it "handles escape sequences" do
        @interface.instance_variable_set(:@stream, SlipStream.new)
        @interface.add_protocol(SlipProtocol, [], :READ_WRITE)
        $buffer = "\x00\xDB\xDC\x44\xDB\xDD\x02\xDB\xDC\x03\xDB\xDD\xC0"
        packet = @interface.read
        expect(packet.buffer).to eql("\x00\xC0\x44\xDB\x02\xC0\x03\xDB")
      end

      it "leaves escape sequences" do
        @interface.instance_variable_set(:@stream, SlipStream.new)
        @interface.add_protocol(SlipProtocol, [nil, true, false], :READ_WRITE)
        $buffer = "\x00\xDB\xDC\x44\xDB\xDD\x02\xDB\xDC\x03\xDB\xDD\xC0"
        packet = @interface.read
        expect(packet.buffer).to eql("\x00\xDB\xDC\x44\xDB\xDD\x02\xDB\xDC\x03\xDB\xDD")
      end
    end

    describe "write" do
      it "appends end_char to the packet" do
        @interface.instance_variable_set(:@stream, SlipStream.new)
        @interface.add_protocol(SlipProtocol, [], :READ_WRITE)
        pkt = Packet.new('tgt', 'pkt')
        pkt.buffer = "\x00\x01\x02\x03"
        @interface.write(pkt)
        expect($buffer).to eql("\x00\x01\x02\x03\xC0")
      end

      it "appends a different end_char to the packet" do
        @interface.instance_variable_set(:@stream, SlipStream.new)
        @interface.add_protocol(SlipProtocol, [nil, true, true, true, "0xEE"], :READ_WRITE)
        pkt = Packet.new('tgt', 'pkt')
        pkt.buffer = "\x00\x01\x02\x03"
        @interface.write(pkt)
        expect($buffer).to eql("\x00\x01\x02\x03\xEE")
      end

      it "appends start_char and end_char to the packet" do
        @interface.instance_variable_set(:@stream, SlipStream.new)
        @interface.add_protocol(SlipProtocol, ["0xA0", true, true, true, "0xC0"], :READ_WRITE)
        pkt = Packet.new('tgt', 'pkt')
        pkt.buffer = "\x00\x01\x02\x03"
        @interface.write(pkt)
        expect($buffer).to eql("\xA0\x00\x01\x02\x03\xC0")
      end

      it "handles writing the end_char inside the packet" do
        @interface.instance_variable_set(:@stream, SlipStream.new)
        @interface.add_protocol(SlipProtocol, [], :READ_WRITE)
        pkt = Packet.new('tgt', 'pkt')
        pkt.buffer = "\x00\xC0\x02\x03"
        @interface.write(pkt)
        expect($buffer).to eql("\x00\xDB\xDC\x02\x03\xC0")
      end

      it "handles writing the esc_char inside the packet" do
        @interface.instance_variable_set(:@stream, SlipStream.new)
        @interface.add_protocol(SlipProtocol, [], :READ_WRITE)
        pkt = Packet.new('tgt', 'pkt')
        pkt.buffer = "\x00\xDB\x02\x03"
        @interface.write(pkt)
        expect($buffer).to eql("\x00\xDB\xDD\x02\x03\xC0")
      end

      it "handles writing the end_char and the esc_char inside the packet" do
        @interface.instance_variable_set(:@stream, SlipStream.new)
        @interface.add_protocol(SlipProtocol, [], :READ_WRITE)
        pkt = Packet.new('tgt', 'pkt')
        pkt.buffer = "\x00\xC0\xDB\xDB\xC0\x02\x03"
        @interface.write(pkt)
        expect($buffer).to eql("\x00\xDB\xDC\xDB\xDD\xDB\xDD\xDB\xDC\x02\x03\xC0")
      end

      it "handles not writing escape sequences" do
        @interface.instance_variable_set(:@stream, SlipStream.new)
        @interface.add_protocol(SlipProtocol, [nil, true, true, false], :READ_WRITE)
        pkt = Packet.new('tgt', 'pkt')
        pkt.buffer = "\x00\xC0\xDB\xDB\xC0\x02\x03"
        @interface.write(pkt)
        expect($buffer).to eql("\x00\xC0\xDB\xDB\xC0\x02\x03\xC0")
      end

      it "handles different escape sequences" do
        @interface.instance_variable_set(:@stream, SlipStream.new)
        @interface.add_protocol(SlipProtocol, [nil, true, true, true, "0xE0", "0xE1", "0xE2", "0xE3"], :READ_WRITE)
        pkt = Packet.new('tgt', 'pkt')
        pkt.buffer = "\x00\xE0\xE1\xE1\xE0\x02\x03"
        @interface.write(pkt)
        expect($buffer).to eql("\x00\xE1\xE2\xE1\xE3\xE1\xE3\xE1\xE2\x02\x03\xE0")
      end
    end

    describe "write_details" do
      it "returns the protocol configuration details" do
        @interface.add_protocol(SlipProtocol, [], :READ_WRITE)
        protocol = @interface.write_protocols[0]
        details = protocol.write_details
        
        expect(details).to be_a(Hash)
        expect(details['name']).to eq('SlipProtocol')
        expect(details.key?('write_data_input_time')).to be true
        expect(details.key?('write_data_input')).to be true
        expect(details.key?('write_data_output_time')).to be true
        expect(details.key?('write_data_output')).to be true
      end

      it "includes slip protocol-specific configuration" do
        @interface.add_protocol(SlipProtocol, ["0xC0", "false", "true", "false", "0xC0", "0xDB", "0xDC", "0xDD"], :READ_WRITE)
        protocol = @interface.write_protocols[0]
        details = protocol.write_details
        
        expect(details['start_char']).to eq("\xC0".inspect)
        expect(details['write_enable_escaping']).to eq(false)
        expect(details['end_char']).to eq("\xC0".inspect)
        expect(details['esc_char']).to eq("\xDB".inspect)
        expect(details['esc_end_char']).to eq("\xDC".inspect)
        expect(details['esc_esc_char']).to eq("\xDD".inspect)
      end
    end

    describe "read_details" do
      it "returns the protocol configuration details" do
        @interface.add_protocol(SlipProtocol, [], :READ_WRITE)
        protocol = @interface.read_protocols[0]
        details = protocol.read_details
        
        expect(details).to be_a(Hash)
        expect(details['name']).to eq('SlipProtocol')
        expect(details.key?('read_data_input_time')).to be true
        expect(details.key?('read_data_input')).to be true
        expect(details.key?('read_data_output_time')).to be true
        expect(details.key?('read_data_output')).to be true
      end

      it "includes slip protocol-specific configuration" do
        @interface.add_protocol(SlipProtocol, ["0xA0", "true", "false", "true", "0xE0", "0xE1", "0xE2", "0xE3"], :READ_WRITE)
        protocol = @interface.read_protocols[0]
        details = protocol.read_details
        
        expect(details['start_char']).to eq("\xA0".inspect)
        expect(details['read_strip_characters']).to eq(true)
        expect(details['read_enable_escaping']).to eq(false)
        expect(details['end_char']).to eq("\xE0".inspect)
        expect(details['esc_char']).to eq("\xE1".inspect)
        expect(details['esc_end_char']).to eq("\xE2".inspect)
        expect(details['esc_esc_char']).to eq("\xE3".inspect)
      end
    end
  end
end
