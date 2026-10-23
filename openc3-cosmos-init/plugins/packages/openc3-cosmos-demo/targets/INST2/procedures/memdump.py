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

# Dump a region of INST2 memory with the MEMDUMP command, verify each chunk
# and then push the dump to the bucket with put_target_file.
#
# The dump recovers from a bad downlink:
#   * Chunks with no response are requested again
#   * Chunks with a bad CRC prompt the operator to retry or stop the dump
#   * If the link is down the script waits for it to come back
#   * Progress is checkpointed to the bucket so an interrupted dump resumes
#     where it left off the next time the script runs
#
# Environment variables:
#   BAD_CRC=1 flips a bit in one chunk part way through the dump to show recovery from a bad CRC
#   RESTART=1 discards any saved progress and starts over
import os
import re
import time
from datetime import UTC, datetime

from openc3.utilities.crc import Crc32


START_OFFSET = 0
TOTAL_SIZE = 10000  # Bytes to dump
CHUNK_SIZE = 1024  # Bytes per MEMDUMP command (max 4096)
MAX_ATTEMPTS = 3  # Times to request a chunk with no response before giving up
RESPONSE_TIMEOUT = 5  # Seconds to wait for each MEMDUMP response
LINK_TIMEOUT = 60  # Seconds to wait for a lost link to come back
CHECKPOINT_CHUNKS = 2  # Save progress to the bucket every N chunks
PROGRESS_KEY = "INST2_MEMDUMP_PROGRESS"  # Stash key holding the checkpoint

crc = Crc32()
bad_crc = os.environ.get("BAD_CRC")
restart = os.environ.get("RESTART")
end_offset = START_OFFSET + TOTAL_SIZE
dump_data = bytearray()  # The verified dump is small enough to keep in memory
offset = START_OFFSET
filename = None
checkpointed = False  # Whether a partial file exists in the bucket
progress = stash_get(PROGRESS_KEY)
if progress:
    data = None
    # Only resume a dump of the same region and only if the checkpoint is intact
    if not restart and progress["start_offset"] == START_OFFSET and progress["total_size"] == TOTAL_SIZE:
        partial = get_target_file(progress["partial_path"])
        if partial:
            data = partial.read()
            partial.close()
    if data is not None and len(data) == progress["next_offset"] - START_OFFSET and crc.calc(data) == progress["crc"]:
        dump_data += data
        offset = progress["next_offset"]
        filename = progress["filename"]
        checkpointed = True
        print(f"Resuming {filename} at OFFSET {offset} ({len(data)} bytes already verified)")
    else:
        if restart:
            print("Discarding saved progress because RESTART is set")
        else:
            print("WARN: Discarding saved progress which doesn't match this dump")
        stash_delete(PROGRESS_KEY)
        # Remove the old partial file so it doesn't linger in the bucket
        if progress.get("partial_path"):
            try:
                delete_target_file(progress["partial_path"])
            except Exception as error:
                print(f"WARN: Unable to delete old partial file: {error}")
if filename is None:
    filename = f"INST2_memdump_{datetime.now(UTC).strftime('%Y%m%d%H%M%S')}.bin"
bucket_path = f"INST2/memdumps/{filename}"
partial_path = f"{bucket_path}.partial"

bad_crc_offset = START_OFFSET + (TOTAL_SIZE // CHUNK_SIZE // 2) * CHUNK_SIZE
chunks = 0
while offset < end_offset:
    size = min(CHUNK_SIZE, end_offset - offset)
    # Request a bad CRC on the first request for the chunk in the middle of
    # the dump (or the first chunk if resuming past the middle)
    chunk_bad_crc = "FALSE"
    if bad_crc and offset >= bad_crc_offset:
        chunk_bad_crc = "TRUE"
        bad_crc = None

    data = None
    attempt = 0
    while data is None and attempt < MAX_ATTEMPTS:
        attempt += 1
        # Record the received count so we know when the response arrives
        count = tlm("INST2 MEMDUMP RECEIVED_COUNT") or 0

        # Send the command, waiting for the link if it is down. This doesn't use up
        # an attempt. An ack timeout may mean the command did reach the target but
        # the duplicate response is harmless because it has the same OFFSET and SIZE.
        link_deadline = time.time() + LINK_TIMEOUT
        sent = False
        while not sent:
            try:
                # The command CRC over OFFSET, SIZE and BAD_CRC is calculated automatically
                cmd(f"INST2 MEMDUMP with OFFSET {offset}, SIZE {size}, BAD_CRC {chunk_bad_crc}")
                sent = True
                # Only the first request has a bad CRC so the retry succeeds
                chunk_bad_crc = "FALSE"
            except Exception as error:
                if not re.search("not connected|waiting for cmd ack", str(error), re.IGNORECASE):
                    raise
                if time.time() > link_deadline:
                    raise
                print(f"WARN: {error}, retrying until the link returns")
                wait(2)

        # Wait for the response to this request. A stale response (e.g. a late
        # reply to an earlier request) is skipped and we keep waiting.
        dump = None
        deadline = time.time() + RESPONSE_TIMEOUT
        while (remaining := deadline - time.time()) > 0:
            # wait returns False on timeout rather than raising
            if not wait(f"INST2 MEMDUMP RECEIVED_COUNT > {count}", remaining):
                break
            # Grab all the items at once so they all come from the same packet
            response = {name: value for name, value, _ in get_tlm_packet("INST2 MEMDUMP", type="RAW")}
            count = response["RECEIVED_COUNT"]
            if response["OFFSET"] == offset and response["SIZE"] == size:
                dump = response
                break
            print(
                f"WARN: Ignoring stale response for OFFSET {response['OFFSET']}, SIZE {response['SIZE']} "
                f"while waiting for OFFSET {offset}, SIZE {size}"
            )
        if dump is None:
            print(f"WARN: No response for OFFSET {offset} (attempt {attempt} of {MAX_ATTEMPTS})")
            continue

        # CRC_OK is a derived item comparing the target CRC to the ground CRC
        # but we also check it here to show how to calculate a CRC in a script
        chunk = bytes(dump["DATA"])
        calculated = crc.calc(chunk)
        if calculated == dump["CRC"] and dump["CRC_OK"] == 1:
            print(f"CRC passed at OFFSET {offset}")
            data = chunk
        else:
            mismatch = f"Target CRC 0x{dump['CRC']:08X} vs calculated 0x{calculated:08X}"
            print(f"WARN: CRC mismatch at OFFSET {offset}: {mismatch}")
            # Let the operator decide whether to request the chunk again
            answer = message_box(
                f"Bad CRC at OFFSET {offset}. Retry this chunk?", "Retry", "Stop Dump", informative=mismatch
            )
            if answer == "Stop Dump":
                raise RuntimeError(
                    f"Dump stopped by operator at OFFSET {offset}. Run again to resume from the last checkpoint."
                )
            # An operator retry doesn't use up an attempt
            attempt -= 1
    if data is None:
        raise RuntimeError(f"Unable to dump OFFSET {offset} after {MAX_ATTEMPTS} attempts")
    dump_data += data
    offset += size

    # Checkpoint the verified data so an interrupted dump can resume here
    chunks += 1
    if chunks % CHECKPOINT_CHUNKS == 0 and offset < end_offset:
        put_target_file(partial_path, bytes(dump_data))
        stash_set(
            PROGRESS_KEY,
            {
                "filename": filename,
                "partial_path": partial_path,
                "start_offset": START_OFFSET,
                "total_size": TOTAL_SIZE,
                "next_offset": offset,
                "crc": crc.calc(dump_data),
            },
        )
        checkpointed = True
        print(f"Checkpoint saved at OFFSET {offset}")
print(f"Dumped {len(dump_data)} bytes (CRC32 0x{crc.calc(dump_data):08X})")

# Push the dump to the bucket and clean up the checkpoint
put_target_file(bucket_path, bytes(dump_data))
stash_delete(PROGRESS_KEY)
if checkpointed:
    delete_target_file(partial_path)

# Read it back to verify it made it to the bucket intact
file = get_target_file(bucket_path)
data = file.read()
file.close()
expected = bytes((START_OFFSET + i) & 0xFF for i in range(TOTAL_SIZE))
check_expression(f"{len(data)} == {TOTAL_SIZE}")
check_expression(f"{crc.calc(data)} == {crc.calc(expected)}")
print(f"Memory dump saved to {bucket_path}")
