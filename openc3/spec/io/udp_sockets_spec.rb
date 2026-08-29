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
require 'openc3/io/udp_sockets'

module OpenC3
  describe UdpWriteSocket do
    describe "initialize" do
      it "creates a socket" do
        udp = UdpWriteSocket.new('127.0.0.1', 8888)
        expect(udp.peeraddr[2]).to eql '127.0.0.1'
        expect(udp.peeraddr[1]).to eql 8888
        udp.close
        if RUBY_ENGINE == 'ruby' # UDP multicast does not work in Jruby
          udp = UdpWriteSocket.new('224.0.1.1', 8888, 7888, '127.0.0.1', 3)
          expect(udp.local_address.ip_port).to eql 7888
          # Reading this back doesn't appear to work in JRUBY, not sure if it is actually taking
          expect(udp.getsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_TTL).int).to eql 3
          expect(IPAddr.new_ntoh(udp.getsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_IF).data).to_s).to eql "127.0.0.1"
          udp.close
        end
      end
    end

    describe "write" do
      it "writes data" do
        udp_read  = UdpReadSocket.new(8888)
        udp_write = UdpWriteSocket.new('127.0.0.1', 8888)
        udp_write.write("\x01\x02", 2.0)
        expect(udp_read.read).to eql "\x01\x02"
        udp_read.close
        udp_write.close
      end

      it "handles timeouts" do
        allow_any_instance_of(UDPSocket).to receive(:write_nonblock) { raise Errno::EWOULDBLOCK }
        expect(IO).to receive(:fast_select).at_least(:once).and_return([], nil)
        udp_write = UdpWriteSocket.new('127.0.0.1', 8888)
        expect { udp_write.write("\x01\x02", 2.0) }.to raise_error(Timeout::Error)
        udp_write.close
      end

      it "raises on a non retryable send error" do
        udp = UdpReadWriteSocket.new(0, '0.0.0.0', 8888, '127.0.0.1', nil, 1, false, true, false)
        begin
          # Non EAGAIN errors are not retryable and must not spin the write loop
          expect_any_instance_of(UDPSocket).to receive(:send).once.and_raise(Errno::ENETUNREACH)
          expect { udp.write("\x01\x02", 2.0) }.to raise_error(Errno::ENETUNREACH)
        ensure
          udp.close
        end
      end

      it "writes to an unconnected socket using the address resolved at creation" do
        udp_read = UdpReadSocket.new(8888)
        # connect_socket false means every write must explicitly address the datagram
        udp_write = UdpReadWriteSocket.new(0, '0.0.0.0', 8888, 'localhost', nil, 1, false, true, false)
        begin
          expect(udp_write.instance_variable_get(:@external_sockaddr)).to \
            eql Socket.sockaddr_in(8888, '127.0.0.1')
          # The destination is resolved once at creation, not on every write
          expect(Socket).to_not receive(:getaddrinfo)
          udp_write.write("\x01\x02", 2.0)
          expect(udp_read.read).to eql "\x01\x02"
        ensure
          udp_read.close
          udp_write.close
        end
      end
    end

    describe "multicast" do
      it "determines if a host is multicast" do
        expect(UdpWriteSocket.multicast?(nil, 80)).to be false
        expect(UdpWriteSocket.multicast?('224.0.1.1', nil)).to be true
        expect(UdpWriteSocket.multicast?('127.0.0.1', 80)).to be false
        expect(UdpWriteSocket.multicast?('224.0.1.1', 80)).to be true
      end

      it "returns false for an unresolvable host" do
        expect(UdpWriteSocket.multicast?('this-host-does-not-exist.invalid')).to be false
      end
    end
  end

  describe UdpReadSocket do
    describe "initialize" do
      it "creates a socket" do
        udp = UdpReadSocket.new(8888)
        expect(udp.local_address.ip_address).to eql '0.0.0.0'
        expect(udp.local_address.ip_port).to eql 8888
        udp.close
        if RUBY_ENGINE == 'ruby' # UDP multicast does not work in Jruby
          udp = UdpReadSocket.new(8888, '224.0.1.1')
          expect(IPAddr.new_ntoh(udp.getsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_IF).data).to_s).to eql "0.0.0.0"
          udp.close
        end
      end

      it "binds port zero to an ephemeral port" do
        udp = UdpReadSocket.new(0)
        begin
          expect(udp.local_address.ip_port).to be > 0
        ensure
          udp.close
        end
      end

      it "joins the multicast group" do
        skip "UDP multicast does not work in JRuby" unless RUBY_ENGINE == 'ruby'

        calls = []
        allow_any_instance_of(UDPSocket).to receive(:setsockopt).and_wrap_original do |method, *args|
          calls << args
          method.call(*args)
        end
        udp = UdpReadSocket.new(8888, '224.0.1.1')
        begin
          membership = IPAddr.new('224.0.1.1').hton + IPAddr.new('0.0.0.0').hton
          expect(calls).to include([Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP, membership])
        ensure
          udp.close
        end
      end
    end

    describe "read" do
      it "reads data" do
        udp_read  = UdpReadSocket.new(8888)
        udp_write = UdpWriteSocket.new('127.0.0.1', 8888)
        udp_write.write("\x01\x02", 2.0)
        expect(udp_read.read).to eql "\x01\x02"
        udp_read.close
        udp_write.close
      end

      it "handles timeouts" do
        allow_any_instance_of(UDPSocket).to receive(:recvfrom_nonblock) { raise Errno::EWOULDBLOCK }
        expect(IO).to receive(:fast_select).at_least(:once).and_return([], nil)
        udp_read = UdpReadSocket.new(8889)
        expect { udp_read.read(2.0) }.to raise_error(Timeout::Error)
        udp_read.close
      end
    end
  end

  describe UdpReadWriteSocket do
    describe "initialize" do
      it "creates a socket" do
        udp = UdpReadWriteSocket.new(8888)
        expect(udp.local_address.ip_address).to eql '0.0.0.0'
        expect(udp.local_address.ip_port).to eql 8888
        udp.close
        if RUBY_ENGINE == 'ruby' # UDP multicast does not work in Jruby
          udp = UdpReadWriteSocket.new(8888, '0.0.0.0', 1234, '224.0.1.1')
          expect(IPAddr.new_ntoh(udp.getsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_IF).data).to_s).to eql "0.0.0.0"
          udp.close
        end
      end
    end

    describe "read" do
      it "reads data" do
        udp_read  = UdpReadWriteSocket.new(8888)
        udp_write = UdpWriteSocket.new('127.0.0.1', 8888)
        udp_write.write("\x01\x02", 2.0)
        expect(udp_read.read).to eql "\x01\x02"
        udp_read.close
        udp_write.close
      end
    end

    describe "write" do
      it "writes data" do
        udp_read  = UdpReadSocket.new(8888)
        udp_write = UdpReadWriteSocket.new(0, "0.0.0.0", 8888, '127.0.0.1')
        udp_write.write("\x01\x02", 2.0)
        expect(udp_read.read).to eql "\x01\x02"
        udp_read.close
        udp_write.close
      end
    end
  end
end
