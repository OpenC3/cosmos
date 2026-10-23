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

# Dump a region of INST memory with the MEMDUMP command, verify each chunk
# and then push the dump to the bucket with put_target_file.
#
# The dump recovers from a bad downlink:
#   * Chunks with no response are requested again
#   * Chunks with a bad CRC prompt the operator to retry or stop the dump
#   * If the link is down the script waits for it to come back
#
# Environment variables:
#   BAD_CRC=1 flips a bit in one chunk part way through the dump to show recovery from a bad CRC
require 'openc3/utilities/crc'

START_OFFSET = 0
TOTAL_SIZE = 10000 # Bytes to dump
CHUNK_SIZE = 1024 # Bytes per MEMDUMP command (max 4096)
MAX_ATTEMPTS = 3 # Times to request a chunk with no response before giving up
RESPONSE_TIMEOUT = 5 # Seconds to wait for each MEMDUMP response
LINK_TIMEOUT = 60 # Seconds to wait for a lost link to come back

crc = OpenC3::Crc32.new
bad_crc = ENV['BAD_CRC']
end_offset = START_OFFSET + TOTAL_SIZE
dump_data = ''.b # The verified dump is small enough to keep in memory
offset = START_OFFSET
bucket_path = "INST/memdumps/INST_memdump_#{Time.now.utc.strftime('%Y%m%d%H%M%S')}.bin"

bad_crc_offset = START_OFFSET + (TOTAL_SIZE / CHUNK_SIZE / 2) * CHUNK_SIZE
while offset < end_offset
  size = [CHUNK_SIZE, end_offset - offset].min
  # Request a bad CRC on the first request for the chunk in the middle of
  # the dump
  chunk_bad_crc = 'FALSE'
  if bad_crc and offset >= bad_crc_offset
    chunk_bad_crc = 'TRUE'
    bad_crc = nil
  end

  data = nil
  attempt = 0
  while data.nil? and attempt < MAX_ATTEMPTS
    attempt += 1
    # Record the received count so we know when the response arrives
    count = tlm("INST MEMDUMP RECEIVED_COUNT") || 0

    # Send the command, waiting for the link if it is down. This doesn't use up
    # an attempt. An ack timeout may mean the command did reach the target but
    # the duplicate response is harmless because it has the same OFFSET and SIZE.
    link_deadline = Time.now + LINK_TIMEOUT
    sent = false
    until sent
      begin
        # The command CRC over OFFSET, SIZE and BAD_CRC is calculated automatically
        cmd("INST MEMDUMP with OFFSET #{offset}, SIZE #{size}, BAD_CRC #{chunk_bad_crc}")
        sent = true
        # Only the first request has a bad CRC so the retry succeeds
        chunk_bad_crc = 'FALSE'
      rescue => e
        raise unless e.message =~ /not connected|waiting for cmd ack/i and Time.now < link_deadline
        puts "WARN: #{e.message}, retrying until the link returns"
        wait(2)
      end
    end

    # Wait for the response to this request. A stale response (e.g. a late
    # reply to an earlier request) is skipped and we keep waiting.
    dump = nil
    deadline = Time.now + RESPONSE_TIMEOUT
    while (remaining = deadline - Time.now) > 0
      # wait returns false on timeout rather than raising
      break unless wait("INST MEMDUMP RECEIVED_COUNT > #{count}", remaining)
      # Grab all the items at once so they all come from the same packet
      response = get_tlm_packet("INST MEMDUMP", type: :RAW).to_h { |name, value, _| [name, value] }
      count = response['RECEIVED_COUNT']
      if response['OFFSET'] == offset and response['SIZE'] == size
        dump = response
        break
      end
      puts "WARN: Ignoring stale response for OFFSET #{response['OFFSET']}, SIZE #{response['SIZE']} " \
           "while waiting for OFFSET #{offset}, SIZE #{size}"
    end
    unless dump
      puts "WARN: No response for OFFSET #{offset} (attempt #{attempt} of #{MAX_ATTEMPTS})"
      next
    end

    # Calculate the CRC in the script (the CRC_OK derived item does the same
    # check on the ground for display on the screen)
    calculated = crc.calc(dump['DATA'])
    if calculated == dump['CRC']
      puts "CRC passed at OFFSET #{offset}"
      data = dump['DATA']
    else
      mismatch = "Target CRC 0x#{dump['CRC'].to_s(16).upcase} vs calculated 0x#{calculated.to_s(16).upcase}"
      puts "WARN: CRC mismatch at OFFSET #{offset}: #{mismatch}"
      # Let the operator decide whether to request the chunk again
      answer = message_box("Bad CRC at OFFSET #{offset}. Retry this chunk?", 'Retry', 'Stop Dump', informative: mismatch)
      if answer == 'Stop Dump'
        raise "Dump stopped by operator at OFFSET #{offset}"
      end
      # An operator retry doesn't use up an attempt
      attempt -= 1
    end
  end
  raise "Unable to dump OFFSET #{offset} after #{MAX_ATTEMPTS} attempts" unless data
  dump_data << data.b
  offset += size
end
puts "Dumped #{dump_data.length} bytes (CRC32 0x#{crc.calc(dump_data).to_s(16).upcase})"

# Push the dump to the bucket
put_target_file(bucket_path, dump_data)

# Read it back to verify it made it to the bucket intact
file = get_target_file(bucket_path)
data = file.read
file.delete
check_expression("#{data.length} == #{TOTAL_SIZE}")
check_expression("#{crc.calc(data)} == #{crc.calc(Array.new(TOTAL_SIZE) { |i| (START_OFFSET + i) & 0xFF }.pack('C*'))}")
puts "Memory dump saved to #{bucket_path}"
