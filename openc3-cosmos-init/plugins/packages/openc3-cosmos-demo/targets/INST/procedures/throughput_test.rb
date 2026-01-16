# Throughput Test Script for <%= target_name %> (Ruby)
#
# This script tests command and telemetry throughput performance
# when connected to the external throughput server.
#
# Prerequisites:
# 1. Start the throughput server: python examples/throughput_server/throughput_server.py
# 2. Install the DEMO plugin with: use_throughput_server=true

set_line_delay(0)
TARGET = "<%= target_name %>"

def test_command_throughput(num_commands, description)
  puts "=" * 60
  puts "Test: #{description}"
  puts "Sending #{num_commands} commands..."

  # Reset stats before test
  cmd("#{TARGET} RESET_STATS")
  wait(0.5)

  start_time = Time.now

  num_commands.times do |i|
    cmd_no_hazardous_check("#{TARGET} GET_STATS")
  end

  elapsed = Time.now - start_time
  rate = num_commands / elapsed

  puts "Completed: #{num_commands} commands in #{elapsed.round(3)} seconds"
  puts "Command rate: #{rate.round(1)} commands/second"
  puts ""

  rate
end

def test_telemetry_throughput(stream_rate, duration, description)
  puts "=" * 60
  puts "Test: #{description}"
  puts "Streaming at #{stream_rate} Hz for #{duration} seconds..."

  # Reset stats on the server and request fresh telemetry
  cmd("#{TARGET} RESET_STATS")
  cmd("#{TARGET} GET_STATS")
  # Wait for fresh packet to arrive with reset values (count is 0 in the packet)
  wait_check("#{TARGET} THROUGHPUT_STATUS TLM_SENT_COUNT == 0", 2)

  # Get initial counts - capture packet count FIRST to minimize race
  initial_cosmos_count = get_tlm_cnt("#{TARGET} THROUGHPUT_STATUS")
  initial_server_count = tlm("#{TARGET} THROUGHPUT_STATUS TLM_SENT_COUNT")
  initial_seq = tlm("#{TARGET} THROUGHPUT_STATUS CCSDSSEQCNT")

  # Start streaming
  cmd("#{TARGET} START_STREAM with RATE #{stream_rate}")

  # Wait for specified duration
  wait(duration)

  # Stop streaming and wait for in-flight packets to arrive
  cmd("#{TARGET} STOP_STREAM")
  wait(2.0)

  # Request a status packet to trigger COSMOS telemetry count sync to Redis
  # (counts are batched every 1 second and only sync when packets arrive)
  cmd("#{TARGET} GET_STATS")
  wait(2.0)

  # Get final counts
  final_cosmos_count = get_tlm_cnt("#{TARGET} THROUGHPUT_STATUS")
  final_server_count = tlm("#{TARGET} THROUGHPUT_STATUS TLM_SENT_COUNT")
  final_seq = tlm("#{TARGET} THROUGHPUT_STATUS CCSDSSEQCNT")

  # Calculate packets sent by server during streaming
  # Note: final_server_count is from the GET_STATS packet, which has the count BEFORE that packet was sent
  packets_sent = final_server_count - initial_server_count

  # Calculate packets received by COSMOS during streaming
  packets_received = final_cosmos_count - initial_cosmos_count

  # Calculate actual rate from test data (more accurate than server's TLM_SENT_RATE which is stale)
  actual_rate = packets_sent.to_f / duration

  # Calculate sequence span (handles 14-bit wrap-around)
  if final_seq >= initial_seq
    seq_span = final_seq - initial_seq
  else
    seq_span = (0x3FFF - initial_seq) + final_seq + 1
  end
  # Subtract 1 from seq_span to exclude the GET_STATS packet after STOP_STREAM
  streaming_seq_span = seq_span - 1

  # Calculate loss based on what server actually sent vs what COSMOS received
  if packets_sent > 0
    loss_percent = [(packets_sent - packets_received).to_f / packets_sent * 100, 0].max.round(2)
  else
    loss_percent = 0
  end

  # Check for sequence gaps (comparing streaming packets only)
  seq_gaps = streaming_seq_span - packets_received
  seq_gaps = 0 if seq_gaps < 0

  puts "Server sent: #{packets_sent} packets"
  puts "COSMOS received: #{packets_received} packets"
  puts "Packet loss: #{loss_percent}%"
  puts "Sequence span: #{initial_seq} -> #{final_seq - 1} (#{streaming_seq_span} streaming packets)"
  if seq_gaps > 0
    puts "Sequence gaps detected: #{seq_gaps} missing packets in sequence"
  end
  puts "Actual rate: #{actual_rate.round(1)} Hz (target: #{stream_rate} Hz)"
  puts ""

  {
    rate: actual_rate,
    packets: packets_received,
    sent: packets_sent,
    loss_percent: loss_percent
  }
end

def run_throughput_tests
  puts ""
  puts "#" * 60
  puts "# #{TARGET} Throughput Test Suite"
  puts "#" * 60
  puts ""

  results = {}

  # Command throughput tests
  puts "\n### COMMAND THROUGHPUT TESTS ###\n"

  results[:cmd_burst_100] = test_command_throughput(100, "Burst 100 commands")
  results[:cmd_burst_500] = test_command_throughput(500, "Burst 500 commands")
  results[:cmd_burst_1000] = test_command_throughput(1000, "Burst 1000 commands")

  # Wait for all command test responses to be fully processed by COSMOS
  # (command tests generate many THROUGHPUT_STATUS packets that may still be in flight)
  puts "\nWaiting for command test packets to settle..."
  wait(3.0)

  # Telemetry throughput tests
  puts "\n### TELEMETRY THROUGHPUT TESTS ###\n"

  results[:tlm_10hz] = test_telemetry_throughput(10, 5, "10 Hz for 5 seconds")
  results[:tlm_100hz] = test_telemetry_throughput(100, 5, "100 Hz for 5 seconds")
  results[:tlm_1000hz] = test_telemetry_throughput(1000, 5, "1000 Hz for 5 seconds")
  results[:tlm_2000hz] = test_telemetry_throughput(2000, 5, "2000 Hz for 5 seconds")
  results[:tlm_3000hz] = test_telemetry_throughput(3000, 5, "3000 Hz for 5 seconds")

  # Summary
  puts "\n" + "=" * 60
  puts "SUMMARY"
  puts "=" * 60

  puts "\nCommand Throughput:"
  puts "  100 cmd burst:  #{results[:cmd_burst_100].round(1)} cmd/s"
  puts "  500 cmd burst:  #{results[:cmd_burst_500].round(1)} cmd/s"
  puts "  1000 cmd burst: #{results[:cmd_burst_1000].round(1)} cmd/s"

  puts "\nTelemetry Throughput:"
  puts "  10 Hz target:    #{results[:tlm_10hz][:rate].round(1)} Hz (#{results[:tlm_10hz][:loss_percent]}% loss)"
  puts "  100 Hz target:   #{results[:tlm_100hz][:rate].round(1)} Hz (#{results[:tlm_100hz][:loss_percent]}% loss)"
  puts "  1000 Hz target:  #{results[:tlm_1000hz][:rate].round(1)} Hz (#{results[:tlm_1000hz][:loss_percent]}% loss)"
  puts "  2000 Hz target:  #{results[:tlm_2000hz][:rate].round(1)} Hz (#{results[:tlm_2000hz][:loss_percent]}% loss)"
  puts "  3000 Hz target:  #{results[:tlm_3000hz][:rate].round(1)} Hz (#{results[:tlm_3000hz][:loss_percent]}% loss)"

  puts "\n" + "#" * 60
  puts "# Test Complete"
  puts "#" * 60

  results
end

# Run the tests
run_throughput_tests
