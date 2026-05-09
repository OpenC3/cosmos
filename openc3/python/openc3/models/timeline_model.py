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
import re
import secrets

from openc3.config.config_parser import ConfigParser
from openc3.models.microservice_model import MicroserviceModel
from openc3.models.model import Model
from openc3.topics.timeline_topic import TimelineTopic
from openc3.utilities.store import Store


class TimelineError(RuntimeError):
    pass


class TimelineInputError(TimelineError):
    pass


class TimelineModel(Model):
    # MUST be equal to ActivityModel.PRIMARY_KEY without leading __
    PRIMARY_KEY = "openc3_timelines"
    KEY = "__TIMELINE__"

    @classmethod
    def get(cls, name, scope):
        json_data = super().get(cls.PRIMARY_KEY, name=f"{scope}{cls.KEY}{name}")
        if json_data is None:
            return None
        return cls.from_json(json_data, name=name, scope=scope)

    @classmethod
    def all(cls):
        return super().all(cls.PRIMARY_KEY)

    @classmethod
    def names(cls):
        return super().names(cls.PRIMARY_KEY)

    # Remove the sorted set.
    @classmethod
    def delete(cls, name, scope, force=False):
        key = f"{scope}__{cls.PRIMARY_KEY}__{name}"
        z = Store.zcard(key)
        if not force and z > 0:
            raise TimelineError("timeline contains activities, must force remove")

        Store.delete(key)
        Store.hdel(cls.PRIMARY_KEY, f"{scope}{cls.KEY}{name}")
        return name

    @classmethod
    def from_json(cls, json_data, name, scope):
        if isinstance(json_data, (str, bytes)):
            json_data = json.loads(json_data)
        if json_data is None:
            raise RuntimeError("json data is nil")
        # Strip name/scope so caller-supplied values win
        json_data = dict(json_data)
        json_data.pop("name", None)
        json_data.pop("scope", None)
        return cls(name=name, scope=scope, **json_data)

    def __init__(self, name, scope, updated_at=None, color=None, shard=0, execute=True):
        if name is None or scope is None:
            raise TimelineInputError("name or scope must not be nil")

        super().__init__(self.PRIMARY_KEY, name=f"{scope}{self.KEY}{name}", scope=scope)
        self.updated_at = updated_at
        self.timeline_name = name
        self.shard = int(shard) if shard is not None else 0
        self.color = color
        self.execute = execute

    @property
    def color(self):
        return self._color

    @color.setter
    def color(self, value):
        if value is None:
            # secrets is overkill for a UI color but satisfies static analyzers
            # that flag random.randint as a weak PRNG.
            value = f"#{secrets.randbelow(0x1000000):06x}"
        if not re.search(r"#?([0-9a-fA-F]{6})", value):
            raise TimelineInputError("invalid color, must be in hex format, e.g. #FF0000")
        if not value.startswith("#"):
            value = f"#{value}"
        self._color = value

    @property
    def execute(self):
        return self._execute

    @execute.setter
    def execute(self, value):
        self._execute = ConfigParser.handle_true_false(value)

    def as_json(self):
        return {
            "name": self.timeline_name,
            "color": self._color,
            "execute": self._execute,
            "shard": self.shard,
            "scope": self.scope,
            "updated_at": self.updated_at,
        }

    # Update the redis stream / timeline topic that something has changed.
    def notify(self, kind):
        notification = {
            "data": json.dumps(self.as_json()),
            "kind": kind,
            "type": "timeline",
            "timeline": self.timeline_name,
        }
        try:
            TimelineTopic.write_activity(notification, scope=self.scope)
        except Exception as e:
            raise TimelineInputError(f"Failed to write to stream: {notification}, {e}") from e

    def deploy(self, gem_path=None, variables=None):
        del gem_path, variables  # unused — kept for base-class compatibility
        topics = [f"{self.scope}__{self.PRIMARY_KEY}"]
        microservice = MicroserviceModel(
            name=self.name,
            folder_name=None,
            cmd=["ruby", "timeline_microservice.rb", self.name],
            work_dir="/openc3-enterprise/lib/openc3-enterprise/microservices",
            options=[],
            topics=topics,
            target_names=[],
            plugin=None,
            shard=self.shard,
            scope=self.scope,
        )
        microservice.create()
        self.notify(kind="created")

    def undeploy(self):
        model = MicroserviceModel.get_model(name=self.name, scope=self.scope)
        if model:
            model.destroy()
            self.notify(kind="deleted")
