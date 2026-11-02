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

# Verify the INST2 decom microservice (Python) recovers when limits events are
# trimmed from the limits event stream before it can read them.
#
# Decom microservices read limits events between batches of packets. The stream
# only keeps ~1000 events, so a decom microservice that falls behind during a
# flood of LIMITS_CHANGE events can lose control events like a limits group
# disable. It must detect the gap and reload the limits settings from the store.
#
# 1. Stall the INST2 decom microservice by injecting the DECOM_STALL packet
# 2. Disable the INST2_TEMP2 limits group while decom is stalled
# 3. Flood the stream with LIMITS_CHANGE events from INST until the group
#    event is trimmed
# 4. After decom resumes, verify it stopped checking limits on INST2 TEMP2
#
# Look for "Limits events were trimmed before they could be read, resyncing limits"
# from DEFAULT__DECOM__INST2 in the log messages. See procedures/limits_resync.rb
# in INST for the same test of a Ruby decom microservice.
import time

import openc3.script


STALL_SECONDS = 30  # Long enough to flood the stream (max 300)
TARGET = "INST2"
FLOOD_TARGET = "INST"  # Must have its own decom microservice
GROUP = "INST2_TEMP2"
FLOOD_ITEMS = ["TEMP2", "TEMP3", "TEMP4"]  # TEMP1 has a limits response which sends commands


def stream_id(id):
    return [int(part) for part in id.split("-")]


def newest_limits_event_id():
    newest = get_limits_events()
    return newest[0][0] if newest else "0-0"


def is_group_event(event):
    # Older versions send a LIMITS_ENABLE_STATE event per item instead of a group event
    if event["type"] == "LIMITS_GROUP_ENABLE_STATE":
        return event["group_name"] == GROUP
    return event["type"] == "LIMITS_ENABLE_STATE" and event["target_name"] == TARGET and event["item_name"] == "TEMP2"


def is_temp2_change(event):
    return (
        event["type"] == "LIMITS_CHANGE"
        and event["target_name"] == TARGET
        and event["packet_name"] == "HEALTH_STATUS"
        and event["item_name"] == "TEMP2"
        and bool(event.get("new_limits_state"))
    )


try:
    enable_limits_group(GROUP)
    for item in FLOOD_ITEMS:
        enable_limits(f"{FLOOD_TARGET} HEALTH_STATUS {item}")
    wait(2)  # Let decom apply the enables

    # 1. Stall decom. Its CVT stops updating while it's stalled.
    stall_start = time.time()
    inject_tlm(TARGET, "DECOM_STALL", {"SECONDS": STALL_SECONDS})
    wait(3)
    count = tlm(f"{TARGET} HEALTH_STATUS RECEIVED_COUNT")
    wait(2)
    if tlm(f"{TARGET} HEALTH_STATUS RECEIVED_COUNT") != count:
        raise RuntimeError(
            f"{TARGET} decom microservice did not stall. Was the demo plugin upgraded with the DECOM_STALL packet?"
        )
    print(f"{TARGET} decom microservice stalled for {STALL_SECONDS}s")

    # 2. Disable the group while decom can't read the event
    offset = newest_limits_event_id()
    disable_limits_group(GROUP)
    group_events = [id for id, event in get_limits_events(offset, count=1000) if is_group_event(event)]
    if not group_events:
        raise RuntimeError("Limits group event not found")
    group_event_id = group_events[0]
    print(
        f"Disabled {GROUP} with event {group_event_id}, "
        f"limits_enabled reports {limits_enabled(f'{TARGET} HEALTH_STATUS TEMP2')}"
    )

    # 3. Flood until the group event is trimmed from the stream
    trimmed = False
    injected = 0
    with disable_instrumentation():
        while time.time() < stall_start + STALL_SECONDS - 3:
            value = 90.0 if injected % 2 == 0 else 0.0  # RED_HIGH then GREEN
            # Call the API directly because inject_tlm prints every call, which overflows the script output
            openc3.script.API_SERVER.inject_tlm(
                FLOOD_TARGET, "HEALTH_STATUS", dict.fromkeys(FLOOD_ITEMS, value), type="CONVERTED"
            )
            injected += 1
            if injected % 100 == 0:
                print(f"Injected {injected} {FLOOD_TARGET} HEALTH_STATUS packets")
            if injected % 25 != 0:
                continue
            oldest = get_limits_events("0-0", count=1)
            if oldest and stream_id(oldest[0][0]) > stream_id(group_event_id):
                trimmed = True
                break
    print(f"Injected {injected} {FLOOD_TARGET} HEALTH_STATUS packets")
    if not trimmed:
        raise RuntimeError("Group event was not trimmed before decom resumed. Increase STALL_SECONDS.")
    print(f"Group event {group_event_id} trimmed from the limits event stream")

    # 4. Wait for decom to resume and work through its backlog
    remaining = stall_start + STALL_SECONDS + 30 - time.time()
    if not wait(f"{TARGET} HEALTH_STATUS RECEIVED_COUNT > {count}", remaining):
        raise RuntimeError(f"{TARGET} decom microservice did not resume")
    wait(3)

    # A decom microservice still checking TEMP2 reports these state changes
    offset = newest_limits_event_id()
    inject_tlm(TARGET, "HEALTH_STATUS", {"TEMP2": 0.0})
    wait(1)
    inject_tlm(TARGET, "HEALTH_STATUS", {"TEMP2": 90.0})
    wait(3)
    changes = [event for _, event in get_limits_events(offset, count=1000) if is_temp2_change(event)]
    if changes:
        for event in changes:
            print(event["message"])
        raise RuntimeError(
            f"FAIL: {TARGET} decom microservice missed the group event and is still checking limits on TEMP2"
        )
    print(f"PASS: {TARGET} decom microservice resynced and stopped checking limits on TEMP2")
finally:
    enable_limits_group(GROUP)
