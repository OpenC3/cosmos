# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import re
import json
from openc3.topics.topic import Topic
from openc3.system.system import System
from openc3.utilities.store import Store
from openc3.utilities.json import JsonEncoder, JsonDecoder


# LimitsEventTopic keeps track of not only the <SCOPE>__openc3_limits_events topic
# but also the ancillary key value stores. The LIMITS_CHANGE event updates the
# <SCOPE>__current_limits key. The LIMITS_SET event updates the <SCOPE>__limits_sets.
# The LIMITS_SETTINGS event updates the <SCOPE>__current_limits_settings.
# While this isn't a clean separation of topics (streams) and models (key-value)
# it helps maintain consistency as the topic and model are linked.
class LimitsEventTopic(Topic):
    @classmethod
    def write(cls, event, scope):
        match event["type"]:
            case "LIMITS_CHANGE":
                # The current_limits hash keeps only the current limits state of items
                # It is used by the API to determine the overall limits state
                field = f"{event['target_name']}__{event['packet_name']}__{event['item_name']}"
                Store.hset(f"{scope}__current_limits", field, event["new_limits_state"])

            case "LIMITS_SETTINGS":
                # Limits updated in limits_api.rb to avoid circular reference to TargetModel
                if cls.sets(scope=scope).get(event["limits_set"], None) is None:
                    Store.hset(f"{scope}__limits_sets", event["limits_set"], "false")

                field = f"{event['target_name']}__{event['packet_name']}__{event['item_name']}"
                limits_settings = Store.hget(f"{scope}__current_limits_settings", field)
                if limits_settings:
                    limits_settings = json.loads(limits_settings)
                else:
                    limits_settings = {}
                limits = {}
                limits["red_low"] = event["red_low"]
                limits["yellow_low"] = event["yellow_low"]
                limits["yellow_high"] = event["yellow_high"]
                limits["red_high"] = event["red_high"]
                if event.get("green_low") and event.get("green_high"):
                    limits["green_low"] = event["green_low"]
                    limits["green_high"] = event["green_high"]
                limits_settings[event["limits_set"]] = limits
                if event.get("persistence"):
                    limits_settings["persistence_setting"] = event["persistence"]
                if event.get("enabled", None) is not None:
                    limits_settings["enabled"] = event["enabled"]
                Store.hset(
                    f"{scope}__current_limits_settings",
                    field,
                    json.dumps(limits_settings),
                )

            case "LIMITS_ENABLE_STATE":
                field = f"{event['target_name']}__{event['packet_name']}__{event['item_name']}"
                limits_settings = Store.hget(f"{scope}__current_limits_settings", field)
                if limits_settings:
                    limits_settings = json.loads(limits_settings)
                else:
                    limits_settings = {}
                limits_settings["enabled"] = event["enabled"]
                Store.hset(
                    f"{scope}__current_limits_settings",
                    field,
                    json.dumps(limits_settings),
                )

            case "LIMITS_SET":
                sets = cls.sets(scope=scope)
                if sets.get(event["set"]) is None:
                    raise RuntimeError(f"Set '{event['set']}' does not exist!")

                # Set all existing sets to "false"
                sets = dict.fromkeys(sets, "false")
                sets[event["set"]] = "true"  # Enable the requested set
                Store.hset(f"{scope}__limits_sets", mapping=sets)
            case _:
                raise RuntimeError(f"Invalid limits event type '{event['type']}'")

        Topic.write_topic(
            f"{scope}__openc3_limits_events",
            {"event": json.dumps(event, cls=JsonEncoder)},
            "*",
            1000,
        )

    # Remove the JSON encoding to return hashes directly
    @classmethod
    def read(cls, offset=None, count=100, scope=None):
        final_result = []
        topic = f"{scope}__openc3_limits_events"
        if offset is not None:
            for topic, msg_id, msg_hash, redis in Topic.read_topics([topic], [offset], None, count):
                # result = Topic.read_topics([topic], [offset], None, count)
                # if len(result) != 0:
                # result is a hash with the topic key followed by an array of results
                # This returns just the array of arrays [[offset, hash], [offset, hash], ...]
                final_result.append([msg_id, msg_hash])
        else:
            result = Topic.get_newest_message(topic)
            if result:
                final_result = [result]
        parsed_result = []
        for offset, hash in final_result:
            parsed_result.append([offset, json.loads(hash[b"event"], cls=JsonDecoder)])
        return parsed_result

    @classmethod
    def out_of_limits(cls, scope):
        out_of_limits = []
        limits = Store.hgetall(f"{scope}__current_limits")
        # decode the binary string keys to strings
        limits = {k.decode(): v.decode() for (k, v) in limits.items()}
        for item, limits_state in limits.items():
            if limits_state in [
                "RED",
                "RED_HIGH",
                "RED_LOW",
                "YELLOW",
                "YELLOW_HIGH",
                "YELLOW_LOW",
            ]:
                target_name, packet_name, item_name = item.split("__")
                out_of_limits.append([target_name, packet_name, item_name, limits_state])
        return out_of_limits

    # Returns all the limits sets as keys with the value 'true' or 'false'
    # where only the active set is 'true'
    #
    # @return [Hash{String => String}] Set name followed by 'true' if enabled else 'false'
    @classmethod
    def sets(cls, scope):
        sets = Store.hgetall(f"{scope}__limits_sets")
        # decode the binary string keys to strings
        return {k.decode(): v.decode() for (k, v) in sets.items()}

    @classmethod
    def current_set(cls, scope):
        sets = LimitsEventTopic.sets(scope=scope)
        # Lookup the key with a true value because there should only ever be one
        try:
            return list(sets.keys())[list(sets.values()).index("true")]
        except ValueError:
            return "DEFAULT"

    # Cleanups up the current_limits and current_limits_settings keys for
    # a target or target/packet combination
    @classmethod
    def delete(cls, target_name, packet_name=None, scope=None):
        limits = Store.hgetall(f"{scope}__current_limits")
        # decode the binary string keys to strings
        limits = {k.decode(): v for (k, v) in limits.items()}
        for item, _ in limits.items():
            if packet_name:
                if re.match(rf"^{target_name}__{packet_name}__", item):
                    Store.hdel(f"{scope}__current_limits", item)
            else:
                if re.match(rf"^{target_name}__", item):
                    Store.hdel(f"{scope}__current_limits", item)

        limits_settings = Store.hgetall(f"{scope}__current_limits_settings")
        # decode the binary string keys to strings
        limits_settings = {k.decode(): v for (k, v) in limits_settings.items()}
        for item, _ in limits_settings.items():
            if packet_name:
                if re.match(rf"^{target_name}__{packet_name}__", item):
                    Store.hdel(f"{scope}__current_limits_settings", item)
            else:
                if re.match(rf"^{target_name}__", item):
                    Store.hdel(f"{scope}__current_limits_settings", item)

    # Update the local System based on overall state
    @classmethod
    def sync_system(cls, scope):
        all_limits_settings = Store.hgetall(f"{scope}__current_limits_settings")
        # decode the binary string keys to strings
        all_limits_settings = {k.decode(): v for (k, v) in all_limits_settings.items()}
        telemetry = System.telemetry.all()
        for item, limits_settings in all_limits_settings.items():
            target_name, packet_name, item_name = item.split("__")
            target = telemetry.get(target_name, None)
            if target is not None:
                packet = target.get(packet_name, None)
                if packet is not None:
                    limits_settings = json.loads(limits_settings)
                    enabled = limits_settings.get("enabled", None)
                    persistence = limits_settings.get("persistence_setting", 1)
                    for limits_set, settings in limits_settings.items():
                        if not isinstance(settings, dict):
                            continue
                        System.limits.set(
                            target_name,
                            packet_name,
                            item_name,
                            settings["red_low"],
                            settings["yellow_low"],
                            settings["yellow_high"],
                            settings["red_high"],
                            settings.get("green_low", None),
                            settings.get("green_high", None),
                            str(limits_set),
                            persistence,
                            enabled,
                        )
                    if enabled is not None:
                        if enabled:
                            System.limits.enable(target_name, packet_name, item_name)
                        else:
                            System.limits.disable(target_name, packet_name, item_name)

    # Update the local system based on limits events
    @classmethod
    def sync_system_thread_body(cls, scope):
        telemetry = System.telemetry.all()
        topics = [f"{scope}__openc3_limits_events"]
        for _, _, event, _ in Topic.read_topics(topics, timeout_ms=None):
            event = json.loads(event[b"event"], cls=JsonDecoder)
            match event["type"]:
                case "LIMITS_CHANGE":
                    pass  # Ignore
                case "LIMITS_SETTINGS":
                    target_name = event["target_name"]
                    packet_name = event["packet_name"]
                    item_name = event["item_name"]
                    target = telemetry.get(target_name)
                    if target:
                        packet = target.get(packet_name)
                        if packet:
                            enabled = event.get("enabled", None)
                            persistence = event.get("persistence", 1)
                            System.limits.set(
                                target_name,
                                packet_name,
                                item_name,
                                event["red_low"],
                                event["yellow_low"],
                                event["yellow_high"],
                                event["red_high"],
                                event.get("green_low", None),
                                event.get("green_high", None),
                                event["limits_set"],
                                persistence,
                                enabled,
                            )

                case "LIMITS_ENABLE_STATE":
                    target_name = event["target_name"]
                    packet_name = event["packet_name"]
                    item_name = event["item_name"]
                    target = telemetry.get(target_name)
                    if target:
                        packet = target.get(packet_name)
                        if packet:
                            enabled = event.get("enabled", False)
                            if enabled:
                                System.limits.enable(target_name, packet_name, item_name)
                            else:
                                System.limits.disable(target_name, packet_name, item_name)

                case "LIMITS_SET":
                    pass  # Ignore, System.limits_set() always queries Redis
