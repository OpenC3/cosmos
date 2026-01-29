# Copyright 2026 OpenC3, Inc.
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

# Maximum Command Rate Test (Ruby)
#
# Tests the theoretical maximum command rate by directly connecting to the
# throughput server and sending CCSDS commands as fast as possible.
# This bypasses COSMOS entirely to measure raw TCP throughput.
#
# Usage:
#   ruby max_cmd_rate_test.rb [host] [port] [duration_seconds]
#
# Example:
#   ruby max_cmd_rate_test.rb host.docker.internal 7778 10

require 'socket'

# Configuration
DEFAULT_HOST = 'host.docker.internal'
DEFAULT_PORT = 7778
DEFAULT_DURATION = 10

# CCSDS Command constants
CMD_GET_STATS = 202
APID = 1  # Use APID 1 for commands

# Build a CCSDS command packet
# Format:
#   word0 (2 bytes): version(3) | type(1)=1 | shf(1)=0 | apid(11)
#   word1 (2 bytes): seqflags(2)=3 | seqcnt(14)
#   length (2 bytes): total_length - 7
#   pktid (2 bytes): command ID
def build_ccsds_command(pktid, sequence_count = 0, payload = '')
  # word0: version=0, type=1 (command), shf=0, apid
  word0 = (0 << 13) | (1 << 12) | (0 << 11) | (APID & 0x07FF)

  # word1: seqflags=3, seqcnt
  word1 = (3 << 14) | (sequence_count & 0x3FFF)

  # Total packet length = 6 (primary header) + 2 (pktid) + payload
  total_length = 6 + 2 + payload.length
  ccsds_length = total_length - 7

  # Pack the header
  header = [word0, word1, ccsds_length, pktid].pack('n4')

  header + payload
end

def run_test(host, port, duration)
  $stdout.sync = true  # Ensure output is flushed immediately

  puts "=" * 60
  puts "Maximum Command Rate Test (Ruby)"
  puts "=" * 60
  puts "Host: #{host}:#{port}"
  puts "Duration: #{duration} seconds"
  puts ""

  # Pre-build the command packet (GET_STATS with no payload)
  cmd_packet = build_ccsds_command(CMD_GET_STATS)
  puts "Command packet size: #{cmd_packet.length} bytes"
  puts "Command packet (hex): #{cmd_packet.unpack1('H*')}"
  puts ""

  # Connect to server
  puts "Connecting to #{host}:#{port}..."
  socket = TCPSocket.new(host, port)
  socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
  socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, 4 * 1024 * 1024)  # 4MB send buffer
  socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF, 4 * 1024 * 1024)  # 4MB receive buffer
  puts "Connected!"
  puts ""

  # Discard any initial telemetry from the server
  puts "Draining initial telemetry..."
  socket.read_nonblock(65536) rescue nil
  puts "Ready to send."
  puts ""

  # Run the test
  puts "Sending commands for #{duration} seconds..."
  puts ""

  cmd_count = 0
  start_time = Time.now
  end_time = start_time + duration
  last_report_time = start_time
  last_report_count = 0

  # Use non-blocking I/O with select() to avoid TCP deadlock
  # Batch multiple commands per select() cycle for efficiency
  batch_size = 100
  batch_packet = cmd_packet * batch_size

  begin
    while Time.now < end_time
      # Use select with short timeout
      readable, writable, = IO.select([socket], [socket], nil, 0.0001)

      # Drain any pending responses to prevent receive buffer from filling
      if readable && readable.include?(socket)
        begin
          socket.read_nonblock(65536)
        rescue IO::WaitReadable, Errno::EAGAIN
          # No data available
        end
      end

      # Send batch of commands if socket is writable
      if writable && writable.include?(socket)
        begin
          written = socket.write_nonblock(batch_packet)
          cmd_count += written / cmd_packet.length
        rescue IO::WaitWritable, Errno::EAGAIN
          # Can't write right now, will retry
        end
      end

      # Periodic progress report (every second)
      now = Time.now
      if now - last_report_time >= 1.0
        interval_count = cmd_count - last_report_count
        interval_rate = interval_count / (now - last_report_time)
        elapsed = now - start_time
        puts "  #{elapsed.round(1)}s: #{cmd_count} commands sent (#{interval_rate.round(0)} cmd/s current)"
        last_report_time = now
        last_report_count = cmd_count
      end
    end
  rescue Errno::EPIPE, Errno::ECONNRESET => e
    puts "Connection error: #{e.message}"
  ensure
    socket.close rescue nil
  end

  # Calculate results
  actual_duration = Time.now - start_time
  overall_rate = cmd_count / actual_duration
  bytes_sent = cmd_count * cmd_packet.length
  throughput_mbps = (bytes_sent * 8) / (actual_duration * 1_000_000)

  # Print results
  puts ""
  puts "=" * 60
  puts "RESULTS"
  puts "=" * 60
  puts "Commands sent:     #{cmd_count}"
  puts "Actual duration:   #{actual_duration.round(3)} seconds"
  puts "Command rate:      #{overall_rate.round(0)} commands/second"
  puts "Bytes sent:        #{bytes_sent} (#{(bytes_sent / 1024.0 / 1024.0).round(2)} MB)"
  puts "Throughput:        #{throughput_mbps.round(2)} Mbps"
  puts "=" * 60
end

# Main
if __FILE__ == $0
  host = ARGV[0] || DEFAULT_HOST
  port = (ARGV[1] || DEFAULT_PORT).to_i
  duration = (ARGV[2] || DEFAULT_DURATION).to_i

  run_test(host, port, duration)
end
