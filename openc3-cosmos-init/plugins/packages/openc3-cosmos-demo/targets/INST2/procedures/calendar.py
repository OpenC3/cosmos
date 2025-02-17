from datetime import datetime, timezone, timedelta

tl = create_timeline("PythonTL", color="#FF0000")
print(tl) #=> {'name': 'PythonTL', 'color': '#FF0000', 'execute': True, 'shard': 0, 'scope': 'DEFAULT', 'updated_at': 1737129062249843763}
tls = list_timelines()
print(tls) #=> [{'name': 'PythonTL', 'color': '#FF0000', 'execute': True, 'shard': 0, 'scope': 'DEFAULT', 'updated_at': 1737129062249843763}]
names = [tl["name"] for tl in tls]
check_expression(f"{'PythonTL' in names} == True")
print(tls[0])  #=> {'name': 'PythonTL', 'color': '#FF0000', 'execute': True, 'shard': 0, 'scope': 'DEFAULT', 'updated_at': 1737129436186473255}

set_timeline_color("PythonTL", "#4287f5")
print(get_timeline("PythonTL")) #=> {'name': 'PythonTL', 'color': '#4287f5', 'execute': True, 'shard': 0, 'scope': 'DEFAULT', 'updated_at': 1737129508391137136}

now = datetime.now(timezone.utc)
start = now + timedelta(hours=1)
stop = start + timedelta(hours=1)
act1 = create_timeline_activity("PythonTL", kind="reserve", start=start, stop=stop)
print(act1)  # =>
# {'name': 'PythonTL', 'updated_at': 1737129305507111708, 'start': 1737132902, 'stop': 1737136502,
#  'kind': 'reserve', 'data': {'username': 'operator'},
#  'scope': 'DEFAULT', 'fulfillment': False, 'uuid': '46328378-ed78-4719-ad70-e84951a196fd',
#  'events': [{'time': 1737129305, 'event': 'created'}], 'recurring': {}}
act2 = create_timeline_activity("PythonTL", kind="COMMAND", start=start, stop=stop,
    data={'command': "INST COLLECT with TYPE NORMAL, DURATION 5, TEMP 10"})
print(act2) #=>
# {'name': 'PythonTL', 'updated_at': 1737129508886643928, 'start': 1737133108, 'stop': 1737136708,
#  'kind': 'command', 'data': {'command': 'INST COLLECT with TYPE NORMAL, DURATION 5, TEMP 10', 'username': 'operator'},
#  'scope': 'DEFAULT', 'fulfillment': False, 'uuid': 'cddbf034-ccdd-4c36-91c2-2653a39b06a5',
#  'events': [{'time': 1737129508, 'event': 'created'}], 'recurring': {}}
start = now + timedelta(hours=2)
stop = start + timedelta(hours=1)
act3 = create_timeline_activity("PythonTL", kind="SCRIPT", start=start, stop=stop,
  data={'environment': [{'key': "USER", 'value': "JASON"}], 'script': "INST2/procedures/checks.py"})
print(act3) #=>
# {'name': 'PythonTL', 'updated_at': 1737129509288571345, 'start': 1737136708, 'stop': 1737140308,
#  'kind': 'script', 'data': {'environment': [{'key': 'USER', 'value': 'JASON'}], 'script': 'INST2/procedures/checks.py', 'username': 'operator'},
#  'scope': 'DEFAULT', 'fulfillment': False, 'uuid': '4f8d791b-b138-4383-b5ec-85c28b2bea20',
#  'events': [{'time': 1737129509, 'event': 'created'}], 'recurring': {}}

act = get_timeline_activity("PythonTL", act2['start'], act2['uuid'])
print(act) #=>
# { "name"=>"RubyTL", "updated_at"=>1737128761316084471, "start"=>1737132303, "stop"=>1737135903,
#   "kind"=>"command", "data"=>{"command"=>"INST COLLECT with TYPE NORMAL, DURATION 5, TEMP 10", "username"=>"operator"},
#   "scope"=>"DEFAULT", "fulfillment"=>false, "uuid"=>"cdb661b4-a65b-44e7-95e2-5e1dba80c782",
#   "events"=>[{"time"=>1737128761, "event"=>"created"}], "recurring"=>{}}

# Get activities in the past ... should be none
tlas = get_timeline_activities("PythonTL", start=now - timedelta(hours=2), stop=now)
print(tlas)
print(type(tlas))
check_expression(f"{len(tlas)} == 0")
# Get all activities at plus and minus 1 week
tlas = get_timeline_activities("PythonTL")
check_expression(f"{len(tlas)} == 3")

# Create and delete a new activity
start = start + timedelta(hours=2)
stop = start + timedelta(minutes=30)
act = create_timeline_activity("PythonTL", kind="reserve", start=start, stop=stop)
tlas = get_timeline_activities("PythonTL")
check_expression(f"{len(tlas)} == 4")
delete_timeline_activity("PythonTL", act["start"], act["uuid"])
tlas = get_timeline_activities("PythonTL")
check_expression(f"{len(tlas)} == 3")

# delete fails since the timeline has activities
delete_timeline("PythonTL")
# Force delete since the timeline has activities
delete_timeline("PythonTL", force=True)
tls = list_timelines()
names = [tl["name"] for tl in tls]
check_expression(f"{'PythonTL' in names} == False")
