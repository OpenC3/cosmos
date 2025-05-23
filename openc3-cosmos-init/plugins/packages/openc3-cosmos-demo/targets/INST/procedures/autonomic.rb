# Get current list of groups
groups = autonomic_group_list()
puts "Current groups: #{groups.inspect}"

# Create a test group
group = "API" # Make sure this is alphabetically after DEFAULT
result = autonomic_group_create(group)
puts "Group created: #{result.inspect}"
check_expression("'#{result['name']}' == '#{group}'")
wait # Allow the playwright spec to see the group

# Show the group info
result = autonomic_group_show(group)
puts "Group info: #{result.inspect}"
check_expression("'#{result['name']}' == '#{group}'")

# Verify group was added to list
groups = autonomic_group_list()
puts "Updated groups: #{groups.inspect}"
sorted = groups.sort_by { |g| g['name'] }
check_expression("'#{sorted[0]['name']}' == '#{group}'")
check_expression("'#{sorted[1]['name']}' == 'DEFAULT'")

# TRIGGER METHODS
# Get current list of triggers
triggers = autonomic_trigger_list(group: group)
puts "Current triggers: #{triggers.inspect}"

# Create a test trigger
left = {
  type: "item",
  target: "INST",
  packet: "HEALTH_STATUS",
  item: "TEMP1",
  valueType: "CONVERTED",
}
operator = ">"
right = {
  type: "float",
  float: 0,
}

result = autonomic_trigger_create(left: left, operator: operator, right: right, group: group)
puts "Trigger created: #{result.inspect}"
test_trigger = result['name']
check_expression("'#{result['enabled']}' == 'true'")
check_expression("'#{result['group']}' == '#{group}'")
check_expression("'#{result['left']['type']}' == 'item'")
check_expression("'#{result['left']['target']}' == 'INST'")
check_expression("'#{result['left']['packet']}' == 'HEALTH_STATUS'")
check_expression("'#{result['left']['item']}' == 'TEMP1'")
check_expression("'#{result['left']['valueType']}' == 'CONVERTED'")
check_expression("'#{result['operator']}' == '>'")
check_expression("'#{result['right']['type']}' == 'float'")
check_expression("#{result['right']['float']} == 0")
wait # Allow the playwright spec to see the trigger

# Show the trigger info
result = autonomic_trigger_show(test_trigger, group: group)
puts "Trigger info: #{result.inspect}"
check_expression("'#{result['name']}' == '#{test_trigger}'")
check_expression("'#{result['enabled']}' == 'true'")
check_expression("'#{result['group']}' == '#{group}'")
check_expression("'#{result['left']['type']}' == 'item'")
check_expression("'#{result['left']['target']}' == 'INST'")
check_expression("'#{result['left']['packet']}' == 'HEALTH_STATUS'")
check_expression("'#{result['left']['item']}' == 'TEMP1'")
check_expression("'#{result['left']['valueType']}' == 'CONVERTED'")
check_expression("'#{result['operator']}' == '>'")
check_expression("'#{result['right']['type']}' == 'float'")
check_expression("#{result['right']['float']} == 0")

# Verify trigger was added to list
triggers = autonomic_trigger_list(group: group)
puts "Updated triggers: #{triggers.inspect}"

# Disable the trigger
autonomic_trigger_disable(test_trigger, group: group)
wait # Allow the playwright spec to see the disable

# Show the trigger info after disabling
trigger_info = autonomic_trigger_show(test_trigger, group: group)
puts "Trigger info after disabling: #{trigger_info.inspect}"

# Enable the trigger
autonomic_trigger_enable(test_trigger, group: group)
wait # Allow the playwright spec to see the enable

# Show the trigger info after enabling
trigger_info = autonomic_trigger_show(test_trigger, group: group)
puts "Trigger info after enabling: #{trigger_info.inspect}"

# Update the trigger
operator = "<="
right = {
  type: "float",
  float: 100,
}

result = autonomic_trigger_update(test_trigger, operator: operator, right: right, group: group)
puts "Trigger updated: #{result.inspect}"
wait # Allow the playwright spec to see the update

# Show the trigger info after updating
trigger_info = autonomic_trigger_show(test_trigger, group: group)
puts "Trigger info after updating: #{trigger_info.inspect}"

# REACTION METHODS
# Get current list of reactions
reactions = autonomic_reaction_list()
puts "Current reactions: #{reactions.inspect}"

# Create a test reaction
triggers = [{
  'name' => test_trigger,
  'group' => group,
}]
actions = [{
  'type' => 'command',
  'value' => 'INST ABORT'
}]

result = autonomic_reaction_create(triggers: triggers, actions: actions, trigger_level: 'EDGE', snooze: 0)
puts "Reaction created: #{result.inspect}"
test_reaction = result['name']
wait # Allow the playwright spec to see the reaction

# Show the reaction info
reaction_info = autonomic_reaction_show(test_reaction)
puts "Reaction info: #{reaction_info.inspect}"

# Verify reaction was added to list
reactions = autonomic_reaction_list()
puts "Updated reactions: #{reactions.inspect}"

# Disable the reaction
autonomic_reaction_disable(test_reaction)
wait # Allow the playwright spec to see the disable

# Show the reaction info after disabling
reaction_info = autonomic_reaction_show(test_reaction)
puts "Reaction info after disabling: #{reaction_info.inspect}"

# Enable the reaction
autonomic_reaction_enable(test_reaction)
wait # Allow the playwright spec to see the enable

# Show the reaction info after enabling
reaction_info = autonomic_reaction_show(test_reaction)
puts "Reaction info after enabling: #{reaction_info.inspect}"

result = autonomic_reaction_update(test_reaction, trigger_level: 'LEVEL', snooze: 300)
puts "Reaction updated: #{result.inspect}"
wait # Allow the playwright spec to see the update

# Show the reaction info after updating
reaction_info = autonomic_reaction_show(test_reaction)
puts "Reaction info after updating: #{reaction_info.inspect}"

# Execute the reaction
autonomic_reaction_execute(test_reaction)
wait # Allow the playwright spec to see the execution

# CLEANUP
autonomic_reaction_destroy(test_reaction)
wait # Allow the playwright spec to see the deletion
autonomic_trigger_destroy(test_trigger, group: group)
wait # Allow the playwright spec to see the deletion
autonomic_group_destroy(group)
