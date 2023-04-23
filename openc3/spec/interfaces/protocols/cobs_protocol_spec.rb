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
require 'openc3/interfaces/protocols/cobs_protocol'
require 'openc3/interfaces/interface'
require 'openc3/streams/stream'

module OpenC3
  describe CobsProtocol do

    class CobsStream < Stream
      def connect; end
      def connected?; true; end
      def disconnect; end
      def read; $buffer; end
      def write(data); $buffer = data; end
    end

    def build_example_data
      @examples = [
        ["\x00", "\x01\x01\x00"],
        ["\x00\x00", "\x01\x01\x01\x00"],
        ["\x00\x11\x00", "\x01\x02\x11\x01\x00"],
        ["\x11\x22\x00\x33", "\x03\x11\x22\x02\x33\x00"],
        ["\x11\x22\x33\x44", "\x05\x11\x22\x33\x44\x00"],
        ["\x11\x00\x00\x00", "\x02\x11\x01\x01\x01\x00"],
      ]
      data = ''
      (0..254).each do |char|
        data << [char].pack('C')
      end
      result = "\x01\xFF" + data[1..-1] + "\x00"
      @examples << [data, result]
      data = ''
      (0..254).each do |char|
        data << [char].pack('C')
      end
      result = "\x01\xFF" + data[1..-1] + "\x00"
      @examples << [data, result]
      data = ''
      (1..255).each do |char|
        data << [char].pack('C')
      end
      result = "\xFF" + data[0..-2] + "\x02\xFF\x00"
      @examples << [data, result]
      data = ''
      (2..255).each do |char|
        data << [char].pack('C')
      end
      data << "\x00"
      result = "\xFF" + data[0..-2] + "\x01\x01\x00"
      @examples << [data, result]
      data = ''
      (3..255).each do |char|
        data << [char].pack('C')
      end
      data << "\x00\x01"
      result = "\xFE" + data[0..-3] + "\x02\x01\x00"
      @examples << [data, result]
    end

    before(:each) do
      @interface = StreamInterface.new
      allow(@interface).to receive(:connected?) { true }
      $buffer = ''
    end

    describe "read" do
      it "handles multiple reads" do
        $index = 0
        class TerminatedCobsStream < CobsStream
          def read
            case $index
            when 0
              $index += 1
              "\x03\x01\x02"
            when 1
              $index += 1
              "\x00"
            end
          end
        end

        @interface.instance_variable_set(:@stream, TerminatedCobsStream.new)
        @interface.add_protocol(CobsProtocol, [], :READ_WRITE)
        packet = @interface.read
        expect(packet.buffer).to eql("\x01\x02")
      end

      it "handles multiple reads and packets" do
        $index = 0
        class MultiTerminatedCobsStream < CobsStream
          def read
            case $index
            when 0
              $index += 1
              "\x03"
            when 1
              $index += 1
              "\x01\x02"
            when 2
              $index += 1
              "\x00"
            when 3
              $index += 1
              "\x05\x03\x04"
            when 4
              $index += 1
              "\x01\x02"
            when 5
              $index += 1
              "\x00"
            end
          end
        end

        @interface.instance_variable_set(:@stream, MultiTerminatedCobsStream.new)
        @interface.add_protocol(CobsProtocol, [], :READ_WRITE)
        packet = @interface.read
        expect(packet.buffer).to eql("\x01\x02")
        packet = @interface.read
        expect(packet.buffer).to eql("\x03\x04\x01\x02")
      end

      it "handles empty packets" do
        @interface.instance_variable_set(:@stream, CobsStream.new)
        @interface.add_protocol(CobsProtocol, [], :READ_WRITE)
        $buffer = "\x01\x00\x03\x01\x02\x00"
        packet = @interface.read
        expect(packet.buffer.length).to eql 0
        packet = @interface.read
        expect(packet.buffer).to eql("\x01\x02")
      end

      it "handles examples" do
        build_example_data()
        @interface.instance_variable_set(:@stream, CobsStream.new)
        @interface.add_protocol(CobsProtocol, [], :READ_WRITE)
        pkt = Packet.new('tgt', 'pkt')
        @examples.each do |decoded, encoded|
          $buffer = encoded
          packet = @interface.read
          expect(packet.buffer).to eql(decoded)
        end
      end
    end

    describe "write" do
      it "handles examples" do
        build_example_data()
        @interface.instance_variable_set(:@stream, CobsStream.new)
        @interface.add_protocol(CobsProtocol, [], :READ_WRITE)
        pkt = Packet.new('tgt', 'pkt')
        @examples.each do |decoded, encoded|
          pkt.buffer = decoded
          @interface.write(pkt)
          expect($buffer).to eql(encoded)
        end
      end
    end
  end
end
