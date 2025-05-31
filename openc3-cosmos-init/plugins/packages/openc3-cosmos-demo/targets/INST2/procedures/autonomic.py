# Get current list of groups
groups = autonomic_group_list()
print(f"Current groups: {groups}")

# Create a test group
group = "API"  # Make sure this is alphabetically after DEFAULT
result = autonomic_group_create(group)
print(f"Group created: {result}")
check_expression(f"'{result['name']}' == '{group}'")
wait()  # Allow the playwright spec to see the group

# Show the group info
result = autonomic_group_show(group)
print(f"Group info: {result}")
check_expression(f"'{result['name']}' == '{group}'")

# Verify group was added to list
groups = autonomic_group_list()
print(f"Updated groups: {groups}")
sorted_groups = sorted(groups, key=lambda g: g['name'])
check_expression(f"'{sorted_groups[0]['name']}' == '{group}'")
check_expression(f"'{sorted_groups[1]['name']}' == 'DEFAULT'")

# TRIGGER METHODS
# Get current list of triggers
triggers = autonomic_trigger_list(group=group)
print(f"Current triggers: {triggers}")

# Create a test trigger
left = {
    "type": "item",
    "target": "INST",
    "packet": "HEALTH_STATUS",
    "item": "TEMP1",
    "valueType": "CONVERTED",
}
operator = ">"
right = {
    "type": "float",
    "float": 0,
}

result = autonomic_trigger_create(left=left, operator=operator, right=right, group=group)
print(f"Trigger created: {result}")
test_trigger = result['name']
check_expression(f"'{result['enabled']}' == 'True'")
check_expression(f"'{result['group']}' == '{group}'")
check_expression(f"'{result['left']['type']}' == 'item'")
check_expression(f"'{result['left']['target']}' == 'INST'")
check_expression(f"'{result['left']['packet']}' == 'HEALTH_STATUS'")
check_expression(f"'{result['left']['item']}' == 'TEMP1'")
check_expression(f"'{result['left']['valueType']}' == 'CONVERTED'")
check_expression(f"'{result['operator']}' == '>'")
check_expression(f"'{result['right']['type']}' == 'float'")
check_expression(f"{result['right']['float']} == 0")
wait()  # Allow the playwright spec to see the trigger

# Show the trigger info
result = autonomic_trigger_show(test_trigger, group=group)
print(f"Trigger info: {result}")
check_expression(f"'{result['name']}' == '{test_trigger}'")
check_expression(f"'{result['enabled']}' == 'True'")
check_expression(f"'{result['group']}' == '{group}'")
check_expression(f"'{result['left']['type']}' == 'item'")
check_expression(f"'{result['left']['target']}' == 'INST'")
check_expression(f"'{result['left']['packet']}' == 'HEALTH_STATUS'")
check_expression(f"'{result['left']['item']}' == 'TEMP1'")
check_expression(f"'{result['left']['valueType']}' == 'CONVERTED'")
check_expression(f"'{result['operator']}' == '>'")
check_expression(f"'{result['right']['type']}' == 'float'")
check_expression(f"{result['right']['float']} == 0")

# Verify trigger was added to list
triggers = autonomic_trigger_list(group=group)
print(f"Updated triggers: {triggers}")

# Disable the trigger
autonomic_trigger_disable(test_trigger, group=group)
wait()  # Allow the playwright spec to see the disable

# Show the trigger info after disabling
trigger_info = autonomic_trigger_show(test_trigger, group=group)
print(f"Trigger info after disabling: {trigger_info}")

# Enable the trigger
autonomic_trigger_enable(test_trigger, group=group)
wait()  # Allow the playwright spec to see the enable

# Show the trigger info after enabling
trigger_info = autonomic_trigger_show(test_trigger, group=group)
print(f"Trigger info after enabling: {trigger_info}")

# Update the trigger
operator = "<="
right = {
    "type": "float",
    "float": 100,
}

result = autonomic_trigger_update(test_trigger, operator=operator, right=right, group=group)
print(f"Trigger updated: {result}")
wait()  # Allow the playwright spec to see the update

# Show the trigger info after updating
trigger_info = autonomic_trigger_show(test_trigger, group=group)
print(f"Trigger info after updating: {trigger_info}")

# REACTION METHODS
# Get current list of reactions
reactions = autonomic_reaction_list()
print(f"Current reactions: {reactions}")

# Create a test reaction
triggers = [{
    'name': test_trigger,
    'group': group,
}]
actions = [{
    'type': 'command',
    'value': 'INST ABORT'
}]

result = autonomic_reaction_create(triggers=triggers, actions=actions, trigger_level='EDGE', snooze=0)
print(f"Reaction created: {result}")
test_reaction = result['name']
wait()  # Allow the playwright spec to see the reaction

# Show the reaction info
reaction_info = autonomic_reaction_show(test_reaction)
print(f"Reaction info: {reaction_info}")

# Verify reaction was added to list
reactions = autonomic_reaction_list()
print(f"Updated reactions: {reactions}")

# Disable the reaction
autonomic_reaction_disable(test_reaction)
wait()  # Allow the playwright spec to see the disable

# Show the reaction info after disabling
reaction_info = autonomic_reaction_show(test_reaction)
print(f"Reaction info after disabling: {reaction_info}")

# Enable the reaction
autonomic_reaction_enable(test_reaction)
wait()  # Allow the playwright spec to see the enable

# Show the reaction info after enabling
reaction_info = autonomic_reaction_show(test_reaction)
print(f"Reaction info after enabling: {reaction_info}")

result = autonomic_reaction_update(test_reaction, trigger_level='LEVEL', snooze=300)
print(f"Reaction updated: {result}")
wait()  # Allow the playwright spec to see the update

# Show the reaction info after updating
reaction_info = autonomic_reaction_show(test_reaction)
print(f"Reaction info after updating: {reaction_info}")

# Execute the reaction
autonomic_reaction_execute(test_reaction)
wait()  # Allow the playwright spec to see the execution

# CLEANUP
autonomic_reaction_destroy(test_reaction)
wait()  # Allow the playwright spec to see the deletion
autonomic_trigger_destroy(test_trigger, group=group)
wait()  # Allow the playwright spec to see the deletion
autonomic_group_destroy(group)