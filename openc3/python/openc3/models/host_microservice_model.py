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

from openc3.models.model import Model


class HostMicroserviceModel(Model):
    """Spawn spec for a COSMOS interface that runs on the host (outside Docker).

    Written by the Ruby InterfaceModel#deploy for bridged interfaces (the BRIDGE
    keyword) and read here by the bridge_microservice, which serves the list to
    openc3-app over the ``api/host_microservices`` ALPN. openc3-app spawns each
    host microservice; it performs raw data transfer only (protocols and target
    definitions stay on the Docker side of COSMOS) and speaks Iroh back to the
    bridge_microservice on the ``stream/<name>`` ALPN.

    Kept separate from MicroserviceModel so the normal COSMOS operator never runs
    these host-only microservices.
    """

    PRIMARY_KEY = "openc3_host_microservices"

    # NOTE: The following class methods are reimplemented so the base Model
    # class methods work with this scoped primary key.
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
    def from_json(cls, json_data: str | dict, scope: str):
        if isinstance(json_data, str):
            json_data = json.loads(json_data)
        if json_data is None:
            raise RuntimeError("json data is nil")
        json_data["scope"] = scope
        return cls(**json_data)

    @classmethod
    def get_model(cls, name: str, scope: str):
        json_data = cls.get(name, scope)
        return cls.from_json(json_data, scope) if json_data else None

    def __init__(
        self,
        name: str,
        scope: str,
        bridge_name: str = None,
        stream: str = None,
        config_params: list | None = None,
        work_dir: str = ".",
        env: dict | None = None,
        options: list | None = None,
        secret_options: list | None = None,
        secrets: list | None = None,
        container: str = None,
        needs_dependencies: bool = False,
        updated_at: int = None,
        plugin: str = None,
    ):
        super().__init__(
            f"{scope}__{self.PRIMARY_KEY}",
            name=name,
            scope=scope,
            updated_at=updated_at,
            plugin=plugin,
        )
        # The bridge (bridge_microservice) this host interface routes through.
        self.bridge_name = bridge_name
        # Iroh ALPN stream name (the interface name) used for the data path.
        self.stream = stream
        # The real interface class and its parameters, e.g. ['serial_interface.py', ...]
        self.config_params = [] if config_params is None else config_params
        self.work_dir = work_dir
        self.env = {} if env is None else env
        self.options = [] if options is None else options
        self.secret_options = [] if secret_options is None else secret_options
        self.secrets = [] if secrets is None else secrets
        self.container = container
        self.needs_dependencies = needs_dependencies

    def as_json(self):
        return {
            "name": self.name,
            "scope": self.scope,
            "bridge_name": self.bridge_name,
            "stream": self.stream,
            "config_params": self.config_params,
            "work_dir": self.work_dir,
            "env": self.env,
            "options": self.options,
            "secret_options": self.secret_options,
            "secrets": self.secrets,
            "container": self.container,
            "needs_dependencies": self.needs_dependencies,
            "plugin": self.plugin,
            "updated_at": self.updated_at,
        }
