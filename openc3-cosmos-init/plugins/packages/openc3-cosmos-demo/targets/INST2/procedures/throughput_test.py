# Throughput Test Script for <%= target_name %> (Python)
#
# This script tests command and telemetry throughput performance
# when connected to the external throughput server.
#
# Prerequisites:
# 1. Start the throughput server: python examples/throughput_server/throughput_server.py
# 2. Install the DEMO plugin with: use_throughput_server=true

import time

set_line_delay(0)
TARGET = "<%= target_name %>"


def test_command_throughput(num_commands, description):
    print("=" * 60)
    print(f"Test: {description}")
    print(f"Sending {num_commands} commands...")

    # Reset stats before test
    cmd(f"{TARGET} RESET_STATS")
    wait(0.5)

    start_time = time.time()

    for i in range(num_commands):
        cmd_no_hazardous_check(f"{TARGET} GET_STATS")

    elapsed = time.time() - start_time
    rate = num_commands / elapsed

    print(f"Completed: {num_commands} commands in {elapsed:.3f} seconds")
    print(f"Command rate: {rate:.1f} commands/second")
    print("")

    return rate


def test_telemetry_throughput(stream_rate, duration, description):
    print("=" * 60)
    print(f"Test: {description}")
    print(f"Streaming at {stream_rate} Hz for {duration} seconds...")

    # Reset stats on the server and request fresh telemetry
    cmd(f"{TARGET} RESET_STATS")
    cmd(f"{TARGET} GET_STATS")
    # Wait for fresh packet to arrive with reset values (count is 0 in the packet)
    wait_check(f"{TARGET} THROUGHPUT_STATUS TLM_SENT_COUNT == 0", 2)

    # Get initial counts - capture packet count FIRST to minimize race
    initial_cosmos_count = get_tlm_cnt(f"{TARGET} THROUGHPUT_STATUS")
    initial_server_count = tlm(f"{TARGET} THROUGHPUT_STATUS TLM_SENT_COUNT")
    initial_seq = tlm(f"{TARGET} THROUGHPUT_STATUS CCSDSSEQCNT")

    # Start streaming
    cmd(f"{TARGET} START_STREAM with RATE {stream_rate}")

    # Wait for specified duration
    wait(duration)

    # Stop streaming and wait for in-flight packets to arrive
    cmd(f"{TARGET} STOP_STREAM")
    wait(2.0)

    # Request a status packet to trigger COSMOS telemetry count sync to Redis
    # (counts are batched every 1 second and only sync when packets arrive)
    cmd(f"{TARGET} GET_STATS")
    wait(2.0)

    # Get final counts
    final_cosmos_count = get_tlm_cnt(f"{TARGET} THROUGHPUT_STATUS")
    final_server_count = tlm(f"{TARGET} THROUGHPUT_STATUS TLM_SENT_COUNT")
    final_seq = tlm(f"{TARGET} THROUGHPUT_STATUS CCSDSSEQCNT")

    # Calculate packets sent by server during streaming
    # Note: final_server_count is from the GET_STATS packet, which has the count BEFORE that packet was sent
    packets_sent = final_server_count - initial_server_count

    # Calculate packets received by COSMOS during streaming
    packets_received = final_cosmos_count - initial_cosmos_count

    # Calculate actual rate from test data (more accurate than server's TLM_SENT_RATE which is stale)
    actual_rate = packets_sent / duration

    # Calculate sequence span (handles 14-bit wrap-around)
    if final_seq >= initial_seq:
        seq_span = final_seq - initial_seq
    else:
        seq_span = (0x3FFF - initial_seq) + final_seq + 1
    # Subtract 1 from seq_span to exclude the GET_STATS packet after STOP_STREAM
    streaming_seq_span = seq_span - 1

    # Calculate loss based on what server actually sent vs what COSMOS received
    if packets_sent > 0:
        loss_percent = max(
            0, round((packets_sent - packets_received) / packets_sent * 100, 2)
        )
    else:
        loss_percent = 0

    # Check for sequence gaps (comparing streaming packets only)
    seq_gaps = streaming_seq_span - packets_received
    if seq_gaps < 0:
        seq_gaps = 0

    print(f"Server sent: {packets_sent} packets")
    print(f"COSMOS received: {packets_received} packets")
    print(f"Packet loss: {loss_percent}%")
    print(
        f"Sequence span: {initial_seq} -> {final_seq - 1} ({streaming_seq_span} streaming packets)"
    )
    if seq_gaps > 0:
        print(f"Sequence gaps detected: {seq_gaps} missing packets in sequence")
    print(f"Actual rate: {actual_rate:.1f} Hz (target: {stream_rate} Hz)")
    print("")

    return {
        "rate": actual_rate,
        "packets": packets_received,
        "sent": packets_sent,
        "loss_percent": loss_percent,
    }


def run_throughput_tests():
    print("")
    print("#" * 60)
    print(f"# {TARGET} Throughput Test Suite (Python)")
    print("#" * 60)
    print("")

    results = {}

    # Command throughput tests
    print("\n### COMMAND THROUGHPUT TESTS ###\n")

    results["cmd_burst_100"] = test_command_throughput(100, "Burst 100 commands")
    results["cmd_burst_500"] = test_command_throughput(500, "Burst 500 commands")
    results["cmd_burst_1000"] = test_command_throughput(1000, "Burst 1000 commands")

    # Wait for all command test responses to be fully processed by COSMOS
    # (command tests generate many THROUGHPUT_STATUS packets that may still be in flight)
    print("\nWaiting for command test packets to settle...")
    wait(3.0)

    # Telemetry throughput tests
    print("\n### TELEMETRY THROUGHPUT TESTS ###\n")

    results["tlm_10hz"] = test_telemetry_throughput(10, 5, "10 Hz for 5 seconds")
    results["tlm_100hz"] = test_telemetry_throughput(100, 5, "100 Hz for 5 seconds")
    results["tlm_1000hz"] = test_telemetry_throughput(1000, 5, "1000 Hz for 5 seconds")
    results["tlm_2000hz"] = test_telemetry_throughput(2000, 5, "2000 Hz for 5 seconds")
    results["tlm_3000hz"] = test_telemetry_throughput(3000, 5, "3000 Hz for 5 seconds")

    # Summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)

    print("\nCommand Throughput:")
    print(f"  100 cmd burst:  {results['cmd_burst_100']:.1f} cmd/s")
    print(f"  500 cmd burst:  {results['cmd_burst_500']:.1f} cmd/s")
    print(f"  1000 cmd burst: {results['cmd_burst_1000']:.1f} cmd/s")

    print("\nTelemetry Throughput:")
    print(
        f"  10 Hz target:    {results['tlm_10hz']['rate']:.1f} Hz ({results['tlm_10hz']['loss_percent']}% loss)"
    )
    print(
        f"  100 Hz target:   {results['tlm_100hz']['rate']:.1f} Hz ({results['tlm_100hz']['loss_percent']}% loss)"
    )
    print(
        f"  1000 Hz target:  {results['tlm_1000hz']['rate']:.1f} Hz ({results['tlm_1000hz']['loss_percent']}% loss)"
    )
    print(
        f"  2000 Hz target:  {results['tlm_2000hz']['rate']:.1f} Hz ({results['tlm_2000hz']['loss_percent']}% loss)"
    )
    print(
        f"  3000 Hz target:  {results['tlm_3000hz']['rate']:.1f} Hz ({results['tlm_3000hz']['loss_percent']}% loss)"
    )

    print("\n" + "#" * 60)
    print("# Test Complete")
    print("#" * 60)

    return results


# Run the tests
run_throughput_tests()
