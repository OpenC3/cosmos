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
        self.state = state
        self._instance_mutex = threading.Lock()

    def create(self, update: bool = False, force: bool = False, queued: bool = False):
        super().create(update=update, force=force, queued=queued)
        if update:
            self.notify(kind="updated")
        else:
            self.notify(kind="created")

    def as_json(self):
        return {"name": self.name, "scope": self.scope, "state": self.state, "updated_at": self.updated_at}

    def notify(self, kind: str):
        notification = {
            "kind": kind,
            "data": json.dumps(self.as_json(), allow_nan=True),
        }
        QueueTopic.write_notification(notification, scope=self.scope)

    def insert(self, index: Optional[float], command_data: dict):
        if index is None:
            result = Store.zrevrange(f"{self.scope}:{self.name}", 0, 0, withscores=True)
            if not result:
                index = 1.0
            else:
                index = float(result[0][1]) + 1

        Store.zadd(f"{self.scope}:{self.name}", index, json.dumps(command_data))
        self.notify(kind="command")

    def remove(self, index: float):
        num_removed = Store.zremrangebyscore(f"{self.scope}:{self.name}", index, index)
        self.notify(kind="command")
        return num_removed == 1

    def list(self):
        results = Store.zrange(f"{self.scope}:{self.name}", 0, -1, withscores=True)
        items = []
        for item in results:
            result = json.loads(item[0])
            result["index"] = float(item[1])
            items.append(result)
        return items

    def create_microservice(self, topics: list):
        microservice = MicroserviceModel(
            name=self.microservice_name,
            folder_name=None,
            cmd=["ruby", "queue_microservice.rb", self.microservice_name],
            work_dir="/openc3/lib/openc3/microservices",
            options=[],
            topics=topics,
            target_names=[],
            plugin=None,
            scope=self.scope,
        )
        microservice.create()

    def deploy(self, gem_path: str, variables: str):
        topics = [f"{self.scope}__{QueueTopic.PRIMARY_KEY}"]
        if not MicroserviceModel.get_model(name=self.microservice_name, scope=self.scope):
            self.create_microservice(topics=topics)

    def undeploy(self):
        model = MicroserviceModel.get_model(name=self.microservice_name, scope=self.scope)
        if model:
            notification = {
                "kind": "undeployed",
                "data": json.dumps(
                    {
                        "name": self.microservice_name,
                        "updated_at": time.time_ns(),
                    }
                ),
            }
            QueueTopic.write_notification(notification, scope=self.scope)
            model.destroy()

    def destroy(self):
        Store.zremrangebyrank(f"{self.scope}:{self.name}", 0, -1)
        super().destroy()
