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
require 'openc3/interfaces/protocols/ignore_packet_protocol'
require 'openc3/interfaces/interface'
require 'openc3/streams/stream'

module OpenC3
  describe IgnorePacketProtocol do
    before(:all) do
      setup_system()
    end

    before(:each) do
      $buffer = nil
      @interface = StreamInterface.new
      @interface.target_names = ['SYSTEM', 'INST']
      @interface.cmd_target_names = ['SYSTEM', 'INST']
      @interface.tlm_target_names = ['SYSTEM', 'INST']
      allow(@interface).to receive(:connected?) { true }
    end

    class IgnorePreStream < Stream
      def initialize(*args)
        super(*args)
        @run = true
      end

      def connect; @run = true; end

      def connected?; true; end

      def disconnect; @run = false; end

      def read
        if @run
          sleep(0.01)
          $buffer
        else
          raise "Done"
        end
      end

      def write(data); $buffer = data; end
    end

    describe "initialize" do
      it "complains if target is not given" do
        expect { @interface.add_protocol(IgnorePacketProtocol, [], :READ_WRITE) }.to raise_error(ArgumentError)
      end

      it "complains if packet is not given" do
        expect { @interface.add_protocol(IgnorePacketProtocol, ['SYSTEM'], :READ_WRITE) }.to raise_error(ArgumentError)
      end

      it "complains if the target is not found" do
        expect { @interface.add_protocol(IgnorePacketProtocol, ['BLAH', 'META'], :READ_WRITE) }.to raise_error(/target 'BLAH' does not exist/)
      end

      it "complains if the target is not found" do
        expect { @interface.add_protocol(IgnorePacketProtocol, ['SYSTEM', 'BLAH'], :READ_WRITE) }.to raise_error(/packet 'SYSTEM BLAH' does not exist/)
      end
    end

    describe "read" do
      it "ignores the packet specified" do
        stream = IgnorePreStream.new
        @interface.instance_variable_set(:@stream, stream)
        pkt = System.telemetry.packet("SYSTEM", "META")
        # Ensure the ID items are set so this packet can be identified
        pkt.id_items.each do |item|
          pkt.write_item(item, item.id_value)
        end
        pkt.received_time = Time.now
        $buffer = nil
        @interface.write(pkt)
        # Verify the write went out
        expect(pkt.buffer).to eql $buffer
        # Verify we read the packet back
        packet = @interface.read
        expect(packet.buffer).to eql $buffer

        # Now add the protocol to ignore the packet
        @interface.add_protocol(IgnorePacketProtocol, ['SYSTEM', 'META'], :READ)
        $buffer = nil
        @interface.write(pkt)
        packet = nil
        # Try to read the interface
        # We put this in a thread because it blocks and calls it continuously
        thread = Thread.new do
          begin
            packet = @interface.read
          rescue
          end
        end
        sleep 0.1
        @interface.disconnect
        stream.disconnect
        thread.join
        expect(packet).to be_nil
      end

      it "can be added multiple times to ignore different packets" do
        stream = IgnorePreStream.new
        @interface.instance_variable_set(:@stream, stream)

        pkt = System.telemetry.packet("INST", "HEALTH_STATUS")
        # Ensure the ID items are set so this packet can be identified
        pkt.id_items.each do |item|
          pkt.write_item(item, item.id_value)
        end
        pkt.received_time = Time.now
        $buffer = nil
        @interface.write(pkt)
        expect($buffer).to eql pkt.buffer

        # Verify we read the packet back
        packet = @interface.read
        expect(packet.buffer).to eql $buffer

        # Now add the protocol to ignore the packet
        @interface.add_protocol(IgnorePacketProtocol, ['INST', 'HEALTH_STATUS'], :READ)
        $buffer = nil
        @interface.write(pkt)
        expect($buffer).to eql pkt.buffer
        packet = nil
        # Try to read the interface
        # We put this in a thread because it calls it continuously
        thread = Thread.new do
          begin
            packet = @interface.read
          rescue
          end
        end
        sleep 0.1
        @interface.disconnect
        stream.disconnect
        thread.join
        @interface.connect
        stream.connect
        expect(packet).to be_nil

        # Add another protocol to ignore another packet
        @interface.add_protocol(IgnorePacketProtocol, ['INST', 'ADCS'], :READ)

        pkt = System.telemetry.packet("INST", "ADCS")
        # Ensure the ID items are set so this packet can be identified
        pkt.id_items.each do |item|
          pkt.write_item(item, item.id_value)
        end
        pkt.received_time = Time.now
        $buffer = nil
        @interface.write(pkt)
        expect($buffer).to eql pkt.buffer

        packet = nil
        # Try to read the interface
        # We put this in a thread because it calls it continuously
        thread = Thread.new do
          begin
            packet = @interface.read
          rescue
          end
        end
        sleep 0.1
        @interface.disconnect
        stream.disconnect
        thread.join
        @interface.connect
        stream.connect
        expect(packet).to be_nil

        pkt = System.telemetry.packet("INST", "PARAMS")
        # Ensure the ID items are set so this packet can be identified
        pkt.id_items.each do |item|
          pkt.write_item(item, item.id_value)
        end
        pkt.received_time = Time.now
        $buffer = nil
        @interface.write(pkt)
        # Verify the write went out
        expect($buffer).to eql pkt.buffer

        packet = @interface.read
        expect(packet.buffer).to eql pkt.buffer
      end
    end

    describe "write" do
      it "ignores the packet specified" do
        stream = IgnorePreStream.new
        @interface.instance_variable_set(:@stream, stream)
        @interface.add_protocol(IgnorePacketProtocol, ['SYSTEM', 'META'], :WRITE)
        pkt = System.telemetry.packet("SYSTEM", "META")
        pkt.write("OPENC3_VERSION", "TEST")
        pkt.received_time = Time.now
        $buffer = nil
        @interface.write(pkt)
        # Verify the write was ignored
        expect($buffer).to be_nil

        # Verify reading the interface works
        $buffer = pkt.buffer
        packet = @interface.read
        expect(packet.buffer).to eql $buffer
      end

      it "can be added multiple times to ignore different packets" do
        stream = IgnorePreStream.new
        @interface.instance_variable_set(:@stream, stream)
        @interface.add_protocol(IgnorePacketProtocol, ['INST', 'HEALTH_STATUS'], :WRITE)
        @interface.add_protocol(IgnorePacketProtocol, ['INST', 'ADCS'], :WRITE)

        pkt = System.telemetry.packet("INST", "HEALTH_STATUS")
        pkt.received_time = Time.now
        $buffer = nil
        @interface.write(pkt)
        # Verify the write was ignored
        expect($buffer).to be_nil

        pkt = System.telemetry.packet("INST", "ADCS")
        pkt.received_time = Time.now
        $buffer = nil
        @interface.write(pkt)
        # Verify the write was ignored
        expect($buffer).to be_nil

        pkt = System.telemetry.packet("INST", "PARAMS")
        pkt.received_time = Time.now
        $buffer = nil
        @interface.write(pkt)
        # Verify the write went out
        expect($buffer).to eql pkt.buffer
      end
    end

    describe "read/write" do
      it "ignores the packet specified" do
        stream = IgnorePreStream.new
        @interface.instance_variable_set(:@stream, stream)
        @interface.add_protocol(IgnorePacketProtocol, ['SYSTEM', 'META'], :READ_WRITE)
        pkt = System.telemetry.packet("SYSTEM", "META")
        pkt.write("OPENC3_VERSION", "TEST")
        pkt.received_time = Time.now
        $buffer = nil
        @interface.write(pkt)
        # Verify the write was ignored
        expect($buffer).to be_nil

        packet = nil
        # Try to read the interface
        thread = Thread.new do
          begin
            packet = @interface.read
          rescue
          end
        end
        sleep 0.1
        @interface.disconnect
        stream.disconnect
        thread.join
        expect(packet).to be_nil
      end

      it "reads and writes unknown packets" do
        stream = IgnorePreStream.new
        @interface.instance_variable_set(:@stream, stream)
        @interface.add_protocol(IgnorePacketProtocol, ['SYSTEM', 'META'], :READ_WRITE)
        $buffer = nil
        pkt = Packet.new("TGT", "PTK")
        pkt.append_item("ITEM", 8, :INT)
        pkt.write("ITEM", 33, :RAW)
        @interface.write(pkt)
        # Verify the write went out
        expect(pkt.buffer).to eql $buffer

        # Verify the read works
        packet = @interface.read
        expect(packet.buffer).to eq $buffer
      end
    end

    describe "write_details" do
      it "returns the protocol configuration details" do
        @interface.add_protocol(IgnorePacketProtocol, ['SYSTEM', 'META'], :READ_WRITE)
        protocol = @interface.write_protocols[0]
        details = protocol.write_details
        
        expect(details).to be_a(Hash)
        expect(details['name']).to eq('IgnorePacketProtocol')
        expect(details.key?('write_data_input_time')).to be true
        expect(details.key?('write_data_input')).to be true
        expect(details.key?('write_data_output_time')).to be true
        expect(details.key?('write_data_output')).to be true
      end

      it "includes ignore packet protocol-specific configuration" do
        @interface.add_protocol(IgnorePacketProtocol, ['INST', 'HEALTH_STATUS'], :READ_WRITE)
        protocol = @interface.write_protocols[0]
        details = protocol.write_details
        
        expect(details['target_name']).to eq('INST')
        expect(details['packet_name']).to eq('HEALTH_STATUS')
      end
    end

    describe "read_details" do
      it "returns the protocol configuration details" do
        @interface.add_protocol(IgnorePacketProtocol, ['SYSTEM', 'META'], :READ_WRITE)
        protocol = @interface.read_protocols[0]
        details = protocol.read_details
        
        expect(details).to be_a(Hash)
        expect(details['name']).to eq('IgnorePacketProtocol')
        expect(details.key?('read_data_input_time')).to be true
        expect(details.key?('read_data_input')).to be true
        expect(details.key?('read_data_output_time')).to be true
        expect(details.key?('read_data_output')).to be true
      end

      it "includes ignore packet protocol-specific configuration" do
        @interface.add_protocol(IgnorePacketProtocol, ['INST', 'ADCS'], :READ_WRITE)
        protocol = @interface.read_protocols[0]
        details = protocol.read_details
        
        expect(details['target_name']).to eq('INST')
        expect(details['packet_name']).to eq('ADCS')
      end
    end
  end
end
