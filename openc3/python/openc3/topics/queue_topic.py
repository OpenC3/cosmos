# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.topics.topic import Topic


class QueueTopic(Topic):
    PRIMARY_KEY = "openc3_queue"

    @classmethod
    def write_notification(cls, notification, scope):
        cls.write_topic(f"{scope}__{cls.PRIMARY_KEY}", notification, "*", 1000)
