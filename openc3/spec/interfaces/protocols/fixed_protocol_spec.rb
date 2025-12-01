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
require 'openc3/interfaces/protocols/fixed_protocol'
require 'openc3/interfaces/interface'
require 'openc3/interfaces/stream_interface'
require 'openc3/streams/stream'
require 'tempfile'

module OpenC3
  describe FixedProtocol do
    before(:each) do
      @interface = StreamInterface.new
      allow(@interface).to receive(:connected?) { true }
      allow(@interface).to receive(:disconnect) { nil }
    end

    describe "initialize" do
      it "initializes attributes" do
        @interface.add_protocol(FixedProtocol, [2, 1, '0xDEADBEEF', false, true], :READ_WRITE)
        expect(@interface.read_protocols[0].instance_variable_get(:@data)).to eq ''
        expect(@interface.read_protocols[0].instance_variable_get(:@min_id_size)).to eq 2
        expect(@interface.read_protocols[0].instance_variable_get(:@discard_leading_bytes)).to eq 1
        expect(@interface.read_protocols[0].instance_variable_get(:@sync_pattern)).to eq "\xDE\xAD\xBE\xEF"
        expect(@interface.read_protocols[0].instance_variable_get(:@telemetry)).to be false
        expect(@interface.read_protocols[0].instance_variable_get(:@fill_fields)).to be true
      end
    end

    describe "read_data" do
      before(:all) do
        setup_system()
      end

      $index = 0
      class FixedStream < Stream
        def connect; end

        def connected?; true; end

        def read
          case $index
          when 0
            "\x00" # UNKNOWN
          when 1
            "\x01" # SYSTEM META
          when 2
            "\x02" # SYSTEM LIMITS
          end
        end
      end

      it "returns unknown packets" do
        @interface.add_protocol(FixedProtocol, [1], :READ)
        @interface.instance_variable_set(:@stream, FixedStream.new)
        @interface.target_names = ['SYSTEM']
        @interface.cmd_target_names = ['SYSTEM']
        @interface.tlm_target_names = ['SYSTEM']
        # Initialize the read with a packet identified as SYSTEM META
        $index = 1
        packet = @interface.read
        expect(packet.received_time.to_f).to_not eql 0.0
        expect(packet.target_name).to eql "SYSTEM"
        expect(packet.packet_name).to eql "META"
        expect(packet.buffer[0]).to eql "\x01"
        # Return zeros which will not be identified
        $index = 0
        packet = @interface.read
        expect(packet.received_time.to_f).to eql 0.0
        expect(packet.target_name).to eql nil
        expect(packet.packet_name).to eql nil
        expect(packet.buffer).to eql "\x00"
      end

      it "raises an exception if unknown packet" do
        @interface.add_protocol(FixedProtocol, [1, 0, nil, true, false, true], :READ)
        @interface.instance_variable_set(:@stream, FixedStream.new)
        @interface.target_names = ['SYSTEM']
        @interface.cmd_target_names = ['SYSTEM']
        @interface.tlm_target_names = ['SYSTEM']
        expect { @interface.read }.to raise_error(/Unknown data/)
      end

      it "handles targets with no defined telemetry" do
        @interface.add_protocol(FixedProtocol, [1], :READ)
        @interface.instance_variable_set(:@stream, FixedStream.new)
        @interface.target_names = ['EMPTY']
        @interface.cmd_target_names = ['EMPTY']
        @interface.tlm_target_names = ['EMPTY']
        $index = 1
        packet = @interface.read
        expect(packet.received_time.to_f).to eql 0.0
        expect(packet.target_name).to eql nil
        expect(packet.packet_name).to eql nil
        expect(packet.buffer).to eql "\x01"
      end

      it "reads telemetry data from the stream" do
        @interface.add_protocol(FixedProtocol, [1], :READ_WRITE)
        @interface.instance_variable_set(:@stream, FixedStream.new)
        @interface.target_names = ['SYSTEM']
        @interface.cmd_target_names = ['SYSTEM']
        @interface.tlm_target_names = ['SYSTEM']
        $index = 1
        packet = @interface.read
        expect(packet.received_time.to_f).to be_within(0.1).of(Time.now.to_f)
        expect(packet.target_name).to eql 'SYSTEM'
        expect(packet.packet_name).to eql 'META'
        $index = 2
        packet = @interface.read
        expect(packet.received_time.to_f).to be_within(0.1).of(Time.now.to_f)
        expect(packet.target_name).to eql 'SYSTEM'
        expect(packet.packet_name).to eql 'LIMITS_CHANGE'
        System.telemetry.config.tlm_unique_id_mode['SYSTEM'] = true
        $index = 1
        packet = @interface.read
        expect(packet.received_time.to_f).to be_within(0.1).of(Time.now.to_f)
        expect(packet.target_name).to eql 'SYSTEM'
        expect(packet.packet_name).to eql 'META'
        $index = 2
        packet = @interface.read
        expect(packet.received_time.to_f).to be_within(0.1).of(Time.now.to_f)
        expect(packet.target_name).to eql 'SYSTEM'
        expect(packet.packet_name).to eql 'LIMITS_CHANGE'
        System.telemetry.config.tlm_unique_id_mode['SYSTEM'] = false
      end

      it "reads command data from the stream" do
        packet = System.commands.packet("SYSTEM", "STARTLOGGING")
        packet.restore_defaults
        $buffer = packet.buffer.clone
        class FixedStream2 < Stream
          def connect; end

          def connected?; true; end

          def read
            # Prepend a matching sync pattern to test the discard
            "\x1A\xCF\xFC\x1D\x55\x55" << $buffer
          end
        end
        # Require 8 bytes, discard 6 leading bytes, use 0x1ACFFC1D sync, telemetry = false (command)
        @interface.add_protocol(FixedProtocol, [8, 6, '0x1ACFFC1D', false], :READ_WRITE)
        @interface.instance_variable_set(:@stream, FixedStream2.new)
        @interface.target_names = ['SfYSTEM']
        @interface.cmd_target_names = ['SYSTEM']
        @interface.tlm_target_names = ['SYSTEM']
        System.commands.config.cmd_unique_id_mode['SYSTEM'] = false
        packet = @interface.read
        expect(packet.received_time.to_f).to be_within(0.01).of(Time.now.to_f)
        expect(packet.target_name).to eql 'SYSTEM'
        expect(packet.packet_name).to eql 'STARTLOGGING'
        expect(packet.buffer).to eql $buffer
        System.commands.config.cmd_unique_id_mode['SYSTEM'] = true
        packet = @interface.read
        expect(packet.received_time.to_f).to be_within(0.01).of(Time.now.to_f)
        expect(packet.target_name).to eql 'SYSTEM'
        expect(packet.packet_name).to eql 'STARTLOGGING'
        expect(packet.buffer).to eql $buffer
        System.commands.config.cmd_unique_id_mode['SYSTEM'] = false
      end

      it "breaks apart telemetry data from the stream" do
        packet = System.telemetry.packet("SYSTEM", "META")
        packet.write('PKTID', 1)
        packet.write('OPERATOR_NAME', 'RYAN')
        $buffer1 = packet.buffer.clone
        packet.write('OPERATOR_NAME', 'JASON')
        $buffer2 = packet.buffer.clone
        $buffer = "\x1A\xCF\xFC\x1D" + $buffer1 + "\x1A\xCF\xFC\x1D" + $buffer2
        $index = 0

        class FixedStream3 < Stream
          def connect; end

          def connected?; true; end

          def read
            # Send a byte a time
            $index += 1
            $buffer[$index - 1]
          end
        end
        # Require 5 bytes, discard 4 leading bytes, use 0x1ACFFC1D sync, telemetry = true
        @interface.add_protocol(FixedProtocol, [5, 4, '0x1ACFFC1D', true], :READ_WRITE)
        @interface.instance_variable_set(:@stream, FixedStream3.new)
        @interface.target_names = ['SYSTEM']
        @interface.cmd_target_names = ['SYSTEM']
        @interface.tlm_target_names = ['SYSTEM']
        packet = @interface.read
        expect(packet.received_time.to_f).to be_within(0.01).of(Time.now.to_f)
        expect(packet.target_name).to eql 'SYSTEM'
        expect(packet.packet_name).to eql 'META'
        expect(packet.buffer).to include('RYAN')
        packet = @interface.read
        expect(packet.received_time.to_f).to be_within(0.01).of(Time.now.to_f)
        expect(packet.target_name).to eql 'SYSTEM'
        expect(packet.packet_name).to eql 'META'
        expect(packet.buffer).to include('JASON')
        packet = @interface.read
        expect(packet).to be_nil
      end
    end

    describe "write_details" do
      it "returns the protocol configuration details" do
        @interface.add_protocol(FixedProtocol, [2, 1, '0xDEADBEEF', false, true], :READ_WRITE)
        protocol = @interface.write_protocols[0]
        details = protocol.write_details

        expect(details).to be_a(Hash)
        expect(details['name']).to eq('FixedProtocol')
        expect(details.key?('write_data_input_time')).to be true
        expect(details.key?('write_data_input')).to be true
        expect(details.key?('write_data_output_time')).to be true
        expect(details.key?('write_data_output')).to be true
      end

      it "includes fixed protocol-specific configuration" do
        @interface.add_protocol(FixedProtocol, [4, 2, '0x1234', true, false], :READ_WRITE)
        protocol = @interface.write_protocols[0]
        details = protocol.write_details

        expect(details['min_id_size']).to eq(4)
        expect(details['discard_leading_bytes']).to eq(2)
        expect(details['sync_pattern']).to eq("\x12\x34".inspect)
        expect(details['telemetry']).to eq(true)
        expect(details['fill_fields']).to eq(false)
      end
    end

    describe "read_details" do
      it "returns the protocol configuration details" do
        @interface.add_protocol(FixedProtocol, [1], :READ)
        protocol = @interface.read_protocols[0]
        details = protocol.read_details

        expect(details).to be_a(Hash)
        expect(details['name']).to eq('FixedProtocol')
        expect(details.key?('read_data_input_time')).to be true
        expect(details.key?('read_data_input')).to be true
        expect(details.key?('read_data_output_time')).to be true
        expect(details.key?('read_data_output')).to be true
      end

      it "includes fixed protocol-specific configuration" do
        @interface.add_protocol(FixedProtocol, [8, 6, '0x1ACFFC1D', false, true, false], :READ_WRITE)
        protocol = @interface.read_protocols[0]
        details = protocol.read_details

        expect(details['min_id_size']).to eq(8)
        expect(details['discard_leading_bytes']).to eq(6)
        expect(details['sync_pattern']).to eq("\x1A\xCF\xFC\x1D".inspect)
        expect(details['telemetry']).to eq(false)
        expect(details['fill_fields']).to eq(true)
      end
    end

    describe "packet identification with subpackets" do
      before(:all) do
        setup_system()
      end

      before(:each) do
        tf = Tempfile.new('unittest')
        tf.puts 'TELEMETRY TEST PKT1 BIG_ENDIAN "Normal Packet"'
        tf.puts '  APPEND_ID_ITEM item1 8 UINT 1 "Item1"'
        tf.puts '  APPEND_ITEM item2 8 UINT "Item2"'
        tf.puts 'TELEMETRY TEST SUB1 BIG_ENDIAN "Subpacket"'
        tf.puts '  SUBPACKET'
        tf.puts '  APPEND_ID_ITEM item1 8 UINT 10 "Item1"'
        tf.puts '  APPEND_ITEM item2 8 UINT "Item2"'
        tf.puts 'TELEMETRY TEST VIRTUAL_PKT BIG_ENDIAN "Virtual Packet"'
        tf.puts '  VIRTUAL'
        tf.puts '  APPEND_ID_ITEM item1 8 UINT 99 "Item1"'
        tf.puts '  APPEND_ITEM item2 8 UINT "Item2"'
        tf.close

        pc = PacketConfig.new
        pc.process_file(tf.path, "TEST")
        telemetry = Telemetry.new(pc)
        tf.unlink
        allow(System).to receive_message_chain(:telemetry).and_return(telemetry)
      end

      $subpacket_index = 0
      class SubpacketStream < Stream
        def connect; end
        def connected?; true; end

        def read
          case $subpacket_index
          when 0
            "\x01\x05" # Normal packet PKT1
          when 1
            "\x0A\x06" # Subpacket SUB1
          when 2
            "\x63\x07" # Virtual packet (should not be identified)
          else
            "\xFF\xFF" # Unknown
          end
        end
      end

      it "identifies normal packets but not subpackets" do
        @interface.add_protocol(FixedProtocol, [2, 0, nil, true], :READ)
        @interface.instance_variable_set(:@stream, SubpacketStream.new)
        @interface.target_names = ['TEST']
        @interface.tlm_target_names = ['TEST']

        $subpacket_index = 0
        packet = @interface.read
        expect(packet.target_name).to eql "TEST"
        expect(packet.packet_name).to eql "PKT1"
      end

      it "does not identify subpackets at interface level" do
        @interface.add_protocol(FixedProtocol, [2, 0, nil, true], :READ)
        @interface.instance_variable_set(:@stream, SubpacketStream.new)
        @interface.target_names = ['TEST']
        @interface.tlm_target_names = ['TEST']

        $subpacket_index = 1
        packet = @interface.read
        expect(packet.target_name).to be_nil
        expect(packet.packet_name).to be_nil
      end

      it "does not identify virtual packets" do
        @interface.add_protocol(FixedProtocol, [2, 0, nil, true], :READ)
        @interface.instance_variable_set(:@stream, SubpacketStream.new)
        @interface.target_names = ['TEST']
        @interface.tlm_target_names = ['TEST']

        $subpacket_index = 2
        packet = @interface.read
        expect(packet.target_name).to be_nil
        expect(packet.packet_name).to be_nil
      end
    end
  end
end
