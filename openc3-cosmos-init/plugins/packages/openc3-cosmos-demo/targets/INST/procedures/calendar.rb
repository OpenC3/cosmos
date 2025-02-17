tl = create_timeline("RubyTL")
puts tl #=> {"name"=>"RubyTL", "color"=>"#cdce42", "execute"=>true, "shard"=>0, "scope"=>"DEFAULT", "updated_at"=>1737128664493258134}
tls = list_timelines()
names = tls.map { |tl| tl['name'] }
check_expression("#{names.include?('RubyTL')} == true")
puts tls[0] #=> {"name"=>"RubyTL", "color"=>"#cdce42", "execute"=>true, "shard"=>0, "scope"=>"DEFAULT", "updated_at"=>1737128664493258134}

set_timeline_color("RubyTL", "#4287f5")
puts get_timeline("RubyTL") #=> {"name"=>"RubyTL", "color"=>"#4287f5", "execute"=>true, "shard"=>0, "scope"=>"DEFAULT", "updated_at"=>1737128689586673173}

now = Time.now()
start = now + 3600
stop = start + 3600
act1 = create_timeline_activity("RubyTL", kind: "RESERVE", start: start, stop: stop)
puts act1 #=>
# { "name"=>"RubyTL", "updated_at"=>1737128705034982375, "start"=>1737132303, "stop"=>1737135903,
#   "kind"=>"reserve", "data"=>{"username"=>"operator"},
#   "scope"=>"DEFAULT", "fulfillment"=>false, "uuid"=>"5f373846-eb6c-43cd-97bd-cca19a8ffb04",
#   "events"=>[{"time"=>1737128705, "event"=>"created"}], "recurring"=>{}}
act2 = create_timeline_activity("RubyTL", kind: "COMMAND", start: start, stop: stop,
    data: {command: "INST COLLECT with TYPE NORMAL, DURATION 5, TEMP 10"})
puts act2 #=>
# { "name"=>"RubyTL", "updated_at"=>1737128761316084471, "start"=>1737132303, "stop"=>1737135903,
#   "kind"=>"command", "data"=>{"command"=>"INST COLLECT with TYPE NORMAL, DURATION 5, TEMP 10", "username"=>"operator"},
#   "scope"=>"DEFAULT", "fulfillment"=>false, "uuid"=>"cdb661b4-a65b-44e7-95e2-5e1dba80c782",
#   "events"=>[{"time"=>1737128761, "event"=>"created"}], "recurring"=>{}}
start = now + 7200
stop = start + 3600
act3 = create_timeline_activity("RubyTL", kind: "SCRIPT", start: start, stop: stop,
  data: {environment: [{key: "USER", value: "JASON"}], script: "INST/procedures/checks.rb"})
puts act3 #=>
# { "name"=>"RubyTL", "updated_at"=>1737128791047885970, "start"=>1737135903, "stop"=>1737139503,
#   "kind"=>"script", "data"=>{"environment"=>[{"key"=>"USER", "value"=>"JASON"}], "script"=>"INST/procedures/checks.rb", "username"=>"operator"},
#   "scope"=>"DEFAULT", "fulfillment"=>false, "uuid"=>"70426e3d-6313-4897-b159-6e5cd94ace1d",
#   "events"=>[{"time"=>1737128791, "event"=>"created"}], "recurring"=>{}}

act = get_timeline_activity("RubyTL", act2['start'], act2['uuid'])
puts act #=>
# { "name"=>"RubyTL", "updated_at"=>1737128761316084471, "start"=>1737132303, "stop"=>1737135903,
#   "kind"=>"command", "data"=>{"command"=>"INST COLLECT with TYPE NORMAL, DURATION 5, TEMP 10", "username"=>"operator"},
#   "scope"=>"DEFAULT", "fulfillment"=>false, "uuid"=>"cdb661b4-a65b-44e7-95e2-5e1dba80c782",
#   "events"=>[{"time"=>1737128761, "event"=>"created"}], "recurring"=>{}}

# Get activities in the past ... should be none
tlas = get_timeline_activities("RubyTL", start: Time.now() - 3600, stop: Time.now())
check_expression("#{tlas.length} == 0")
# Get all activities at plus and minus 1 week
tlas = get_timeline_activities("RubyTL")
check_expression("#{tlas.length} == 3")

# Create and delete a new activity
start = start + 7200
stop = start + 300
act = create_timeline_activity("RubyTL", kind: "reserve", start: start, stop: stop)
tlas = get_timeline_activities("RubyTL")
check_expression("#{tlas.length} == 4")
delete_timeline_activity("RubyTL", act['start'], act['uuid'])
tlas = get_timeline_activities("RubyTL")
check_expression("#{tlas.length} == 3")

# delete fails since the timeline has activities
delete_timeline("RubyTL") #=> RuntimeError : Failed to delete timeline due to timeline contains activities, must force remove
# Force delete since the timeline has activities
delete_timeline("RubyTL", force: true)
# Verify the timeline no longer exists
tls = list_timelines()
names = tls.map { |tl| tl['name'] }
check_expression("#{names.include?('RubyTL')} == false")
