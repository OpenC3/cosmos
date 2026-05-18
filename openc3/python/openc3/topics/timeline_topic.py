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

from openc3.topics.topic import Topic


class TimelineTopic(Topic):
    PRIMARY_KEY = "__openc3_timelines"

    # Write an activity to the topic.
    #
    # Example payload:
    #   {
    #     "timeline": "foobar",
    #     "kind": "created",
    #     "type": "activity",
    #     "data": {
    #       "name": "foobar",
    #       "start": 1621875570,
    #       "stop": 1621875585,
    #       "kind": "cmd",
    #       "data": {"cmd": "INST ABORT"},
    #       "events": [{"event": "created"}]
    #     }
    #   }
    @classmethod
    def write_activity(cls, activity, scope):
        return Topic.write_topic(f"{scope}{cls.PRIMARY_KEY}", activity, "*", 1000)
