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
#   * Chunks with a bad CRC or no response are requested again
#   * If the link is down the script waits for it to come back
#   * Progress is checkpointed to the bucket so an interrupted dump resumes
#     where it left off the next time the script runs
#
# Environment variables:
#   FAULT=BITFLIP or FAULT=DROP injects that fault part way through the dump
#   RESTART=1 discards any saved progress and starts over
require 'openc3/utilities/crc'

START_OFFSET = 0
TOTAL_SIZE = 10000 # Bytes to dump
CHUNK_SIZE = 1024 # Bytes per MEMDUMP command (max 4096)
MAX_ATTEMPTS = 3 # Times to request a chunk before giving up (bad CRC or no response)
RESPONSE_TIMEOUT = 5 # Seconds to wait for each MEMDUMP response
LINK_TIMEOUT = 60 # Seconds to wait for a lost link to come back
CHECKPOINT_CHUNKS = 2 # Save progress to the bucket every N chunks
PROGRESS_KEY = 'INST_MEMDUMP_PROGRESS' # Stash key holding the checkpoint

crc = OpenC3::Crc32.new
fault = ENV['FAULT']
end_offset = START_OFFSET + TOTAL_SIZE
dump_data = ''.b # The verified dump is small enough to keep in memory
offset = START_OFFSET
filename = nil
checkpointed = false # Whether a partial file exists in the bucket
progress = stash_get(PROGRESS_KEY)
if progress
  data = nil
  # Only resume a dump of the same region and only if the checkpoint is intact
  if !ENV['RESTART'] and progress['start_offset'] == START_OFFSET and progress['total_size'] == TOTAL_SIZE
    partial = get_target_file(progress['partial_path'])
    if partial
      data = partial.read
      partial.delete
    end
  end
  if data and data.length == progress['next_offset'] - START_OFFSET and crc.calc(data) == progress['crc']
    dump_data << data.b
    offset = progress['next_offset']
    filename = progress['filename']
    checkpointed = true
    puts "Resuming #{filename} at OFFSET #{offset} (#{data.length} bytes already verified)"
  else
    if ENV['RESTART']
      puts "Discarding saved progress because RESTART is set"
    else
      puts "WARN: Discarding saved progress which doesn't match this dump"
    end
    stash_delete(PROGRESS_KEY)
    # Remove the old partial file so it doesn't linger in the bucket
    begin
      delete_target_file(progress['partial_path']) if progress['partial_path']
    rescue => e
      puts "WARN: Unable to delete old partial file: #{e.message}"
    end
  end
end
filename ||= "INST_memdump_#{Time.now.utc.strftime('%Y%m%d%H%M%S')}.bin"
bucket_path = "INST/memdumps/#{filename}"
partial_path = "#{bucket_path}.partial"

fault_offset = START_OFFSET + (TOTAL_SIZE / CHUNK_SIZE / 2) * CHUNK_SIZE
chunks = 0
while offset < end_offset
  size = [CHUNK_SIZE, end_offset - offset].min
  # Inject the requested fault on the chunk in the middle of the dump
  # (or the first chunk if resuming past the middle)
  if fault and offset >= fault_offset
    cmd("INST MEMDUMP_FAULT with TYPE #{fault}")
    fault = nil
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
        # The command CRC over OFFSET and SIZE is calculated automatically
        cmd("INST MEMDUMP with OFFSET #{offset}, SIZE #{size}")
        sent = true
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

    # CRC_OK is a derived item comparing the target CRC to the ground CRC
    # but we also check it here to show how to calculate a CRC in a script
    calculated = crc.calc(dump['DATA'])
    if calculated == dump['CRC'] and dump['CRC_OK'] == 1
      data = dump['DATA']
    else
      puts "WARN: CRC mismatch at OFFSET #{offset}: target 0x#{dump['CRC'].to_s(16).upcase} vs " \
           "calculated 0x#{calculated.to_s(16).upcase} (attempt #{attempt} of #{MAX_ATTEMPTS})"
    end
  end
  raise "Unable to dump OFFSET #{offset} after #{MAX_ATTEMPTS} attempts" unless data
  dump_data << data.b
  offset += size

  # Checkpoint the verified data so an interrupted dump can resume here
  chunks += 1
  if chunks % CHECKPOINT_CHUNKS == 0 and offset < end_offset
    put_target_file(partial_path, dump_data)
    stash_set(PROGRESS_KEY, { 'filename' => filename, 'partial_path' => partial_path, 'start_offset' => START_OFFSET,
                              'total_size' => TOTAL_SIZE, 'next_offset' => offset, 'crc' => crc.calc(dump_data) })
    checkpointed = true
    puts "Checkpoint saved at OFFSET #{offset}"
  end
end
puts "Dumped #{dump_data.length} bytes (CRC32 0x#{crc.calc(dump_data).to_s(16).upcase})"

# Push the dump to the bucket and clean up the checkpoint
put_target_file(bucket_path, dump_data)
stash_delete(PROGRESS_KEY)
delete_target_file(partial_path) if checkpointed

# Read it back to verify it made it to the bucket intact
file = get_target_file(bucket_path)
data = file.read
file.delete
check_expression("#{data.length} == #{TOTAL_SIZE}")
check_expression("#{crc.calc(data)} == #{crc.calc(Array.new(TOTAL_SIZE) { |i| (START_OFFSET + i) & 0xFF }.pack('C*'))}")
puts "Memory dump saved to #{bucket_path}"
