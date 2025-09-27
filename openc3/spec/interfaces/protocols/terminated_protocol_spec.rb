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

require 'spec_helper'
require 'openc3/interfaces/protocols/terminated_protocol'
require 'openc3/interfaces/interface'
require 'openc3/streams/stream'

module OpenC3
  describe TerminatedProtocol do
    class TerminatedStream < Stream
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
      it "initializes attributes" do
        @interface.add_protocol(TerminatedProtocol, ['0xABCD', '0xABCD'], :READ_WRITE)
        expect(@interface.read_protocols[0].instance_variable_get(:@data)).to eq ''
      end
    end

    describe "read" do
      it "handles multiple reads" do
        $index = 0
        class MultiTerminatedStream < TerminatedStream
          def read
            case $index
            when 0
              $index += 1
              "\x01\x02"
            when 1
              $index += 1
              "\xAB"
            when 2
              $index += 1
              "\xCD"
            end
          end
        end

        @interface.instance_variable_set(:@stream, MultiTerminatedStream.new)
        @interface.add_protocol(TerminatedProtocol, ['', '0xABCD', true], :READ_WRITE)
        packet = @interface.read
        expect(packet.buffer).to eql("\x01\x02")
      end

      context "when stripping termination characters" do
        it "handles empty packets" do
          @interface.instance_variable_set(:@stream, TerminatedStream.new)
          @interface.add_protocol(TerminatedProtocol, ['', '0xABCD', true], :READ_WRITE)
          $buffer = "\xAB\xCD\x01\x02\xAB\xCD"
          packet = @interface.read
          expect(packet.buffer.length).to eql 0
          packet = @interface.read
          expect(packet.buffer).to eql("\x01\x02")
        end

        it "handles no sync pattern" do
          @interface.instance_variable_set(:@stream, TerminatedStream.new)
          @interface.add_protocol(TerminatedProtocol, ['', '0xABCD', true], :READ_WRITE)
          $buffer = "\x00\x01\x02\xAB\xCD\x44\x02\x03"
          packet = @interface.read
          expect(packet.buffer).to eql("\x00\x01\x02")
        end

        it "handles a sync pattern inside the packet" do
          @interface.instance_variable_set(:@stream, TerminatedStream.new)
          @interface.add_protocol(TerminatedProtocol, ['', '0xABCD', true, 0, 'DEAD'], :READ_WRITE)
          $buffer = "\xDE\xAD\x00\x01\x02\xAB\xCD\x44\x02\x03"
          packet = @interface.read
          expect(packet.buffer).to eql("\xDE\xAD\x00\x01\x02")
        end

        it "handles a sync pattern outside the packet" do
          @interface.instance_variable_set(:@stream, TerminatedStream.new)
          @interface.add_protocol(TerminatedProtocol, ['', '0xABCD', true, 2, 'DEAD'], :READ_WRITE)
          $buffer = "\xDE\xAD\x00\x01\x02\xAB\xCD\x44\x02\x03"
          packet = @interface.read
          expect(packet.buffer).to eql("\x00\x01\x02")
        end
      end

      context "when keeping termination characters" do
        it "handles empty packets" do
          @interface.instance_variable_set(:@stream, TerminatedStream.new)
          @interface.add_protocol(TerminatedProtocol, ['', '0xABCD', false], :READ_WRITE)
          $buffer = "\xAB\xCD\x01\x02\xAB\xCD"
          packet = @interface.read
          expect(packet.buffer).to eql("\xAB\xCD")
          packet = @interface.read
          expect(packet.buffer).to eql("\x01\x02\xAB\xCD")
        end

        it "handles no sync pattern" do
          @interface.instance_variable_set(:@stream, TerminatedStream.new)
          @interface.add_protocol(TerminatedProtocol, ['', '0xABCD', false], :READ_WRITE)
          $buffer = "\x00\x01\x02\xAB\xCD\x44\x02\x03"
          packet = @interface.read
          expect(packet.buffer).to eql("\x00\x01\x02\xAB\xCD")
        end

        it "handles a sync pattern inside the packet" do
          @interface.instance_variable_set(:@stream, TerminatedStream.new)
          @interface.add_protocol(TerminatedProtocol, ['', '0xABCD', false, 0, 'DEAD'], :READ_WRITE)
          $buffer = "\xDE\xAD\x00\x01\x02\xAB\xCD\x44\x02\x03"
          packet = @interface.read
          expect(packet.buffer).to eql("\xDE\xAD\x00\x01\x02\xAB\xCD")
        end

        it "handles a sync pattern outside the packet" do
          @interface.instance_variable_set(:@stream, TerminatedStream.new)
          @interface.add_protocol(TerminatedProtocol, ['', '0xABCD', false, 2, 'DEAD'], :READ_WRITE)
          $buffer = "\xDE\xAD\x00\x01\x02\xAB\xCD\x44\x02\x03"
          packet = @interface.read
          expect(packet.buffer).to eql("\x00\x01\x02\xAB\xCD")
        end
      end
    end

    describe "write" do
      it "appends termination characters to the packet" do
        @interface.instance_variable_set(:@stream, TerminatedStream.new)
        @interface.add_protocol(TerminatedProtocol, ['0xCDEF', ''], :READ_WRITE)
        pkt = Packet.new('tgt', 'pkt')
        pkt.buffer = "\x00\x01\x02\x03"
        @interface.write(pkt)
        expect($buffer).to eql("\x00\x01\x02\x03\xCD\xEF")
      end

      it "complains if the packet buffer contains the termination characters" do
        @interface.instance_variable_set(:@stream, TerminatedStream.new)
        @interface.add_protocol(TerminatedProtocol, ['0xCDEF', ''], :READ_WRITE)
        pkt = Packet.new('tgt', 'pkt')
        pkt.buffer = "\x00\xCD\xEF\x03"
        expect { @interface.write(pkt) }.to raise_error("Packet contains termination characters!")
      end

      it "handles writing the sync field inside the packet" do
        @interface.instance_variable_set(:@stream, TerminatedStream.new)
        @interface.add_protocol(TerminatedProtocol, ['0xCDEF', '', true, 0, 'DEAD', true], :READ_WRITE)
        pkt = Packet.new('tgt', 'pkt')
        pkt.buffer = "\x00\x01\x02\x03"
        @interface.write(pkt)
        expect($buffer).to eql("\xDE\xAD\x02\x03\xCD\xEF")
      end

      it "handles writing the sync field outside the packet" do
        @interface.instance_variable_set(:@stream, TerminatedStream.new)
        @interface.add_protocol(TerminatedProtocol, ['0xCDEF', '', true, 2, 'DEAD', true], :READ_WRITE)
        pkt = Packet.new('tgt', 'pkt')
        pkt.buffer = "\x00\x01\x02\x03"
        @interface.write(pkt)
        expect($buffer).to eql("\xDE\xAD\x00\x01\x02\x03\xCD\xEF")
      end
    end

    describe "write_details" do
      it "returns the protocol configuration details" do
        @interface.add_protocol(TerminatedProtocol, ['0xCDEF', ''], :READ_WRITE)
        protocol = @interface.write_protocols[0]
        details = protocol.write_details
        
        expect(details).to be_a(Hash)
        expect(details['name']).to eq('TerminatedProtocol')
        expect(details.key?('write_data_input_time')).to be true
        expect(details.key?('write_data_input')).to be true
        expect(details.key?('write_data_output_time')).to be true
        expect(details.key?('write_data_output')).to be true
      end

      it "includes terminated protocol-specific configuration" do
        @interface.add_protocol(TerminatedProtocol, ['0xCDEF', '0xABCD'], :READ_WRITE)
        protocol = @interface.write_protocols[0]
        details = protocol.write_details
        
        expect(details['write_termination_characters']).to eq("\xCD\xEF".inspect)
      end
    end

    describe "read_details" do
      it "returns the protocol configuration details" do
        @interface.add_protocol(TerminatedProtocol, ['', '0xABCD', true], :READ_WRITE)
        protocol = @interface.read_protocols[0]
        details = protocol.read_details
        
        expect(details).to be_a(Hash)
        expect(details['name']).to eq('TerminatedProtocol')
        expect(details.key?('read_data_input_time')).to be true
        expect(details.key?('read_data_input')).to be true
        expect(details.key?('read_data_output_time')).to be true
        expect(details.key?('read_data_output')).to be true
      end

      it "includes terminated protocol-specific configuration" do
        @interface.add_protocol(TerminatedProtocol, ['', '0xABCD', false, 2, 'DEAD', true], :READ_WRITE)
        protocol = @interface.read_protocols[0]
        details = protocol.read_details
        
        expect(details['read_termination_characters']).to eq("\xAB\xCD".inspect)
        expect(details['strip_read_termination']).to eq(false)
      end
    end
  end
end
