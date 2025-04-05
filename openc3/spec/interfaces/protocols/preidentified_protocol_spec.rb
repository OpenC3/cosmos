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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/interfaces/protocols/preidentified_protocol'
require 'openc3/interfaces/interface'
require 'openc3/streams/stream'

module OpenC3
  describe PreidentifiedProtocol do
    before(:all) do
      setup_system()
      @log_dir = File.expand_path(File.join(SPEC_DIR, 'install', 'outputs', 'logs'))
      FileUtils.mkdir_p(@log_dir)
    end

    before(:each) do
      $buffer = ''
      @interface = StreamInterface.new
      allow(@interface).to receive(:connected?) { true }
    end

    saved_verbose = $VERBOSE; $VERBOSE = nil
    class PreStream < Stream
      def connect; end
      def connected?; true; end
      def disconnect; end
      def read; $buffer; end
      def write(data); $buffer = data; end
    end
    $VERBOSE = saved_verbose

    it "handles receiving a bad packet length" do
      @interface.instance_variable_set(:@stream, PreStream.new)
      @interface.add_protocol(PreidentifiedProtocol, [nil, 5, 4], :READ_WRITE)
      pkt = System.telemetry.packet("SYSTEM", "META")
      time = Time.new(2020, 1, 31, 12, 15, 30.5)
      pkt.received_time = time
      @interface.write(pkt)
      expect { @interface.read }.to raise_error(RuntimeError)
    end

    describe "initialize" do
      it "initializes attributes" do
        @interface.add_protocol(PreidentifiedProtocol, ['0xDEADBEEF', 100, 4], :READ_WRITE)
        expect(@interface.read_protocols[0].instance_variable_get(:@mode)).to eq 4
        expect(@interface.read_protocols[0].instance_variable_get(:@data)).to eq ''
        expect(@interface.read_protocols[0].instance_variable_get(:@sync_pattern)).to eq "\xDE\xAD\xBE\xEF"
        expect(@interface.read_protocols[0].instance_variable_get(:@max_length)).to eq 100
      end
    end

    describe "write" do
      [true, false].each do |stored|
        context "with stored #{stored}" do
          [4, 5, 6].each do |mode|
            it "writes a packet in mode #{mode}" do
              @interface = StreamInterface.new
              @interface.instance_variable_set(:@stream, PreStream.new)
              @interface.add_protocol(PreidentifiedProtocol, [nil, 5, mode], :READ_WRITE)
              pkt = System.telemetry.packet("SYSTEM", "META")
              packet_time = Time.new(2020, 1, 31, 12, 15, 30.5)
              received_time = Time.new(2025, 1, 31, 12, 15, 30.5)
              pkt.packet_time = packet_time
              pkt.received_time = received_time
              pkt.stored = stored
              pkt.extra = nil
              @interface.write(pkt)
              case mode
              when 4
                flags = $buffer[0..0].unpack('C')[0]
                if stored
                  expect(flags & 0x80).to eql 0x80
                else
                  expect(flags & 0x80).to eql 0
                end
                expect($buffer[1..4].unpack('N')[0]).to eql received_time.to_f.to_i
                expect($buffer[5..8].unpack('N')[0]).to eql 500000
                offset = 9
                tgt_name_length = $buffer[offset].unpack('C')[0]
                offset += 1 # for the length field
                expect($buffer[offset...(offset + tgt_name_length)]).to eql 'SYSTEM'
                offset += tgt_name_length
                pkt_name_length = $buffer[offset].unpack('C')[0]
                offset += 1 # for the length field
                expect($buffer[offset...(offset + pkt_name_length)]).to eql 'META'
                offset += pkt_name_length
                expect($buffer[offset..(offset + 3)].unpack('N')[0]).to eql pkt.buffer.length
                offset += 4
                expect($buffer[offset..-1]).to eql pkt.buffer
              when 5, 6
                length = $buffer[0..3].unpack('N')[0]
                expect(length).to eql($buffer.length - 4) # 4 bytes for the length field
                flags = $buffer[4..6].unpack('n')[0]
                if stored
                  expect(flags & 0x400).to eql 0x400
                else
                  expect(flags & 0x400).to eql 0
                end
                index = $buffer[6..8].unpack('n')[0]
                expect(index).to eql 0
                time = $buffer[8..16].unpack('Q>')[0]
                expect(time).to eql packet_time.to_nsec_from_epoch
                rx_time = $buffer[16..24].unpack('Q>')[0]
                expect(rx_time).to eql received_time.to_nsec_from_epoch

                expect($buffer[24..-1]).to eql pkt.buffer
              else
                # Do nothing
              end
            end
          end
        end
      end

      [4, 5, 6].each do |mode|
        it "writes a packet in mode #{mode} with extra" do
          @interface = StreamInterface.new
          @interface.instance_variable_set(:@stream, PreStream.new)
          @interface.add_protocol(PreidentifiedProtocol, [nil, 5, mode], :READ_WRITE)
          pkt = System.telemetry.packet("SYSTEM", "META")
          packet_time = Time.new(2020, 1, 31, 12, 15, 30.5)
          received_time = Time.new(2025, 1, 31, 12, 15, 30.5)
          pkt.packet_time = packet_time
          pkt.received_time = received_time
          extra_data = { "vcid" => 2 }
          pkt.stored = false
          pkt.extra = extra_data
          @interface.write(pkt)
          case mode
          when 4
            offset = 0
            expect($buffer[0..0].unpack('C')[0]).to eql 0x40
            json_extra = extra_data.as_json(:allow_nan => true).to_json(:allow_nan => true)
            offset += 1
            expect($buffer[offset..(offset + 3)].unpack('N')[0]).to eql json_extra.length
            offset += 4
            expect($buffer[offset..(offset + json_extra.length - 1)]).to eql json_extra
            offset += json_extra.length
            expect($buffer[offset..(offset + 3)].unpack('N')[0]).to eql received_time.to_f.to_i
            expect($buffer[(offset + 4)..(offset + 7)].unpack('N')[0]).to eql 500000
            offset = offset += 8 # time fields
            tgt_name_length = $buffer[offset].unpack('C')[0]
            offset += 1 # for the length field
            expect($buffer[offset...(offset + tgt_name_length)]).to eql 'SYSTEM'
            offset += tgt_name_length
            pkt_name_length = $buffer[offset].unpack('C')[0]
            offset += 1 # for the length field
            expect($buffer[offset...(offset + pkt_name_length)]).to eql 'META'
            offset += pkt_name_length
            expect($buffer[offset..(offset + 3)].unpack('N')[0]).to eql pkt.buffer.length
            offset += 4
            expect($buffer[offset..-1]).to eql pkt.buffer
          when 5, 6
            length = $buffer[0..3].unpack('N')[0]
            expect(length).to eql($buffer.length - 4) # 4 bytes for the length field
            flags = $buffer[4..6].unpack('n')[0]
            index = $buffer[6..8].unpack('n')[0]
            expect(index).to eql 0
            time = $buffer[8..16].unpack('Q>')[0]
            expect(time).to eql packet_time.to_nsec_from_epoch
            rx_time = $buffer[16..24].unpack('Q>')[0]
            expect(rx_time).to eql received_time.to_nsec_from_epoch
            extra_length = $buffer[24..28].unpack('N')[0]
            extra = $buffer[28..(28 + extra_length - 1)]
            decoded = CBOR.decode(extra)
            expect(decoded).to eql extra_data
            expect($buffer[(28 + extra_length)..-1]).to eql pkt.buffer
          else
            # Do nothing
          end
        end
      end
    end

    describe "read from file" do
      before(:each) do
        @files = {}
        s3 = double("AwsS3Client").as_null_object
        allow(Aws::S3::Client).to receive(:new).and_return(s3)
        allow(s3).to receive(:put_object) do |args|
          @files[File.basename(args[:key])] = args[:body].read
        end
      end

      it "reads handles a file header and reads packets" do
        pkt1_time = Time.now.to_nsec_from_epoch
        plw = PacketLogWriter.new(@log_dir, 'test')
        plw.write(:RAW_PACKET, :TLM, 'TGT1', 'PKT1', pkt1_time, false, "\x01\x02", nil, '0-0')
        pkt2_time = pkt1_time + 1_000_000_000
        plw.write(:RAW_PACKET, :TLM, 'TGT2', 'PKT2', pkt2_time, false, "\x03\x04", nil, '0-0')
        plw.shutdown
        sleep 0.1 # Allow for shutdown thread "copy" to S3

        filename = @files.keys[0]
        $buffer = Zlib::GzipReader.new(StringIO.new(@files[filename])).read

        @interface = StreamInterface.new
        @interface.instance_variable_set(:@stream, PreStream.new)
        @interface.instance_variable_set(:@filename, 'FILENAME')
        @interface.add_protocol(PreidentifiedProtocol, [nil, nil, 5, true], :READ_WRITE)

        packet = @interface.read
        expect(packet.target_name).to eql 'TGT1'
        expect(packet.packet_name).to eql 'PKT1'
        expect(packet.identified?).to be true
        expect(packet.defined?).to be false
        expect(packet.buffer).to eql "\x01\x02"
        expect(packet.received_time.to_nsec_from_epoch).to eql pkt1_time
        expect(packet.stored).to be false
        expect(packet.extra).to be nil

        packet = @interface.read
        expect(packet.target_name).to eql 'TGT2'
        expect(packet.packet_name).to eql 'PKT2'
        expect(packet.identified?).to be true
        expect(packet.defined?).to be false
        expect(packet.buffer).to eql "\x03\x04"
        expect(packet.received_time.to_nsec_from_epoch).to eql pkt2_time
        expect(packet.stored).to be false
        expect(packet.extra).to be nil

        # The stream will just keep reading the $buffer so we get the same packet
        packet = @interface.read
        expect(packet.target_name).to eql 'TGT1'
        expect(packet.packet_name).to eql 'PKT1'
      end
    end

    it "creates a packet header with stored and extra" do
      @interface.instance_variable_set(:@stream, PreStream.new)
      @interface.add_protocol(PreidentifiedProtocol, [nil, 5, 4], :READ_WRITE)
      pkt = System.telemetry.packet("SYSTEM", "META").clone
      time = Time.new(2020, 1, 31, 12, 15, 30.5)
      pkt.received_time = time
      pkt.stored = true
      extra_data = { "vcid" => 2 }
      pkt.extra = extra_data
      @interface.write(pkt)
      offset = 0
      expect($buffer[0..0].unpack('C')[0]).to eql 0xC0
      json_extra = extra_data.as_json(:allow_nan => true).to_json(:allow_nan => true)
      offset += 1
      expect($buffer[offset..(offset + 3)].unpack('N')[0]).to eql json_extra.length
      offset += 4
      expect($buffer[offset..(offset + json_extra.length - 1)]).to eql json_extra
      offset += json_extra.length
      expect($buffer[offset..(offset + 3)].unpack('N')[0]).to eql time.to_f.to_i
      expect($buffer[(offset + 4)..(offset + 7)].unpack('N')[0]).to eql 500000
      offset = offset += 8 # time fields
      tgt_name_length = $buffer[offset].unpack('C')[0]
      offset += 1 # for the length field
      expect($buffer[offset...(offset + tgt_name_length)]).to eql 'SYSTEM'
      offset += tgt_name_length
      pkt_name_length = $buffer[offset].unpack('C')[0]
      offset += 1 # for the length field
      expect($buffer[offset...(offset + pkt_name_length)]).to eql 'META'
      offset += pkt_name_length
      expect($buffer[offset..(offset + 3)].unpack('N')[0]).to eql pkt.buffer.length
      offset += 4
      expect($buffer[offset..-1]).to eql pkt.buffer
    end

    it "handles a sync pattern" do
      @interface.instance_variable_set(:@stream, PreStream.new)
      @interface.add_protocol(PreidentifiedProtocol, ["DEAD", 5, 4], :READ_WRITE)
      pkt = System.telemetry.packet("SYSTEM", "META")
      time = Time.new(2020, 1, 31, 12, 15, 30.5)
      pkt.received_time = time
      @interface.write(pkt)
      expect($buffer[0..1]).to eql("\xDE\xAD")
      expect($buffer[2..2].unpack('C')[0]).to eql 0
      expect($buffer[3..6].unpack('N')[0]).to eql time.to_f.to_i
      expect($buffer[7..10].unpack('N')[0]).to eql 500000
      offset = 11
      tgt_name_length = $buffer[offset].unpack('C')[0]
      offset += 1 # for the length field
      expect($buffer[offset...(offset + tgt_name_length)]).to eql 'SYSTEM'
      offset += tgt_name_length
      pkt_name_length = $buffer[offset].unpack('C')[0]
      offset += 1 # for the length field
      expect($buffer[offset...(offset + pkt_name_length)]).to eql 'META'
      offset += pkt_name_length
      expect($buffer[offset..(offset + 3)].unpack('N')[0]).to eql pkt.buffer.length
      offset += 4
      expect($buffer[offset..-1]).to eql pkt.buffer
    end

    it "handles a sync pattern with stored and extra" do
      @interface.instance_variable_set(:@stream, PreStream.new)
      @interface.add_protocol(PreidentifiedProtocol, ["DEAD", 5, 4], :READ_WRITE)
      pkt = System.telemetry.packet("SYSTEM", "META").clone
      time = Time.new(2020, 1, 31, 12, 15, 30.5)
      pkt.received_time = time
      pkt.stored = true
      extra_data = { "vcid" => 2 }
      pkt.extra = extra_data
      @interface.write(pkt)
      expect($buffer[0..1]).to eql("\xDE\xAD")
      offset = 2
      expect($buffer[2..2].unpack('C')[0]).to eql 0xC0
      json_extra = extra_data.as_json(:allow_nan => true).to_json(:allow_nan => true)
      offset += 1
      expect($buffer[offset..(offset + 3)].unpack('N')[0]).to eql json_extra.length
      offset += 4
      expect($buffer[offset..(offset + json_extra.length - 1)]).to eql json_extra
      offset += json_extra.length
      expect($buffer[offset..(offset + 3)].unpack('N')[0]).to eql time.to_f.to_i
      expect($buffer[(offset + 4)..(offset + 7)].unpack('N')[0]).to eql 500000
      offset = offset += 8 # time fields
      tgt_name_length = $buffer[offset].unpack('C')[0]
      offset += 1 # for the length field
      expect($buffer[offset...(offset + tgt_name_length)]).to eql 'SYSTEM'
      offset += tgt_name_length
      pkt_name_length = $buffer[offset].unpack('C')[0]
      offset += 1 # for the length field
      expect($buffer[offset...(offset + pkt_name_length)]).to eql 'META'
      offset += pkt_name_length
      expect($buffer[offset..(offset + 3)].unpack('N')[0]).to eql pkt.buffer.length
      offset += 4
      expect($buffer[offset..-1]).to eql pkt.buffer
    end
  end

  describe "read" do
    it "handles a sync pattern" do
      @interface = StreamInterface.new
      @interface.instance_variable_set(:@stream, PreStream.new)
      @interface.add_protocol(PreidentifiedProtocol, ["0x1234", nil, 4], :READ_WRITE)
      pkt = System.telemetry.packet("SYSTEM", "META")
      pkt.write("OPENC3_VERSION", "TEST")
      time = Time.new(2020, 1, 31, 12, 15, 30.5)
      pkt.received_time = time
      @interface.write(pkt)
      expect($buffer[0]).to eql "\x12"
      expect($buffer[1]).to eql "\x34"
      packet = @interface.read
      expect(packet.target_name).to eql 'SYSTEM'
      expect(packet.packet_name).to eql 'META'
      expect(packet.identified?).to be true
      expect(packet.defined?).to be false

      pkt2 = System.telemetry.update!("SYSTEM", "META", packet.buffer)
      expect(pkt2.read('OPENC3_VERSION')).to eql 'TEST'
      expect(pkt2.identified?).to be true
      expect(pkt2.defined?).to be true
    end

    it "returns a packet" do
      @interface = StreamInterface.new
      @interface.instance_variable_set(:@stream, PreStream.new)
      @interface.add_protocol(PreidentifiedProtocol, [nil, nil, 4], :READ_WRITE)
      pkt = System.telemetry.packet("SYSTEM", "META")
      pkt.write("OPENC3_VERSION", "TEST")
      time = Time.new(2020, 1, 31, 12, 15, 30.5)
      pkt.received_time = time
      @interface.write(pkt)
      packet = @interface.read
      expect(packet.target_name).to eql 'SYSTEM'
      expect(packet.packet_name).to eql 'META'
      expect(packet.identified?).to be true
      expect(packet.defined?).to be false

      pkt2 = System.telemetry.update!("SYSTEM", "META", packet.buffer)
      expect(pkt2.read('OPENC3_VERSION')).to eql 'TEST'
      expect(pkt2.identified?).to be true
      expect(pkt2.defined?).to be true
    end
  end
end
