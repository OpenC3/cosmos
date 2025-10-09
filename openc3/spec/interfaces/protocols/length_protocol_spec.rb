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
require 'openc3/interfaces/protocols/length_protocol'
require 'openc3/interfaces/interface'
require 'openc3/streams/stream'

module OpenC3
  describe LengthProtocol do
    class LengthStream < Stream
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
        @interface.add_protocol(LengthProtocol, [16, 32, 16, 2, 'LITTLE_ENDIAN', 2, '0xDEADBEEF', 100, true], :READ_WRITE)
        expect(@interface.read_protocols[0].instance_variable_get(:@data)).to eq ''
        expect(@interface.read_protocols[0].instance_variable_get(:@length_bit_offset)).to eq 16
        expect(@interface.read_protocols[0].instance_variable_get(:@length_bit_size)).to eq 32
        expect(@interface.read_protocols[0].instance_variable_get(:@length_value_offset)).to eq 16
        expect(@interface.read_protocols[0].instance_variable_get(:@length_bytes_per_count)).to eq 2
        expect(@interface.read_protocols[0].instance_variable_get(:@length_endianness)).to eq :LITTLE_ENDIAN
        expect(@interface.read_protocols[0].instance_variable_get(:@discard_leading_bytes)).to eq 2
        expect(@interface.read_protocols[0].instance_variable_get(:@sync_pattern)).to eq "\xDE\xAD\xBE\xEF"
        expect(@interface.read_protocols[0].instance_variable_get(:@max_length)).to be 100
        expect(@interface.read_protocols[0].instance_variable_get(:@fill_fields)).to be true
      end
    end

    describe "read" do
      it "caches data for reads correctly" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  0, # bit offset
                                  8, # bit size
                                  0,  # length offset
                                  1,  # bytes per count
                                  'BIG_ENDIAN'
                                ], :READ_WRITE)
        $buffer = "\x02\x03\x02\x05"
        packet = @interface.read
        expect(packet.buffer.length).to eql 2
        expect(packet.buffer).to eql "\x02\x03"
        packet = @interface.read
        expect(packet.buffer.length).to eql 2
        expect(packet.buffer).to eql "\x02\x05"
        expect(@interface.read_protocols[0].read_data("\x03\x01\x02\x03\x04\x05")).to eql ["\x03\x01\x02", nil]
        expect(@interface.read_protocols[0].read_data("")).to eql ["\x03\x04\x05", nil]
        expect(@interface.read_protocols[0].read_data("")).to eql :STOP
      end

      # This test case uses two length protocols to verify that data flows correctly between the two protocols and that earlier data
      # is removed correctly using discard leading bytes.  In general it is not typical to use two different length protocols, but it could
      # be useful to pull out a packet inside of a packet.
      it "caches data for reads correctly with multiple protocols" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  0, # bit offset
                                  8, # bit size
                                  0,  # length offset
                                  1,  # bytes per count
                                  'BIG_ENDIAN'
                                ], :READ_WRITE)
        @interface.add_protocol(LengthProtocol, [
                                  0, # bit offset
                                  8, # bit size
                                  0,  # length offset
                                  1,  # bytes per count
                                  'BIG_ENDIAN',
                                  1
                                ], :READ_WRITE) # Discard leading bytes set to 1
        # The second protocol above will receive the two byte packets from the first protocol and
        # then drop the length field.
        $buffer = "\x02\x03\x02\x05"
        packet = @interface.read
        expect(packet.buffer.length).to eql 1
        expect(packet.buffer).to eql "\x03"
        packet = @interface.read
        expect(packet.buffer.length).to eql 1
        expect(packet.buffer).to eql "\x05"
      end

      it "reads LITTLE_ENDIAN length fields from the stream" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  16, # bit offset
                                  16, # bit size
                                  0,  # length offset
                                  1,  # bytes per count
                                  'LITTLE_ENDIAN'
                                ], :READ_WRITE)
        $buffer = "\x00\x01\x06\x00\x03\x04"
        packet = @interface.read
        expect(packet.buffer.length).to eql 6
      end

      it "reads LITTLE_ENDIAN bit fields from the stream" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  19, # bit offset
                                  5,  # bit size
                                  0,  # length offset
                                  1,  # bytes per count
                                  'LITTLE_ENDIAN'
                                ], :READ_WRITE)
        $buffer = "\x00\x01\x05\x03\x04"
        packet = @interface.read
        expect(packet.buffer.length).to eql 5
      end

      it "adjusts length by offset" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  16, # bit offset
                                  16, # bit size
                                  1, # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN'
                                ], :READ_WRITE)
        $buffer = "\x00\x01\x00\x05\x03\x04"
        packet = @interface.read
        expect(packet.buffer.length).to eql 6
      end

      it "adjusts length by bytes per count" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  16, # bit offset
                                  16, # bit size
                                  1, # length offset
                                  2, # bytes per count
                                  'BIG_ENDIAN'
                                ], :READ_WRITE)
        $buffer = "\x00\x01\x00\x05\x03\x04\x05\x06\x07\x08\x09"
        packet = @interface.read
        expect(packet.buffer.length).to eql 11
      end

      it "accesses length at odd offset and bit sizes" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  19, # bit offset
                                  5, # bit size
                                  0, # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN'
                                ], :READ_WRITE)
        $buffer = "\x00\x01\x05\x03\x04"
        packet = @interface.read
        expect(packet.buffer.length).to eql 5
      end

      it "raises an error with a packet length of 0" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  16, # bit offset
                                  16, # bit size
                                  0,  # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN'
                                ], :READ_WRITE)
        $buffer = "\x00\x01\x00\x00\x03\x04\x05\x06\x07\x08\x09"
        expect { @interface.read }.to raise_error(RuntimeError, /Calculated packet length of 0 bits/)
      end

      it "raises an error if packet length not enough to support offset and size" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  16, # bit offset
                                  16, # bit size
                                  3,  # length offset of 3 not enough to support 2 byte length field at offset 2 bytes
                                  1, # bytes per count
                                  'BIG_ENDIAN'
                                ], :READ_WRITE)
        $buffer = "\x00\x01\x00\x00\x03\x04\x05\x06\x07\x08\x09"
        expect { @interface.read }.to raise_error(RuntimeError, /Calculated packet length of 24 bits/)
      end

      it "processes a 0 length with a non-zero length offset" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  0, # bit offset
                                  16, # bit size
                                  4,  # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN'
                                ], :READ_WRITE)
        $buffer = "\x00\x00\x01\x02\x00\x00\x03\x04"
        packet = @interface.read
        expect(packet.buffer).to eql "\x00\x00\x01\x02"
        packet = @interface.read
        expect(packet.buffer).to eql "\x00\x00\x03\x04"
      end

      it "validates length against the maximum length" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  16, # bit offset
                                  16, # bit size
                                  0,  # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN',
                                  0, # discard
                                  nil, # sync
                                  50
                                ], :READ_WRITE) # max_length
        $buffer = "\x00\x01\xFF\xFF\x03\x04"
        expect { @interface.read }.to raise_error(RuntimeError, "Length value received larger than max_length: 65535 > 50")
      end

      it "handles a sync value in the packet" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  16, # bit offset
                                  16, # bit size
                                  0, # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN',
                                  0, # discard
                                  "DEAD"
                                ], :READ_WRITE) # sync
        $buffer = "\x00\xDE\xAD\x00\x08\x01\x02\x03\x04\x05\x06"
        packet = @interface.read
        expect(packet.buffer).to eql("\xDE\xAD\x00\x08\x01\x02\x03\x04")
      end

      it "handles a sync value that is discarded" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  16, # bit offset (past the discard)
                                  16, # bit size
                                  0, # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN',
                                  2, # discard
                                  "DEAD"
                                ], :READ_WRITE) # sync
        $buffer = "\x00\xDE\xAD\x00\x08\x01\x02\x03\x04\x05\x06\x07\x08"
        packet = @interface.read
        expect(packet.buffer).to eql("\x00\x08\x01\x02\x03\x04")
      end

      it "handles a length value that is discarded" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  8, # bit offset
                                  16, # bit size
                                  0, # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN',
                                  4, # discard
                                  nil
                                ], :READ_WRITE) # sync
        $buffer = "\x00\x00\x08\x00\x01\x02\x03\x04\x05\x06\x07\x08"
        packet = @interface.read
        expect(packet.buffer).to eql("\x01\x02\x03\x04")
      end

      it "handles a sync and length value that are discarded" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  16, # bit offset
                                  8, # bit size
                                  0, # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN',
                                  4, # discard
                                  'DEAD'
                                ], :READ_WRITE) # sync
        $buffer = "\x00\xDE\xAD\x0A\x00\x01\x02\x03\x04\x05\x06\x07\x08"
        packet = @interface.read
        expect(packet.buffer).to eql("\x01\x02\x03\x04\x05\x06")
      end
    end

    describe "write" do
      it "sends data directly to the stream if no fill" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  32, # bit offset
                                  16, # bit size
                                  0, # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN',
                                  0, # discard no leading bytes
                                  "DEAD", # sync
                                  nil, # max length
                                  false
                                ], :READ_WRITE) # fill fields
        packet = Packet.new(nil, nil)
        packet.buffer = "\x01\x02"
        @interface.write(packet)
        expect($buffer).to eql("\x01\x02")
      end

      it "complains if not enough data to write the sync and length fields" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  32, # bit offset
                                  16, # bit size
                                  0, # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN',
                                  0, # discard no leading bytes
                                  "DEAD", # sync
                                  nil, # max length
                                  true
                                ], :READ_WRITE) # fill fields
        packet = Packet.new(nil, nil)
        packet.buffer = "\x01\x02\x03\x04"
        # 4 bytes are not enough since we expect the length field at offset 32
        expect { @interface.write(packet) }.to raise_error(ArgumentError, /buffer insufficient/)
      end

      it "adjusts length by offset" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  16, # bit offset
                                  16, # bit size
                                  2, # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN',
                                  0, # discard no leading bytes
                                  nil, # sync
                                  nil, # max length
                                  true
                                ], :READ_WRITE) # fill fields
        packet = Packet.new(nil, nil)
        packet.buffer = "\x01\x02\x03\x04\x05\x06"
        @interface.write(packet)
        # Length is 4 instead of 6 due to length offset
        expect(packet.buffer).to eql("\x01\x02\x00\x04\x05\x06")
        expect($buffer).to eql("\x01\x02\x00\x04\x05\x06")
      end

      it "adjusts length by bytes per count" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  0, # bit offset
                                  16, # bit size
                                  0, # length offset
                                  2, # bytes per count
                                  'BIG_ENDIAN',
                                  0, # discard no leading bytes
                                  nil, # sync
                                  nil, # max length
                                  true
                                ], :READ_WRITE) # fill fields
        packet = Packet.new(nil, nil)
        packet.buffer = "\x01\x02\x03\x04\x05\x06"
        @interface.write(packet)
        # Length is 3 instead of 6 due to bytes per count
        expect(packet.buffer).to eql("\x00\x03\x03\x04\x05\x06")
        expect($buffer).to eql("\x00\x03\x03\x04\x05\x06")
      end

      it "writes length at odd offset and bit sizes" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  19, # bit offset
                                  5, # bit size
                                  0, # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN',
                                  0, # discard no leading bytes
                                  nil, # sync
                                  nil, # max length
                                  true
                                ], :READ_WRITE) # fill fields
        packet = Packet.new(nil, nil)
        packet.buffer = "\x55\xAA\x00\xAA\x55\xAA"
        @interface.write(packet)
        expect(packet.buffer).to eql("\x55\xAA\x06\xAA\x55\xAA")
        expect($buffer).to eql("\x55\xAA\x06\xAA\x55\xAA")
      end

      it "validates length against the maximum length 1" do
        # Length inside packet
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  0, # bit offset
                                  16, # bit size
                                  0,  # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN',
                                  0, # discard
                                  nil, # sync
                                  4, # max_length
                                  true
                                ], :READ_WRITE) # fill fields
        packet = Packet.new(nil, nil)
        packet.buffer = "\x01\x02\x03\x04\x05\x06"
        expect { packet = @interface.write(packet) }.to raise_error(RuntimeError, "Calculated length 6 larger than max_length 4")
      end

      it "validates length against the maximum length 2" do
        # Length outside packet (data stream)
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  0, # bit offset
                                  16, # bit size
                                  0,  # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN',
                                  2, # discard
                                  nil, # sync
                                  4, # max_length
                                  true
                                ], :READ_WRITE) # fill fields
        packet = Packet.new(nil, nil)
        packet.buffer = "\x01\x02\x03\x04\x05\x06"
        expect { packet = @interface.write(packet) }.to raise_error(RuntimeError, "Calculated length 8 larger than max_length 4")
      end

      it "inserts the sync and length fields into the packet 1" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  16, # bit offset
                                  16, # bit size
                                  0, # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN',
                                  0, # discard no leading bytes
                                  "DEAD", # sync
                                  nil, # max length
                                  true
                                ], :READ_WRITE) # fill fields
        packet = Packet.new(nil, nil)
        packet.buffer = "\x01\x02\x03\x04\x05\x06\x07\x08"
        @interface.write(packet)
        expect(packet.buffer).to eql("\xDE\xAD\x00\x08\x05\x06\x07\x08")
        expect($buffer).to eql("\xDE\xAD\x00\x08\x05\x06\x07\x08")
      end

      it "inserts the sync and length fields into the packet 2" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  64, # bit offset
                                  32, # bit size
                                  12, # length offset
                                  1,  # bytes per count
                                  'BIG_ENDIAN',
                                  0,  # discard no leading bytes
                                  "BA5EBA11CAFEBABE",
                                  nil,
                                  true
                                ], :READ_WRITE)
        packet = Packet.new(nil, nil)
        # The packet buffer contains the sync and length fields which are overwritten by the write call
        packet.buffer = "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x02\x03\x04"
        @interface.write(packet)
        # Since we discarded 0 leading bytes, they are simply written over by the write call
        expect(packet.buffer).to eql("\xBA\x5E\xBA\x11\xCA\xFE\xBA\xBE\x00\x00\x00\x04\x01\x02\x03\x04")
        expect($buffer).to eql("\xBA\x5E\xBA\x11\xCA\xFE\xBA\xBE\x00\x00\x00\x04\x01\x02\x03\x04")
      end

      it "inserts the length field into the packet and sync into data stream 1" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  16, # bit offset
                                  16, # bit size
                                  0, # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN',
                                  2, # discard sync
                                  "DEAD", # sync
                                  nil, # max length
                                  true
                                ], :READ_WRITE) # fill fields
        packet = Packet.new(nil, nil)
        packet.buffer = "\x01\x02\x03\x04\x05\x06"
        @interface.write(packet)
        expect(packet.buffer).to eql("\x00\x08\x03\x04\x05\x06")
        expect($buffer).to eql("\xDE\xAD\x00\x08\x03\x04\x05\x06")
      end

      it "inserts the length field into the packet and sync into data stream 2" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  32, # bit offset
                                  16, # bit size
                                  0, # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN',
                                  4, # discard sync
                                  "BA5EBA11", # sync
                                  nil, # max length
                                  true
                                ], :READ_WRITE) # fill fields
        packet = Packet.new(nil, nil)
        packet.buffer = "\x01\x02\x03\x04\x05\x06"
        @interface.write(packet)
        expect(packet.buffer).to eql("\x00\x0A\x03\x04\x05\x06")
        expect($buffer).to eql("\xBA\x5E\xBA\x11\x00\x0A\x03\x04\x05\x06")
      end

      it "inserts the length field into the packet and sync into data stream 3" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  64, # bit offset
                                  32, # bit size
                                  12, # length offset
                                  1,  # bytes per count
                                  'BIG_ENDIAN',
                                  8,  # discard 8 leading bytes (sync)
                                  "BA5EBA11CAFEBABE",
                                  nil,
                                  true
                                ], :READ_WRITE)
        packet = Packet.new(nil, nil)
        # The packet buffer contains the length field which is overwritten by the write call
        packet.buffer = "\x00\x00\x00\x00\x01\x02\x03\x04"
        @interface.write(packet)
        # Since we discarded 8 leading bytes, they are put back in the final stream data
        expect(packet.buffer).to eql("\x00\x00\x00\x04\x01\x02\x03\x04")
        expect($buffer).to eql("\xBA\x5E\xBA\x11\xCA\xFE\xBA\xBE\x00\x00\x00\x04\x01\x02\x03\x04")
      end

      it "inserts the length field into the data stream 1" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  8, # bit offset
                                  16, # bit size
                                  0, # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN',
                                  4, # discard
                                  nil, # sync
                                  nil, # max length
                                  true
                                ], :READ_WRITE) # fill fields
        packet = Packet.new(nil, nil)
        packet.buffer = "\x01\x02\x03\x04"
        @interface.write(packet)
        expect(packet.buffer).to eql("\x01\x02\x03\x04")
        expect($buffer).to eql("\x00\x00\x08\x00\x01\x02\x03\x04")
      end

      it "inserts the length field into the data stream 2" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  16, # bit offset
                                  8, # bit size
                                  0, # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN',
                                  4, # discard
                                  nil, # sync
                                  nil, # max length
                                  true
                                ], :READ_WRITE) # fill fields
        packet = Packet.new(nil, nil)
        packet.buffer = "\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A"
        @interface.write(packet)
        expect(packet.buffer).to eql("\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A")
        expect($buffer).to eql("\x00\x00\x0E\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A")
      end

      it "inserts the sync and length fields into the data stream 1" do
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  16, # bit offset
                                  8, # bit size
                                  0, # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN',
                                  4, # discard
                                  "0xDEAD", # sync
                                  nil, # max length
                                  true
                                ], :READ_WRITE) # fill fields
        packet = Packet.new(nil, nil)
        packet.buffer = "\x01\x02\x03\x04\x05\x06"
        @interface.write(packet)
        expect(packet.buffer).to eql("\x01\x02\x03\x04\x05\x06")
        expect($buffer).to eql("\xDE\xAD\x0A\x00\x01\x02\x03\x04\x05\x06")
      end

      it "inserts the sync and length fields into the data stream 2" do
        $buffer = ''
        @interface.instance_variable_set(:@stream, LengthStream.new)
        @interface.add_protocol(LengthProtocol, [
                                  32, # bit offset
                                  8, # bit size
                                  0, # length offset
                                  1, # bytes per count
                                  'BIG_ENDIAN',
                                  5, # discard
                                  "BA5EBA11", # sync
                                  nil, # max length
                                  true
                                ], :READ_WRITE) # fill fields
        packet = Packet.new(nil, nil)
        packet.buffer = "\x01\x02\x03\x04"
        @interface.write(packet)
        expect(packet.buffer).to eql("\x01\x02\x03\x04")
        expect($buffer).to eql("\xBA\x5E\xBA\x11\x09\x01\x02\x03\x04")
      end
    end

    describe "write_details" do
      it "returns the protocol configuration details" do
        @interface.add_protocol(LengthProtocol, [16, 32, 16, 2, 'LITTLE_ENDIAN', 2, '0xDEADBEEF', 100, true], :READ_WRITE)
        protocol = @interface.write_protocols[0]
        details = protocol.write_details
        
        expect(details).to be_a(Hash)
        expect(details['name']).to eq('LengthProtocol')
        expect(details.key?('write_data_input_time')).to be true
        expect(details.key?('write_data_input')).to be true
        expect(details.key?('write_data_output_time')).to be true
        expect(details.key?('write_data_output')).to be true
      end

      it "includes length protocol-specific configuration" do
        @interface.add_protocol(LengthProtocol, [8, 16, 4, 1, 'BIG_ENDIAN', 0, nil, 200, false], :READ_WRITE)
        protocol = @interface.write_protocols[0]
        details = protocol.write_details
        
        expect(details['length_bit_offset']).to eq(8)
        expect(details['length_bit_size']).to eq(16)
        expect(details['length_value_offset']).to eq(4)
        expect(details['length_bytes_per_count']).to eq(1)
        expect(details['length_endianness']).to eq(:BIG_ENDIAN)
        expect(details['max_length']).to eq(200)
      end
    end

    describe "read_details" do
      it "returns the protocol configuration details" do
        @interface.add_protocol(LengthProtocol, [0, 8, 0, 1, 'BIG_ENDIAN'], :READ_WRITE)
        protocol = @interface.read_protocols[0]
        details = protocol.read_details
        
        expect(details).to be_a(Hash)
        expect(details['name']).to eq('LengthProtocol')
        expect(details.key?('read_data_input_time')).to be true
        expect(details.key?('read_data_input')).to be true
        expect(details.key?('read_data_output_time')).to be true
        expect(details.key?('read_data_output')).to be true
      end

      it "includes length protocol-specific configuration" do
        @interface.add_protocol(LengthProtocol, [16, 32, 8, 2, 'LITTLE_ENDIAN', 4, '0x1234', 150, true], :READ_WRITE)
        protocol = @interface.read_protocols[0]
        details = protocol.read_details
        
        expect(details['length_bit_offset']).to eq(16)
        expect(details['length_bit_size']).to eq(32)
        expect(details['length_value_offset']).to eq(8)
        expect(details['length_bytes_per_count']).to eq(2)
        expect(details['length_endianness']).to eq(:LITTLE_ENDIAN)
        expect(details['max_length']).to eq(150)
      end
    end
  end
end
