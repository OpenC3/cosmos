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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/interfaces/udp_interface'
require 'openc3/io/udp_sockets'

module OpenC3
  describe UdpInterface do
    describe "initialize" do
      it "initializes the instance variables" do
        i = UdpInterface.new('localhost', '8888', '8889', '8890', 'localhost', '64', '5', '5', 'localhost')
        expect(i.instance_variable_get("@hostname")).to eql '127.0.0.1'
        expect(i.instance_variable_get("@interface_address")).to eql '127.0.0.1'
        expect(i.instance_variable_get("@bind_address")).to eql '127.0.0.1'
        i = UdpInterface.new('10.10.10.1', '8888', '8889', '8890', '10.10.10.2', '64', '5', '5', '10.10.10.3')
        expect(i.instance_variable_get("@hostname")).to eql '10.10.10.1'
        expect(i.instance_variable_get("@interface_address")).to eql '10.10.10.2'
        expect(i.instance_variable_get("@bind_address")).to eql '10.10.10.3'
      end

      it "is not writeable if no write port given" do
        i = UdpInterface.new('localhost', 'nil', '8889')
        expect(i.name).to eql "UdpInterface"
        expect(i.write_allowed?).to be false
        expect(i.write_raw_allowed?).to be false
        expect(i.read_allowed?).to be true
      end

      it "is not readable if no read port given" do
        i = UdpInterface.new('localhost', '8888', 'nil')
        expect(i.name).to eql "UdpInterface"
        expect(i.write_allowed?).to be true
        expect(i.write_raw_allowed?).to be true
        expect(i.read_allowed?).to be false
      end
    end

    describe "connection_string" do
      it "builds a human readable connection string" do
        i = UdpInterface.new('123.4.5.6', '8888', '8889', '8890', '456.7.8.9', '64', '5', '5', '1.2.3.4')
        expect(i.connection_string).to eql "123.4.5.6:8888 (write dest port) 8890 (write src port) 123.4.5.6:8889 (read) 456.7.8.9 (interface addr) 1.2.3.4 (bind addr)"

        i = UdpInterface.new('localhost', 'nil', '8889')
        expect(i.connection_string).to eql "127.0.0.1:8889 (read)"

        i = UdpInterface.new('localhost', '8888', 'nil')
        expect(i.connection_string).to eql "127.0.0.1:8888 (write dest port)"
      end
    end

    describe "connect, connected?, disconnect" do
      it "creates a UdpWriteSocket and UdpReadSocket if both given" do
        i = UdpInterface.new('localhost', '8888', '8889')
        expect(i.connected?).to be false
        i.connect
        expect(i.connected?).to be true
        expect(i.instance_variable_get(:@write_socket)).to_not be_nil
        expect(i.instance_variable_get(:@read_socket)).to_not be_nil
        i.disconnect
        expect(i.connected?).to be false
        expect(i.instance_variable_get(:@write_socket)).to be_nil
        expect(i.instance_variable_get(:@read_socket)).to be_nil
      end

      it "creates a UdpWriteSocket if write port given" do
        i = UdpInterface.new('localhost', '8888', 'nil')
        expect(i.connected?).to be false
        i.connect
        expect(i.connected?).to be true
        expect(i.instance_variable_get(:@write_socket)).to_not be_nil
        expect(i.instance_variable_get(:@read_socket)).to be_nil
        i.disconnect
        expect(i.connected?).to be false
        expect(i.instance_variable_get(:@write_socket)).to be_nil
        expect(i.instance_variable_get(:@read_socket)).to be_nil
      end

      it "creates a UdpReadSocket if read port given" do
        i = UdpInterface.new('localhost', 'nil', '8889')
        expect(i.connected?).to be false
        i.connect
        expect(i.connected?).to be true
        expect(i.instance_variable_get(:@write_socket)).to be_nil
        expect(i.instance_variable_get(:@read_socket)).to_not be_nil
        i.disconnect
        expect(i.connected?).to be false
        expect(i.instance_variable_get(:@write_socket)).to be_nil
        expect(i.instance_variable_get(:@read_socket)).to be_nil
      end

      it "creates one socket if read_port == write_src_port" do
        i = UdpInterface.new('localhost', '8888', '8889', '8889')
        expect(i.connected?).to be false
        i.connect
        expect(i.connected?).to be true
        expect(i.instance_variable_get(:@write_socket)).to_not be_nil
        expect(i.instance_variable_get(:@read_socket)).to_not be_nil
        expect(i.instance_variable_get(:@read_socket)).to eql i.instance_variable_get(:@write_socket)
        i.disconnect
        expect(i.connected?).to be false
        expect(i.instance_variable_get(:@write_socket)).to be_nil
        expect(i.instance_variable_get(:@read_socket)).to be_nil
      end
    end

    describe "read" do
      it "stops the read thread if there is an IOError" do
        read = double("read")
        allow(read).to receive(:read).and_raise(IOError)
        expect(UdpReadSocket).to receive(:new).and_return(read)
        i = UdpInterface.new('localhost', 'nil', '8889')
        i.connect
        thread = Thread.new { i.read }
        sleep 0.1
        expect(thread.stop?).to be true
        OpenC3.kill_thread(nil, thread)
      end

      it "counts the packets received" do
        write = UdpWriteSocket.new('127.0.0.1', 8889)
        i = UdpInterface.new('127.0.0.1', 'nil', '8889')
        i.connect
        expect(i.read_count).to eql 0
        expect(i.bytes_read).to eql 0
        packet = nil
        t = Thread.new { packet = i.read }
        write.write("\x00\x01\x02\x03")
        t.join
        expect(i.read_count).to eql 1
        expect(i.bytes_read).to eql 4
        expect(packet.buffer).to eql "\x00\x01\x02\x03"
        t = Thread.new { packet = i.read }
        write.write("\x04\x05\x06\x07")
        t.join
        expect(i.read_count).to eql 2
        expect(i.bytes_read).to eql 8
        expect(packet.buffer).to eql "\x04\x05\x06\x07"
        i.disconnect
        OpenC3.close_socket(write)
      end

      it "logs the raw data" do
        thread = double("Thread")
        allow(thread).to receive(:join)
        allow(BucketUtilities).to receive(:move_log_file_to_bucket).and_return(thread)

        write = UdpWriteSocket.new('127.0.0.1', 8889)
        i = UdpInterface.new('127.0.0.1', 'nil', '8889')
        i.connect
        i.start_raw_logging
        expect(i.stream_log_pair.read_log.logging_enabled).to be true
        t = Thread.new { i.read }
        write.write("\x00\x01\x02\x03")
        t.join
        filename = i.stream_log_pair.read_log.filename
        i.stop_raw_logging
        expect(i.stream_log_pair.read_log.logging_enabled).to be false
        expect(File.read(filename)).to eq "\x00\x01\x02\x03"
        i.disconnect
        OpenC3.close_socket(write)
        i.stream_log_pair.shutdown
        sleep 0.01
      end
    end

    describe "write" do
      it "complains if write_dest not given" do
        i = UdpInterface.new('localhost', 'nil', '8889')
        expect { i.write(Packet.new('', '')) }.to raise_error(/not connected for write/)
      end

      it "complains if the server is not connected" do
        i = UdpInterface.new('localhost', '8888', 'nil')
        expect { i.write(Packet.new('', '')) }.to raise_error(/Interface not connected/)
      end

      it "counts the packets and bytes written" do
        read = UdpReadSocket.new(8888, 'localhost')
        i = UdpInterface.new('localhost', '8888', 'nil')
        i.connect
        expect(i.write_count).to eql 0
        pkt = Packet.new('tgt', 'pkt')
        pkt.buffer = "\x00\x01\x02\x03"
        i.write(pkt)
        data = read.read
        expect(i.write_count).to eql 1
        expect(i.bytes_written).to eql 4
        expect(data).to eq "\x00\x01\x02\x03"
        i.disconnect
        OpenC3.close_socket(read)
      end

      it "logs the raw data" do
        thread = double("Thread")
        allow(thread).to receive(:join)
        allow(BucketUtilities).to receive(:move_log_file_to_bucket).and_return(thread)

        read = UdpReadSocket.new(8888, 'localhost')
        i = UdpInterface.new('localhost', '8888', 'nil')
        i.connect
        i.start_raw_logging
        expect(i.stream_log_pair.write_log.logging_enabled).to be true
        pkt = Packet.new('tgt', 'pkt')
        pkt.buffer = "\x00\x01\x02\x03"
        i.write(pkt)
        _ = read.read
        filename = i.stream_log_pair.write_log.filename
        i.stop_raw_logging
        expect(i.stream_log_pair.write_log.logging_enabled).to be false
        expect(File.read(filename)).to eq "\x00\x01\x02\x03"
        i.disconnect
        OpenC3.close_socket(read)
        i.stream_log_pair.shutdown
        sleep 0.01
      end
    end

    describe "write_raw" do
      it "complains if write_dest not given" do
        i = UdpInterface.new('localhost', 'nil', '8889')
        expect { i.write_raw('') }.to raise_error(/not connected for write/)
      end

      it "complains if the server is not connected" do
        i = UdpInterface.new('localhost', '8888', 'nil')
        expect { i.write_raw('') }.to raise_error(/Interface not connected/)
      end

      it "counts the bytes written" do
        read = UdpReadSocket.new(8888, 'localhost')
        i = UdpInterface.new('localhost', '8888', 'nil')
        i.connect
        expect(i.write_count).to eql 0
        expect(i.bytes_written).to eql 0
        i.write_raw("\x04\x05\x06\x07")
        data = read.read
        expect(i.write_count).to eql 0
        expect(i.bytes_written).to eql 4
        expect(data).to eq "\x04\x05\x06\x07"
        i.disconnect
        OpenC3.close_socket(read)
      end

      it "logs the raw data" do
        thread = double("Thread")
        allow(thread).to receive(:join)
        allow(BucketUtilities).to receive(:move_log_file_to_bucket).and_return(thread)

        read = UdpReadSocket.new(8888, 'localhost')
        i = UdpInterface.new('localhost', '8888', 'nil')
        i.connect
        i.start_raw_logging
        expect(i.stream_log_pair.write_log.logging_enabled).to be true
        i.write_raw("\x00\x01\x02\x03")
        _ = read.read
        filename = i.stream_log_pair.write_log.filename
        i.stop_raw_logging
        expect(i.stream_log_pair.write_log.logging_enabled).to be false
        expect(File.read(filename)).to eq "\x00\x01\x02\x03"
        i.disconnect
        OpenC3.close_socket(read)
        i.stream_log_pair.shutdown
        sleep 0.01
      end
    end
  end

  describe "details" do
    it "returns detailed interface information" do
      i = UdpInterface.new('localhost', '8888', '8889', '8890', '127.0.0.1', '64', '5.0', '10.0', '0.0.0.0')

      details = i.details

      expect(details).to be_a(Hash)
      expect(details['hostname']).to eql('127.0.0.1')
      expect(details['write_dest_port']).to eql(8888)
      expect(details['read_port']).to eql(8889)
      expect(details['write_src_port']).to eql(8890)
      expect(details['interface_address']).to eql('127.0.0.1')
      expect(details['ttl']).to eql(64)
      expect(details['write_timeout']).to eql(5.0)
      expect(details['read_timeout']).to eql(10.0)
      expect(details['bind_address']).to eql('0.0.0.0')

      # Check that base interface details are included
      expect(details['name']).to eql('UdpInterface')
      expect(details).to have_key('read_allowed')
      expect(details).to have_key('write_allowed')
      expect(details).to have_key('write_raw_allowed')
      expect(details).to have_key('options')
    end

    it "handles nil values correctly" do
      i = UdpInterface.new('localhost', 'nil', '8889')

      details = i.details

      expect(details['hostname']).to eql('127.0.0.1')
      expect(details['write_dest_port']).to be_nil
      expect(details['read_port']).to eql(8889)
      expect(details['write_src_port']).to be_nil
      expect(details['interface_address']).to be_nil
    end
  end
end
