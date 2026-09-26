# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require_relative 'spec_helper'

# A simulated device sends TOTAL_BYTES at SEND_RATE while the interface
# consumer can only process CONSUME_RATE (slower). If the interface only reads
# the socket when the consumer asks for the next packet, the backlog sits in
# the operating system socket buffers which overflow: UDP datagrams are
# dropped by the kernel and a TCP device can't write (so it overruns).
# With the read queue the socket is drained by a dedicated thread and the
# backlog is buffered in memory (up to READ_QUEUE_MAX_SIZE).
RSpec.describe 'Interface socket reads with a slow consumer' do
  def run_udp(read_queue_max_size)
    port = Addrinfo.udp('127.0.0.1', 0).bind { |s| s.local_address.ip_port }
    interface = OpenC3::UdpInterface.new('127.0.0.1', nil, port, nil, nil, 128, 10.0, nil, '127.0.0.1')
    interface.name = 'UDP_THROUGHPUT'
    interface.set_option('READ_QUEUE_MAX_SIZE', [read_queue_max_size.to_s]) if read_queue_max_size
    interface.connect

    stats = T.new_stats
    consumer = Thread.new { T.consume(interface, stats) }
    pid, reader = T.fork_device { T.udp_device(port) }
    device = T.wait_device(pid, reader)

    # The STOP_MARKER queues up behind whatever is still waiting so keep
    # sending it (in case the kernel drops it) until the consumer sees it
    stop_socket = UDPSocket.new
    deadline = T.monotonic + T.consume_timeout
    until consumer.join(0.1) or T.monotonic > deadline
      stop_socket.send(T::STOP_MARKER, 0, '127.0.0.1', port)
    end
    stop_socket.close
    interface.disconnect
    consumer.join(5)
    raise stats[:error] if stats[:error]

    [device, stats]
  end

  def run_tcp(read_queue_max_size)
    server = TCPServer.new('127.0.0.1', 0)
    port = server.local_address.ip_port
    pid, reader = T.fork_device { T.tcp_device(server) }
    server.close # Child owns it now

    interface = OpenC3::TcpipClientInterface.new('127.0.0.1', port, port, 10.0, nil)
    interface.name = 'TCP_THROUGHPUT'
    interface.set_option('READ_QUEUE_MAX_SIZE', [read_queue_max_size.to_s]) if read_queue_max_size
    interface.connect

    stats = T.new_stats
    # The device closing the socket disconnects the consumer
    consumer = Thread.new { T.consume(interface, stats) }
    device = T.wait_device(pid, reader)
    consumer.join(T.consume_timeout)
    interface.disconnect
    consumer.join(5)
    raise stats[:error] if stats[:error]

    [device, stats]
  end

  describe 'UDP' do
    it 'drops datagrams when reads are inline (READ_QUEUE_MAX_SIZE 0)' do
      device, stats = run_udp(0)
      lost = T.report('UDP inline', device, stats)
      # Sanity check that the scenario actually overflows the socket buffer
      expect(lost).to be > 0
    end

    it 'keeps up with the device with the default read queue' do
      device, stats = run_udp(nil)
      T.report('UDP read queue', device, stats)
      expect(T.lost_percent(device, stats)).to be <= T::MAX_UDP_LOSS_PERCENT
    end
  end

  describe 'TCP' do
    it 'overruns the device when reads are inline (READ_QUEUE_MAX_SIZE 0)' do
      device, stats = run_tcp(0)
      T.report('TCP inline', device, stats)
      # TCP doesn't lose data in transit but the device couldn't send it
      expect(device['dropped_bytes']).to be > 0
      expect(stats[:received_bytes]).to eql device['sent_bytes']
    end

    it 'never blocks the device with the default read queue' do
      device, stats = run_tcp(nil)
      T.report('TCP read queue', device, stats)
      expect(device['dropped_bytes']).to eql 0
      expect(stats[:received_bytes]).to eql device['sent_bytes']
    end
  end
end
