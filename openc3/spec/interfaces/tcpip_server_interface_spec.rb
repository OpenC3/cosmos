# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/interfaces'
require 'openc3/interfaces/tcpip_server_interface'

module OpenC3
  describe TcpipServerInterface do
    def wait_until?(timeout)
      end_time = Time.now + timeout
      until yield
        return false if Time.now > end_time

        sleep(0.01)
      end
      true
    end

    describe "initialize" do
      it "initializes the instance variables" do
        i = TcpipServerInterface.new('8888', '8889', '5', '5', 'burst')
        expect(i.name).to eql "TcpipServerInterface"
      end

      it "is not writeable if no write port given" do
        i = TcpipServerInterface.new('nil', '8889', 'nil', '5', 'burst')
        expect(i.write_allowed?).to be false
        expect(i.write_raw_allowed?).to be false
        expect(i.read_allowed?).to be true
      end

      it "is not readable if no read port given" do
        i = TcpipServerInterface.new('8888', 'nil', '5', 'nil', 'burst')
        expect(i.write_allowed?).to be true
        expect(i.write_raw_allowed?).to be true
        expect(i.read_allowed?).to be false
      end
    end

    describe "connection_string" do
      it "builds a human readable connection string" do
        i = TcpipServerInterface.new('8889', '8889', 'nil', '5', 'burst')
        expect(i.connection_string).to eql "listening on 0.0.0.0:8889 (R/W)"

        i = TcpipServerInterface.new('8889', '8890', 'nil', '5', 'burst')
        expect(i.connection_string).to eql "listening on 0.0.0.0:8889 (write) 0.0.0.0:8890 (read)"

        i = TcpipServerInterface.new('8889', 'nil', 'nil', '5', 'burst')
        expect(i.connection_string).to eql "listening on 0.0.0.0:8889 (write)"

        i = TcpipServerInterface.new('nil', '8889', 'nil', '5', 'burst')
        expect(i.connection_string).to eql "listening on 0.0.0.0:8889 (read)"
      end
    end

    describe "read" do
      it "counts the packets received" do
        i = TcpipServerInterface.new('8888', '8889', '5', '5', 'burst')
        class << i
          def connected?; true; end
        end

        read_queue = i.instance_variable_get(:@read_queue)
        2.times { read_queue << Packet.new(nil, nil) }

        expect(i.read_count).to eql 0
        i.read
        expect(i.read_count).to eql 1
        i.read
        expect(i.read_count).to eql 2
      end

      it "does not count nil packets" do
        i = TcpipServerInterface.new('8888', '8889', '5', '5', 'burst')
        class << i
          def connected?; true; end
        end

        read_queue = i.instance_variable_get(:@read_queue)
        2.times { read_queue << nil }

        expect(i.read_count).to eql 0
        i.read
        expect(i.read_count).to eql 0
        i.read
        expect(i.read_count).to eql 0
      end
    end

    describe "write" do
      it "complains if the server is not connected" do
        i = TcpipServerInterface.new('8888', '8889', '5', '5', 'burst')
        class << i
          def connected?; false; end
        end
        expect { i.write(Packet.new('', '')) }.to raise_error(/Interface not connected/)
      end

      it "counts the packets written" do
        i = TcpipServerInterface.new('8888', '8889', '5', '5', 'burst')
        class << i
          def connected?; true; end
        end
        expect(i.write_count).to eql 0
        i.write(Packet.new('', ''))
        expect(i.write_count).to eql 1
        i.write(Packet.new('', ''))
        expect(i.write_count).to eql 2
      end
    end

    describe "write_raw" do
      it "complains if the server is not connected" do
        i = TcpipServerInterface.new('8888', '8889', '5', '5', 'burst')
        class << i
          def connected?; false; end
        end
        expect { i.write_raw("\x00") }.to raise_error(/Interface not connected/)
      end

      it "counts the bytes written" do
        i = TcpipServerInterface.new('8888', '8889', '5', '5', 'burst')
        i.connect
        sleep(1)
        wii = TcpipServerInterface::InterfaceInfo.new(TcpipServerInterface::ClientInterface.new, nil, nil)
        interface = wii.interface
        class << interface
          def connected?; true; end

          def write_interface(data, extra = nil); write_interface_base(data, extra); end

          def stream
            a = Object.new
            class << a
              def write_socket
                b = Object.new
                class << b
                  def recvfrom_nonblock(_amount)
                    raise Errno::EWOULDBLOCK
                  end
                end
                b
              end
            end
            a
          end
        end
        i.add_write_client(wii)
        begin
          expect(i.write_count).to eql 0
          expect(i.bytes_written).to eql 0
          i.write_raw("\x00\x01")
          expect(wait_until?(2) { i.bytes_written == 2 }).to be true
          expect(i.write_count).to eql 0
          i.write_raw("\x02")
          expect(wait_until?(2) { i.bytes_written == 3 }).to be true
          expect(i.write_count).to eql 0
        ensure
          i.disconnect
        end
      end
    end

    describe "set_option" do
      it "sets the listen address for the tcpip_server" do
        i = TcpipServerInterface.new('8888', '8888', '5', '5', 'burst')
        i.set_option('LISTEN_ADDRESS', ['127.0.0.1'])
        expect(i.instance_variable_get(:@listen_address)).to eq '127.0.0.1'
        expect(i.connection_string).to eql "listening on 127.0.0.1:8888 (R/W)"
      end

      it "passes READ_QUEUE_MAX_SIZE to each client connection" do
        i = TcpipServerInterface.new(nil, '8890', nil, '5', 'burst')
        i.set_option('READ_QUEUE_MAX_SIZE', ['1000'])
        i.connect
        socket = TCPSocket.new('127.0.0.1', 8890)
        begin
          read_interface_infos = i.instance_variable_get(:@read_interface_infos)
          50.times do
            break unless read_interface_infos.empty?

            sleep(0.01)
          end
          expect(read_interface_infos.length).to eql 1
          expect(read_interface_infos[0].interface.read_queue_max_size).to eql 1000
        ensure
          socket.close
          i.disconnect
        end
      end
    end

    describe "read_queue_bytes" do
      it "sums the bytes buffered by each client connection" do
        i = TcpipServerInterface.new('8888', '8889', '5', '5', 'burst')
        expect(i.read_queue_bytes).to eql 0
        read_interface_infos = i.instance_variable_get(:@read_interface_infos)
        [3, 4].each do |bytes|
          interface = double('interface', read_queue_bytes: bytes)
          read_interface_infos << TcpipServerInterface::InterfaceInfo.new(interface, nil, nil)
        end
        expect(i.read_queue_bytes).to eql 7
      end
    end

    describe "client disconnects" do
      it "detects any write client disconnecting while no data is written" do
        i = TcpipServerInterface.new('8892', nil, '5', nil, 'burst')
        i.connect
        sockets = []
        begin
          first = TCPSocket.new('127.0.0.1', 8892)
          sockets << first
          expect(wait_until?(2) { i.num_clients == 1 }).to be true
          second = TCPSocket.new('127.0.0.1', 8892)
          sockets << second
          expect(wait_until?(2) { i.num_clients == 2 }).to be true

          # Nothing is written so only the idle check can see the second
          # client go away, and it must check past the first client
          second.close
          expect(wait_until?(2) { i.num_clients == 1 }).to be true
          remaining = i.instance_variable_get(:@write_interface_infos)[0].interface.stream.write_socket
          expect(remaining.remote_address.ip_port).to eql first.local_address.ip_port
        ensure
          sockets.each { |socket| socket.close unless socket.closed? }
          i.disconnect
        end
      end

      it "removes every read client on disconnect" do
        i = TcpipServerInterface.new(nil, '8889', nil, '5', 'burst')
        read_interface_infos = i.instance_variable_get(:@read_interface_infos)
        interfaces = Array.new(2) { double('interface', stream_log_pair: nil) }
        interfaces.each do |interface|
          expect(interface).to receive(:disconnect).once
          read_interface_infos << TcpipServerInterface::InterfaceInfo.new(interface, nil, nil)
        end
        expect(i.num_clients).to eql 2

        i.disconnect

        expect(read_interface_infos).to be_empty
        expect(i.num_clients).to eql 0
      end
    end

    describe "slow clients" do
      # A client which connects but never reads so its socket buffers fill up
      def connect_stalled_client(port)
        socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
        socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF, 1024)
        socket.connect(Socket.pack_sockaddr_in(port, '127.0.0.1'))
        socket
      end

      def start_reader(socket, received)
        Thread.new do
          loop { received[0] += socket.readpartial(65536).length }
        rescue IOError, SystemCallError
          # Socket closed
        end
      end

      it "keeps writing to other clients and accepting while a client is not reading" do
        expect(Socket).not_to receive(:lookup_hostname_from_ip)
        i = TcpipServerInterface.new('8891', nil, '5', nil)
        i.connect
        sockets = []
        reader_thread = nil
        begin
          # Connect the stalled client first so it is written to first
          sockets << connect_stalled_client(8891)
          expect(wait_until?(2) { i.num_clients == 1 }).to be true
          reader = TCPSocket.new('127.0.0.1', 8891)
          sockets << reader
          expect(wait_until?(2) { i.num_clients == 2 }).to be true
          received = [0]
          reader_thread = start_reader(reader, received)

          chunk = "\x00" * 65536
          64.times { i.write_raw(chunk) }
          # Well under the 5s write timeout the stalled client would hold each write for
          expect(wait_until?(3) { received[0] == 64 * 65536 }).to be true

          # New connections are still accepted while the stalled client is held
          sockets << TCPSocket.new('127.0.0.1', 8891)
          expect(wait_until?(1) { i.num_clients == 3 }).to be true
        ensure
          sockets.each(&:close)
          i.disconnect
          reader_thread.join(1) if reader_thread
        end
      end

      it "drops a client which does not read within the write timeout" do
        i = TcpipServerInterface.new('8891', nil, '1', nil)
        i.connect
        sockets = []
        reader_thread = nil
        begin
          sockets << connect_stalled_client(8891)
          expect(wait_until?(2) { i.num_clients == 1 }).to be true
          reader = TCPSocket.new('127.0.0.1', 8891)
          sockets << reader
          expect(wait_until?(2) { i.num_clients == 2 }).to be true
          reader_thread = start_reader(reader, [0])

          chunk = "\x00" * 65536
          64.times { i.write_raw(chunk) }
          expect(wait_until?(5) { i.num_clients == 1 }).to be true
          # The reading client is the one which remains
          remaining = i.instance_variable_get(:@write_interface_infos)[0].interface.stream.write_socket
          expect(remaining.remote_address.ip_port).to eql reader.local_address.ip_port
        ensure
          sockets.each(&:close)
          i.disconnect
          reader_thread.join(1) if reader_thread
        end
      end

      # Blocks after each write like CmdResponseProtocol waiting for a response
      class SlowPostWriteProtocol < Protocol
        def post_write_interface(packet, data, extra = nil)
          sleep(0.4)
          super(packet, data, extra)
        end
      end

      it "does not drop a client whose protocol is slow but which reads its data" do
        i = TcpipServerInterface.new('8891', nil, '1', nil)
        i.add_protocol(SlowPostWriteProtocol, [], :WRITE)
        i.connect
        reader = nil
        reader_thread = nil
        begin
          reader = TCPSocket.new('127.0.0.1', 8891)
          expect(wait_until?(2) { i.num_clients == 1 }).to be true
          received = [0]
          reader_thread = start_reader(reader, received)

          # The protocol takes 2s to write all 5 packets, more than the 1s write
          # timeout, but the socket is never blocked so the client must not be dropped
          5.times do
            packet = Packet.new('TGT', 'PKT')
            packet.buffer = "\x01\x02\x03\x04"
            i.write(packet)
          end
          expect(wait_until?(5) { received[0] == 5 * 4 }).to be true
          expect(i.num_clients).to eql 1
        ensure
          reader.close if reader
          i.disconnect
          reader_thread.join(1) if reader_thread
        end
      end
    end

    describe "details" do
      it "returns detailed interface information" do
        i = TcpipServerInterface.new('8888', '8889', '5.0', '10.0', 'burst')
        i.set_option('LISTEN_ADDRESS', ['127.0.0.1'])

        details = i.details

        expect(details).to be_a(Hash)
        expect(details['write_port']).to eql(8888)
        expect(details['read_port']).to eql(8889)
        expect(details['write_timeout']).to eql(5.0)
        expect(details['read_timeout']).to eql(10.0)
        expect(details['listen_address']).to eql('127.0.0.1')

        # Check that base interface details are included
        expect(details['name']).to eql('TcpipServerInterface')
        expect(details).to have_key('read_allowed')
        expect(details).to have_key('write_allowed')
        expect(details).to have_key('options')
      end

      it "handles default listen address" do
        i = TcpipServerInterface.new('8888', '8889', '5.0', '10.0', 'burst')

        details = i.details

        expect(details['write_port']).to eql(8888)
        expect(details['read_port']).to eql(8889)
        expect(details['listen_address']).to eql('0.0.0.0')
      end

      it "handles nil values correctly" do
        i = TcpipServerInterface.new('8888', 'nil', 'nil', '10.0', 'burst')

        details = i.details

        expect(details['write_port']).to eql(8888)
        expect(details['read_port']).to be_nil
        expect(details['write_timeout']).to be_nil
        expect(details['read_timeout']).to eql(10.0)
      end
    end
  end
end
