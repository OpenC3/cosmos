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

require 'json'
require 'socket'

# OPENC3_TEST_LIB points at the lib directory of a different openc3 checkout
# (e.g. a worktree of main) so the same tests can run against older code.
# See ../run_against.sh
OPENC3_TEST_LIB = ENV['OPENC3_TEST_LIB'] || File.expand_path('../../../../lib', __dir__)
$LOAD_PATH.unshift(OPENC3_TEST_LIB)

# Keep the Logger from trying to publish to Redis
ENV['OPENC3_NO_STORE'] ||= '1'

require 'openc3'
require 'openc3/interfaces/udp_interface'
require 'openc3/interfaces/tcpip_client_interface'

# The interfaces log connect / disconnect info which clutters the report
OpenC3::Logger.stdout = false

puts "Testing #{$LOADED_FEATURES.grep(%r{openc3/interfaces/udp_interface\.rb}).first}"

module SocketThroughput
  MB = 1024 * 1024
  # Total bytes the simulated device sends
  TOTAL_BYTES = (Float(ENV.fetch('OPENC3_SOCKET_TEST_MB', '30')) * MB).to_i
  # Rate the simulated device sends at
  SEND_RATE = Float(ENV.fetch('OPENC3_SOCKET_TEST_SEND_MBPS', '40')) * MB
  # Rate the interface consumer processes data at. This stands in for the
  # protocol, decom and Redis work the interface microservice does per packet.
  CONSUME_RATE = Float(ENV.fetch('OPENC3_SOCKET_TEST_CONSUME_MBPS', '20')) * MB
  # UDP loss allowed with the read queue. Garbage collection stops every thread
  # (the read thread included) and a pause of a few ms is enough to overflow
  # the default Linux socket receive buffer (~200KB, ~5ms at 40MB/s), so a
  # small loss remains on Linux. Inline reads lose roughly half.
  MAX_UDP_LOSS_PERCENT = Float(ENV.fetch('OPENC3_SOCKET_TEST_MAX_UDP_LOSS_PERCENT', '5'))
  # Datagram / write size. Stays below the macOS default net.inet.udp.maxdgram.
  CHUNK_SIZE = 8192
  # Device transmit buffer. Fixed so the result doesn't depend on the OS TCP
  # buffer autotuning (which starts small). Still far smaller than the backlog.
  DEVICE_BUFFER_SIZE = 4 * MB
  # Sent after the device finishes to tell the UDP consumer to stop
  STOP_MARKER = 'STOP_SOCKET_THROUGHPUT_TEST'.freeze

  def self.monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # Sleep as needed to hold bytes / elapsed to the given rate
  def self.pace(start, bytes, rate)
    ahead = (bytes / rate) - (monotonic() - start)
    sleep(ahead) if ahead > 0.0005
  end

  def self.chunk(seq)
    [seq].pack('N') + ("\xA5" * (CHUNK_SIZE - 4))
  end

  # Simulated device which sends datagrams at SEND_RATE. Runs in a forked
  # process so it doesn't compete with the interface for the GVL.
  def self.udp_device(port)
    socket = UDPSocket.new
    socket.connect('127.0.0.1', port)
    sent = 0
    seq = 0
    start = monotonic()
    while sent < TOTAL_BYTES
      data = chunk(seq)
      begin
        socket.send(data, 0)
      rescue Errno::ENOBUFS
        # Local send queue full (macOS), retry the same datagram
        sleep 0.0001
        next
      end
      sent += data.length
      seq += 1
      pace(start, sent, SEND_RATE)
    end
    socket.close
    { 'sent_bytes' => sent, 'dropped_bytes' => 0, 'elapsed' => monotonic() - start }
  end

  # Simulated device which writes to a TCP client at SEND_RATE. Like real
  # hardware it can't block waiting for a slow reader, so whatever can't be
  # written without blocking is dropped (a device buffer overrun).
  def self.tcp_device(server)
    socket = server.accept
    socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, DEVICE_BUFFER_SIZE)
    sent = 0
    dropped = 0
    produced = 0
    seq = 0
    start = monotonic()
    while produced < TOTAL_BYTES
      data = chunk(seq)
      seq += 1
      produced += data.length
      written = socket.write_nonblock(data, exception: false)
      written = 0 if written == :wait_writable
      sent += written
      dropped += data.length - written
      pace(start, produced, SEND_RATE)
    end
    socket.close
    { 'sent_bytes' => sent, 'dropped_bytes' => dropped, 'elapsed' => monotonic() - start }
  end

  # Fork a process running the block and return [pid, reader] where reader
  # yields the JSON result the block returns
  def self.fork_device
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      result = yield
      writer.write(JSON.generate(result))
      writer.close
      exit!(0) # Skip RSpec at_exit hooks in the child
    end
    writer.close
    [pid, reader]
  end

  def self.wait_device(pid, reader)
    Process.wait(pid)
    result = JSON.parse(reader.read)
    reader.close
    result
  end

  # Read packets from the interface until it disconnects or the STOP_MARKER
  # arrives, processing no faster than CONSUME_RATE
  def self.consume(interface, stats)
    start = nil
    loop do
      packet = interface.read
      break unless packet

      data = packet.buffer(false)
      break if data.start_with?(STOP_MARKER)

      start ||= monotonic()
      stats[:received_bytes] += data.length
      stats[:packets] += 1
      if interface.respond_to?(:read_queue_bytes)
        queued = interface.read_queue_bytes
        stats[:peak_queue_bytes] = queued if queued > stats[:peak_queue_bytes]
      end
      pace(start, stats[:received_bytes], CONSUME_RATE)
    end
  rescue => e
    stats[:error] = e
  end

  def self.new_stats
    { received_bytes: 0, packets: 0, peak_queue_bytes: 0, error: nil }
  end

  # Worst case time to drain everything plus slack
  def self.consume_timeout
    ((TOTAL_BYTES / CONSUME_RATE) * 2) + 10
  end

  def self.lost_percent(device, stats)
    total = device['sent_bytes'] + device['dropped_bytes']
    100.0 * (total - stats[:received_bytes]) / total
  end

  def self.report(label, device, stats)
    lost = device['sent_bytes'] + device['dropped_bytes'] - stats[:received_bytes]
    total = device['sent_bytes'] + device['dropped_bytes']
    puts format(
      "\n    %s: produced %.1fMB in %.2fs, received %.1fMB, lost %.1fMB (%.1f%%), peak queue %.1fMB",
      label, total.to_f / MB, device['elapsed'], stats[:received_bytes].to_f / MB,
      lost.to_f / MB, 100.0 * lost / total, stats[:peak_queue_bytes].to_f / MB
    )
    lost
  end
end

# Short alias for the specs
T = SocketThroughput

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.disable_monkey_patching!
  config.default_formatter = 'doc'
end
