out_of_limits = get_out_of_limits()
out_of_limits.each do |target_name, packet_name, item_name, limits_state|
  puts "#{target_name} #{packet_name} #{item_name} is #{limits_state}"
end

limits_state = get_overall_limits_state()
check_expression("['GREEN', 'YELLOW', 'RED'].include?(limits_state)", binding())

set_limits("INST", "HEALTH_STATUS", "TEMP1", -100, -10, 10, 100, nil, nil, 'DEFAULT')
limits = get_limits("INST", "HEALTH_STATUS", "TEMP1")
check_expression("[-100, -10, 10, 100] == limits['DEFAULT']", binding())
limits.each do |key, values_array|
  puts "INST HEALTH_STATUS TEMP1 Limits: [#{values_array.join(' ')}]"
end

set_limits("INST", "HEALTH_STATUS", "TEMP1", -80.0, -70.0, 60.0, 80.0, -20.0, 20.0, 'DEFAULT')
limits = get_limits("INST", "HEALTH_STATUS", "TEMP1")
check_expression("[-80.0, -70.0, 60.0, 80.0, -20.0, 20.0] == limits['DEFAULT']", binding())
limits.each do |key, values_array|
  puts "INST HEALTH_STATUS TEMP1 Limits: [#{values_array.join(' ')}]"
end

set_limits("INST", "HEALTH_STATUS", "TEMP1", -80.0, -70.0, 60.0, 80.0, -20.0, 20.0, 'TVAC')
limits = get_limits("INST", "HEALTH_STATUS", "TEMP1")
check_expression("[-80.0, -70.0, 60.0, 80.0, -20.0, 20.0] == limits['TVAC']", binding())
limits.each do |key, values_array|
  puts "INST HEALTH_STATUS TEMP1 Limits: [#{values_array.join(' ')}]"
end

set_limits("INST", "HEALTH_STATUS", "TEMP1", -80.0, -30.0, 30.0, 80.0, nil, nil, 'TVAC')
limits = get_limits("INST", "HEALTH_STATUS", "TEMP1")
check_expression("[-80.0, -30.0, 30.0, 80.0] == limits['TVAC']", binding())
limits.each do |key, values_array|
  puts "INST HEALTH_STATUS TEMP1 Limits: [#{values_array.join(' ')}]"
end

puts "INST HEALTH_STATUS TEMP1 Limits Enabled: #{limits_enabled?("INST HEALTH_STATUS TEMP1")}"

# INST and INST2 both define TEMPS, GROUND and PAYLOAD so ask for INST2's groups
limits_groups = get_limits_groups('INST2')
check_expression("['GROUND', 'PAYLOAD', 'TEMPS'] == limits_groups.keys.sort", binding())
check_expression("[['INST2', 'HEALTH_STATUS', 'GROUND1STATUS'], ['INST2', 'HEALTH_STATUS', 'GROUND2STATUS']] == limits_groups['GROUND']", binding())
check_expression("[['INST2', 'LIMITS_GROUP', 'TEMPS'], ['INST2', 'LIMITS_GROUP', 'GROUND']] == limits_groups['PAYLOAD']", binding())
# Without a target a group name several targets define is keyed TARGET__GROUP
all_limits_groups = get_limits_groups()
check_expression("all_limits_groups.key?('INST__GROUND') && all_limits_groups.key?('INST2__GROUND')", binding())
limits_groups.each do |group_name, group_items_array|
  puts "Limits Group: #{group_name}"
  group_items_array.each do |target_name, packet_name, item_name|
    puts "  #{target_name} #{packet_name} #{item_name}"
  end
end

disable_limits("INST HEALTH_STATUS TEMP1")
check_expression("limits_enabled?('INST HEALTH_STATUS TEMP1') == false")
enable_limits("INST HEALTH_STATUS TEMP1")
check_expression("limits_enabled?('INST HEALTH_STATUS TEMP1') == true")

puts "INST2 HEALTH_STATUS GROUND1STATUS Limits Enabled: #{limits_enabled?('INST2 HEALTH_STATUS GROUND1STATUS')}"
puts "INST2 HEALTH_STATUS GROUND2STATUS Limits Enabled: #{limits_enabled?('INST2 HEALTH_STATUS GROUND2STATUS')}"
disable_limits_group("INST2", "GROUND")
check_expression("limits_enabled?('INST2 HEALTH_STATUS GROUND1STATUS') == false")
check_expression("limits_enabled?('INST2 HEALTH_STATUS GROUND2STATUS') == false")
# The group's rollup is telemetry in the LIMITS_GROUP packet of the target which defines it
wait_check("INST2 LIMITS_GROUP GROUND_ENABLED == 'FALSE'", 5)
wait_check("INST2 LIMITS_GROUP PAYLOAD_ENABLED == 'FALSE'", 5)
enable_limits_group("INST2", "GROUND")
check_expression("limits_enabled?('INST2 HEALTH_STATUS GROUND1STATUS') == true")
check_expression("limits_enabled?('INST2 HEALTH_STATUS GROUND2STATUS') == true")
wait_check("INST2 LIMITS_GROUP GROUND_ENABLED == 'TRUE'", 5)

puts "Current Limits Set: #{get_limits_set()}"
set_limits_set('TVAC')
check_expression("get_limits_set() == 'TVAC'")
set_limits_set('DEFAULT')
check_expression("get_limits_set() == 'DEFAULT'")

events = get_limits_events()
puts events.inspect
limits_offset = nil
if events.length > 0
  events.each do |offset, event|
    limits_offset = offset
    puts "Limits Event Offset: #{offset}, Event: #{event.inspect}"
  end
end

puts "Limits Offset: #{limits_offset}"
wait(10)

events = get_limits_events(limits_offset)
if events.length > 0
  events.each do |offset, event|
    limits_offset = offset
    puts "Limits Event Offset: #{offset}, Event: #{event.inspect}"
  end
end
