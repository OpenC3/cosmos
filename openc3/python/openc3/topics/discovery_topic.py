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

import json

from openc3.topics.topic import Topic


# Discovery requests flow from COSMOS (Ruby DiscoveryTopic.discover) to a bridge
# hub over the request topic. The hub hands them to openc3-cosmos-app, which runs the
# Discovery class on the host and returns the results, which the hub writes to
# the result topic for the waiting requester. A hardware scan (Ruby
# DiscoveryTopic.scan) is a request with "scan" instead, which openc3-cosmos-app runs
# with openc3.discovery.discovery_scan.
class DiscoveryTopic(Topic):
    @staticmethod
    def request_topic(bridge_name, scope):
        return f"{scope}__DISCOVERY__{bridge_name}"

    @staticmethod
    def result_topic(bridge_name, scope):
        return f"{scope}__DISCOVERY_RESULT__{bridge_name}"

    @staticmethod
    def parse_request(msg_hash):
        """Convert a request topic message into {"id", "discovery", "expires_at"},
        plus "scan" for a hardware scan"""
        request = {
            "id": msg_hash[b"id"].decode(),
            "discovery": json.loads(msg_hash[b"discovery"]),
            "expires_at": float(msg_hash[b"expires_at"]),
        }
        if msg_hash.get(b"scan"):
            request["scan"] = json.loads(msg_hash[b"scan"])
        return request

    @classmethod
    def write_result(cls, bridge_name, request_id, result, scope):
        """Publish a result ({"results": [...]}, {"scan": {...}} or {"error": "..."}) for request_id"""
        Topic.write_topic(
            cls.result_topic(bridge_name, scope),
            {"id": request_id, "result": json.dumps(result)},
            "*",
            100,
        )
