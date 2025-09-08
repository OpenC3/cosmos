# Copyright 2025 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
import threading
import time
from typing import Optional

from openc3.models.model import Model
from openc3.models.microservice_model import MicroserviceModel
from openc3.topics.queue_topic import QueueTopic
from openc3.utilities.store import Store


class QueueError(Exception):
    pass


class QueueModel(Model):
    PRIMARY_KEY = "openc3__queue"

    _class_mutex = threading.Lock()

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name: str, scope: str):
        return super().get(f"{scope}__{cls.PRIMARY_KEY}", name)

    @classmethod
    def names(cls, scope: str):
        return super().names(f"{scope}__{cls.PRIMARY_KEY}")

    @classmethod
    def all(cls, scope: str):
        return super().all(f"{scope}__{cls.PRIMARY_KEY}")

    # END NOTE

    # The queue_command is really the only method need in the Python implementation
    # because it is being called by the cmd_api.py _cmd_implementation.
    # However we need a lot of methods to enable cls.get_model and model.notify
    @classmethod
    def queue_command(cls, name: str, command: str, username: str, scope: str):
        model = cls.get_model(name=name, scope=scope)
        if not model:
            raise QueueError(f"Queue '{name}' not found in scope '{scope}'")

        if model.state != "DISABLE":
            result = Store.zrevrange(f"{scope}:{name}", 0, 0, withscores=True)
            if not result:
                index = 1.0
            else:
                index = float(result[0][1]) + 1

            command_data = {"username": username, "value": command, "timestamp": time.time_ns()}
            Store.zadd(f"{scope}:{name}", {json.dumps(command_data): index})
            model.notify(kind="command")
        else:
            raise QueueError(f"Queue '{name}' is disabled. Command '{command}' not queued.")

    def __init__(self, name: str, scope: str, state: str = "HOLD", updated_at: Optional[float] = None):
        super().__init__(f"{scope}__{self.PRIMARY_KEY}", name=name, updated_at=updated_at, scope=scope)
        self.microservice_name = f"{scope}__QUEUE__{name}"
        if state in ["HOLD", "RELEASE", "DISABLE"]:
            self.state = state
        else:
            self.state = "HOLD"

    def as_json(self):
        return {"name": self.name, "scope": self.scope, "state": self.state, "updated_at": self.updated_at}

    def notify(self, kind: str):
        notification = {
            "kind": kind,
            "data": json.dumps(self.as_json(), allow_nan=True),
        }
        QueueTopic.write_notification(notification, scope=self.scope)
