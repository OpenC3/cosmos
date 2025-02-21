# Copyright 2024 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
from openc3.models.model import Model


class ScopeModel(Model):
    PRIMARY_KEY = "openc3_scopes"

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name: str, scope: str = None):
        return super().get(cls.PRIMARY_KEY, name=name)

    @classmethod
    def names(cls, scope: str = None):
        return super().names(cls.PRIMARY_KEY)

    @classmethod
    def all(cls, scope: str = None):
        return super().all(cls.PRIMARY_KEY)

    # END NOTE

    @classmethod
    def from_json(cls, json_data: str | dict):
        """
        Return:
            [Model] Model generated from the passed JSON
        """
        if isinstance(json_data, str):
            json_data = json.loads(json_data)
        if json_data is None:
            raise RuntimeError("json data is nil")
        return cls(**json_data)

    @classmethod
    def get_model(cls, name: str):
        """Calls self.get_model and then from_json to turn the Hash configuration into a Ruby Model object.
        Return:
            [Object|nil] Model object or nil if name not found under primary_key
        """
        json_data = cls.get(name)
        return cls.from_json(json_data) if json_data else None

    def __init__(
        self,
        name: str,
        text_log_cycle_time: int = 600,
        text_log_cycle_size: int = 50_000_000,
        text_log_retain_time: int = None,
        tool_log_retain_time: int = None,
        cleanup_poll_time: int = 900,
        command_authority: bool = False,
        critical_commanding: str = "OFF",
        shard: int = 0,
        updated_at: int = None,
    ):
        super().__init__(
            self.PRIMARY_KEY,
            name=name,
            updated_at=updated_at,
            # This sets the @scope variable which is sort of redundant for the ScopeModel
            # (since its the same as @name) but every model has a @scope
            scope=name,
        )
        self.text_log_cycle_time = text_log_cycle_time
        self.text_log_cycle_size = text_log_cycle_size
        self.text_log_retain_time = text_log_retain_time
        self.tool_log_retain_time = tool_log_retain_time
        self.cleanup_poll_time = cleanup_poll_time
        self.command_authority = command_authority
        self.critical_commanding = str(critical_commanding).upper()
        if len(self.critical_commanding) == 0:
            self.critical_commanding = "OFF"
        if self.critical_commanding not in ["OFF", "NORMAL", "ALL"]:
            raise RuntimeError(f"Invalid value for critical_commanding: {self.critical_commanding}")
        self.shard = shard
        if self.shard is None:
            self.shard = 0
        self.children = []

    # self.return [Hash] JSON encoding of this model
    def as_json(self):
        return {
            "name": self.name,
            "updated_at": self.updated_at,
            "text_log_cycle_time": self.text_log_cycle_time,
            "text_log_cycle_size": self.text_log_cycle_size,
            "text_log_retain_time": self.text_log_retain_time,
            "tool_log_retain_time": self.tool_log_retain_time,
            "cleanup_poll_time": self.cleanup_poll_time,
            "command_authority": self.command_authority,
            "critical_commanding": self.critical_commanding,
            "shard": self.shard,
        }
