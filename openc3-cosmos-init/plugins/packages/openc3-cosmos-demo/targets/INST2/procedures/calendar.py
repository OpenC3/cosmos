from datetime import datetime, timezone, timedelta

tl = create_timeline("MINE")
print(
    tl
)  # => {"name":"MINE", "color":"#ae2d1b", "scope":"DEFAULT", "updated_at":1698763720728596964}
tls = list_timelines()
print(tls)
print(type(tls))
check_expression(f"{len(tls)} == 1")
print(
    tls[0]
)  # => {"name":"MINE", "color":"#ae2d1b", "scope":"DEFAULT", "updated_at":1698763720728596964}
delete_timeline("MINE")
check_expression(f"{len(list_timelines())} == 0")

create_timeline("MINE")
set_timeline_color("MINE", "#4287f5")
print(
    get_timeline("MINE")
)  # => {"name":"MINE", "color":"#4287f5", "scope":"DEFAULT", "updated_at":1698763720728596964}

now = datetime.now(timezone.utc)
start = datetime(now.year, now.month, now.day, now.hour + 1, 30, 00, 00, timezone.utc)
stop = start + timedelta(hours=1)  # Stop plus 1hr
act = create_timeline_activity("MINE", kind="reserve", start=start, stop=stop)
print(act)  # =>
# { "name"=>"MINE", "updated_at"=>1698763721927799173, "fulfillment"=>false, "duration"=>3600,
#   "start"=>1698764400, "stop"=>1698768000, "kind"=>"reserve",
#   "events"=>[{"time"=>1698763721, "event"=>"created"}], "data"=>{"username"=>""} }
# Get activities in the past ... should be none
tlas = get_timeline_activities("MINE", start=start - timedelta(hours=1), stop=now)
print(tlas)
print(type(tlas))
check_expression(f"{len(tlas)} == 0")
# Get all activities
tlas = get_timeline_activities("MINE")
check_expression(f"{len(tlas)} == 1")

# Create and delete a new activity
start = start + timedelta(hours=2)
stop = start + timedelta(minutes=30)
act = create_timeline_activity("MINE", kind="reserve", start=start, stop=stop)
tlas = get_timeline_activities("MINE")
check_expression(f"{len(tlas)} == 2")
delete_timeline_activity("MINE", act["start"])
tlas = get_timeline_activities("MINE")
check_expression(f"{len(tlas)} == 1")

# delete fails since the timeline has activities
delete_timeline(
    "MINE"
)  #: RuntimeError : Failed to delete timeline due to timeline contains activities, must force remove
# Force delete since the timeline has activities
delete_timeline("MINE", force=True)
tls = list_timelines()
check_expression(f"{len(tls)} == 0")
