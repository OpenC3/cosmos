# Create a trigger on INST2 HEALTH_STATUS TEMP1 > 0 and a reaction
# that runs INST2/procedures/stash.py with a notification.

group = "DEFAULT"

# Create the trigger
left = {
  type: "item",
  target: "INST2",
  packet: "HEALTH_STATUS",
  item: "TEMP1",
  valueType: "CONVERTED",
}
operator = ">"
right = {
  type: "float",
  float: 0,
}

trigger = autonomic_trigger_create(left: left, operator: operator, right: right, group: group)
puts "Trigger created: #{trigger.inspect}"
trigger_name = trigger['name']

# Create the reaction with a notification and a script action
triggers = [{
  'name' => trigger_name,
  'group' => group,
}]
actions = [
  {
    'type' => 'script',
    'value' => 'INST2/procedures/stash.py',
    'environment' => [],
  },
  {
    'type' => 'notify',
    'value' => 'TEMP1 above 0 - running stash.py',
    'severity' => 'WARN',
  },
]

reaction = autonomic_reaction_create(triggers: triggers, actions: actions, trigger_level: 'EDGE', snooze: 300)
puts "Reaction created: #{reaction.inspect}"
