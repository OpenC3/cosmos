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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1953

from typing import Optional

from openc3.environment import OPENC3_SCOPE
from openc3.models.model import Model

# require 'openc3/models/metric_model'
from openc3.utilities.bucket import Bucket


class MicroserviceModel(Model):
    PRIMARY_KEY = "openc3_microservices"

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name, scope: Optional[str] = None):
        return super().get(MicroserviceModel.PRIMARY_KEY, name)

    @classmethod
    def names(cls, scope: Optional[str] = None):
        scoped = []
        unscoped = super().names(MicroserviceModel.PRIMARY_KEY)
        for name in unscoped:
            if scope is None or name.split("__")[0] == scope:
                scoped.append(name)
        return scoped

    @classmethod
    def all(cls, scope: Optional[str] = None):
        scoped = {}
        unscoped = super().all(MicroserviceModel.PRIMARY_KEY)
        for name, json in unscoped.items():
            if scope is None or name.split("__")[0] == scope:
                scoped[name] = json
        return scoped

    # Create a microservice model to be deployed to bucket storage
    def __init__(
        self,
        name: str,
        folder_name: str = None,
        cmd: Optional[list] = None,
        work_dir: str = ".",
        ports: Optional[list] = None,
        env: Optional[dict] = None,
        topics: Optional[list] = None,
        target_names: Optional[list] = None,
        options: Optional[list] = None,
        parent=None,
        container=None,
        updated_at: Optional[float] = None,
        plugin=None,
        needs_dependencies=False,
        secrets: Optional[list] = None,
        prefix=None,
        disable_erb=None,
        ignore_changes=None,
        shard=0,
        enabled: bool = True,
        scope: str = OPENC3_SCOPE,
    ):
        parts = name.split("__")
        if len(parts) != 3:
            raise RuntimeError(f"name '{name}' must be formatted as SCOPE__TYPE__NAME")
        if parts[0] != scope:
            raise RuntimeError(f"name '{name}' scope '{parts[0]}' doesn't match scope parameter '{scope}'")

        cmd = [] if cmd is None else cmd
        ports = [] if ports is None else ports
        env = {} if env is None else env
        topics = [] if topics is None else topics
        target_names = [] if target_names is None else target_names
        options = [] if options is None else options
        secrets = [] if secrets is None else secrets

        super().__init__(
            MicroserviceModel.PRIMARY_KEY,
            name=name,
            updated_at=updated_at,
            plugin=plugin,
            scope=scope,
        )
        self.folder_name = folder_name
        self.cmd = cmd
        self.work_dir = work_dir
        self.ports = ports
        self.env = env
        self.topics = topics
        self.target_names = target_names
        self.options = options
        self.parent = parent
        self.container = container
        self.needs_dependencies = needs_dependencies
        self.secrets = secrets
        self.prefix = prefix
        self.disable_erb = disable_erb
        self.ignore_changes = ignore_changes
        self.shard = shard
        if self.shard is None:
            self.shard = 0
        self.enabled = enabled
        if self.enabled is None:
            self.enabled = True
        self.bucket = Bucket.getClient()

    def as_json(self):
        return {
            "name": self.name,
            "folder_name": self.folder_name,
            "cmd": self.cmd,
            "work_dir": self.work_dir,
            "ports": self.ports,
            "env": self.env,
            "topics": self.topics,
            "target_names": self.target_names,
            "options": self.options,
            "parent": self.parent,
            "container": self.container,
            "updated_at": self.updated_at,
            "plugin": self.plugin,
            "needs_dependencies": self.needs_dependencies,
            "secrets": self.secrets,  # .as_json(),
            "prefix": self.prefix,
            "disable_erb": self.disable_erb,
            "ignore_changes": self.ignore_changes,
            "shard": self.shard,
            "enabled": self.enabled,
        }
