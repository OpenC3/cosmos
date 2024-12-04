# Copyright 2023 OpenC3, Inc.
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

from pathlib import Path
from typing import Optional

from openc3.environment import OPENC3_SCOPE
from openc3.models.model import Model
from openc3.models.secret_model import SecretModel
from openc3.models.target_model import TargetModel
from openc3.models.microservice_model import MicroserviceModel
from openc3.logs.stream_log_pair import StreamLogPair
from openc3.top_level import get_class_from_module
from openc3.utilities.string import filename_to_module, filename_to_class_name


class InterfaceModel(Model):
    INTERFACES_PRIMARY_KEY = "openc3_interfaces"
    ROUTERS_PRIMARY_KEY = "openc3_routers"

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name: str, scope: str):
        return super().get(f"{scope}__{cls._get_key()}", name)

    @classmethod
    def names(cls, scope: str):
        return super().names(f"{scope}__{cls._get_key()}")

    @classmethod
    def all(cls, scope: str):
        return super().all(f"{scope}__{cls._get_key()}")

    # END NOTE

    @classmethod
    def _get_type(cls):
        """Helper method to return the correct type based on class name"""
        return cls.__name__.split("Model")[0].upper()

    @classmethod
    def _get_key(cls):
        """Helper method to return the correct primary key based on class name"""
        type = cls._get_type()
        match type:
            case "INTERFACE":
                return cls.INTERFACES_PRIMARY_KEY
            case "ROUTER":
                return cls.ROUTERS_PRIMARY_KEY
            case _:
                raise RuntimeError(f"Unknown type {type} from class {cls.__name__}")

    def __init__(
        self,
        name,
        config_params: Optional[list] = None,
        target_names: Optional[list] = None,
        cmd_target_names: Optional[list] = None,
        tlm_target_names: Optional[list] = None,
        connect_on_startup: bool = True,
        auto_reconnect: bool = True,
        reconnect_delay: float = 5.0,
        disable_disconnect: bool = False,
        options: Optional[list] = None,
        secret_options: Optional[list] = None,
        protocols: Optional[list] = None,
        log_stream=None,
        updated_at: Optional[float] = None,
        plugin: Optional[str] = None,
        needs_dependencies: bool = False,
        secrets: Optional[list] = None,
        cmd: str = None,
        work_dir: str = "/openc3/lib/openc3/microservices",
        ports: Optional[list] = None,
        env: Optional[dict] = None,
        container=None,
        prefix=None,
        shard=0,
        scope: str = OPENC3_SCOPE,
    ):
        type = self.__class__._get_type()
        if type == "INTERFACE":
            super().__init__(
                f"{scope}__{InterfaceModel.INTERFACES_PRIMARY_KEY}",
                name=name,
                updated_at=updated_at,
                plugin=plugin,
                scope=scope,
            )
        else:
            super().__init__(
                f"{scope}__{InterfaceModel.ROUTERS_PRIMARY_KEY}",
                name=name,
                updated_at=updated_at,
                plugin=plugin,
                scope=scope,
            )
        self.config_params = [] if config_params is None else config_params
        self.target_names = [] if target_names is None else target_names
        self.cmd_target_names = [] if cmd_target_names is None else cmd_target_names
        self.tlm_target_names = [] if tlm_target_names is None else tlm_target_names
        self.connect_on_startup = connect_on_startup
        self.auto_reconnect = auto_reconnect
        self.reconnect_delay = reconnect_delay
        self.disable_disconnect = disable_disconnect
        self.options = [] if options is None else options
        self.secret_options = [] if secret_options is None else secret_options
        self.protocols = [] if protocols is None else protocols
        self.log_stream = log_stream
        self.needs_dependencies = needs_dependencies
        self.cmd = cmd
        if self.cmd is None:
            microservice_name = f"{self.scope}__{type}__{self.name}"
            if len(self.config_params) == 0 or Path(config_params[0]).suffix == ".py":
                work_dir = work_dir.replace("openc3/lib", "openc3/python")
                self.cmd = [
                    "python",
                    f"{type.lower()}_microservice.py",
                    microservice_name,
                ]
            else:
                raise RuntimeError(f"Unknown file type {config_params[0]}")
        self.work_dir = work_dir
        self.ports = [] if ports is None else ports
        self.env = {} if env is None else env
        self.container = container
        self.prefix = prefix
        self.shard = shard
        if self.shard is None:
            self.shard = 0
        self.secrets = [] if secrets is None else secrets

    # Called by InterfaceMicroservice to instantiate the Interface defined
    # by the model configuration. Must be called after get_model which
    # calls from_json to instantiate the class and populate the attributes.
    def build(self):
        klass = get_class_from_module(
            filename_to_module(self.config_params[0]),
            filename_to_class_name(self.config_params[0]),
        )
        if len(self.config_params) > 1:
            interface_or_router = klass(*self.config_params[1:])
        else:
            interface_or_router = klass()
        interface_or_router.secrets.setup(self.secrets)
        interface_or_router.target_names = self.target_names[:]
        interface_or_router.cmd_target_names = self.cmd_target_names[:]
        interface_or_router.tlm_target_names = self.tlm_target_names[:]
        interface_or_router.connect_on_startup = self.connect_on_startup
        interface_or_router.auto_reconnect = self.auto_reconnect
        interface_or_router.reconnect_delay = self.reconnect_delay
        interface_or_router.disable_disconnect = self.disable_disconnect
        for option in self.options:
            interface_or_router.set_option(option[0], option[1:])
        for option in self.secret_options:
            secret_name = option[1]
            secret_value = interface_or_router.secrets.get(secret_name, scope=self.scope)
            interface_or_router.set_option(option[0], [secret_value])
        for protocol in self.protocols:
            klass = get_class_from_module(
                filename_to_module(protocol[1]),
                filename_to_class_name(protocol[1]),
            )
            interface_or_router.add_protocol(klass, protocol[2:], protocol[0].upper())
        if self.log_stream:
            interface_or_router.stream_log_pair = StreamLogPair(interface_or_router.name, self.log_stream)
            interface_or_router.start_raw_logging
        return interface_or_router

    def as_json(self):
        return {
            "name": self.name,
            "config_params": self.config_params,
            "target_names": self.target_names,
            "cmd_target_names": self.cmd_target_names,
            "tlm_target_names": self.tlm_target_names,
            "connect_on_startup": self.connect_on_startup,
            "auto_reconnect": self.auto_reconnect,
            "reconnect_delay": self.reconnect_delay,
            "disable_disconnect": self.disable_disconnect,
            "options": self.options,
            "secret_options": self.secret_options,
            "protocols": self.protocols,
            "log_stream": self.log_stream,
            "plugin": self.plugin,
            "needs_dependencies": self.needs_dependencies,
            "secrets": (self.secrets.as_json() if isinstance(self.secrets, SecretModel) else self.secrets),
            "cmd": self.cmd,
            "work_dir": self.work_dir,
            "ports": self.ports,
            "env": self.env,
            "container": self.container,
            "prefix": self.prefix,
            "shard": self.shard,
            "updated_at": self.updated_at,
        }

    def ensure_target_exists(self, target_name):
        target = TargetModel.get(name=target_name, scope=self.scope)
        if not target:
            raise RuntimeError(f"Target {target_name} does not exist")
        return target

    def unmap_target(self, target_name, cmd_only=False, tlm_only=False):
        if cmd_only and tlm_only:
            cmd_only = False
            tlm_only = False
        target_name = str(target_name).upper()

        # Remove from this interface
        if cmd_only:
            self.cmd_target_names.remove(target_name)
            if target_name not in self.tlm_target_names:
                self.target_names.remove(target_name)
        elif tlm_only:
            self.tlm_target_names.remove(target_name)
            if target_name not in self.cmd_target_names:
                self.target_names.remove(target_name)
        else:
            self.cmd_target_names.remove(target_name)
            self.tlm_target_names.remove(target_name)
            self.target_names.remove(target_name)
        self.update()

        # Respawn the microservice
        type = self.__class__.__name__.split("Model")[0].upper()
        microservice_name = f"{self.scope}__{type}__{self.name}"
        microservice = MicroserviceModel.get_model(name=microservice_name, scope=self.scope)
        if target_name not in self.target_names:
            microservice.target_names.remove(target_name)
        microservice.update()

    def map_target(self, target_name, cmd_only=False, tlm_only=False, unmap_old=True):
        if cmd_only and tlm_only:
            cmd_only = False
            tlm_only = False
        target_name = str(target_name).upper()
        self.ensure_target_exists(target_name)

        if unmap_old:
            # Remove from old interface
            all_interfaces = InterfaceModel.all(scope=self.scope)
            old_interface = None
            for _, old_interface_details in all_interfaces.items():
                if target_name in old_interface_details["target_names"]:
                    old_interface = InterfaceModel.from_json(old_interface_details, scope=self.scope)
                    if old_interface:
                        old_interface.unmap_target(target_name, cmd_only=cmd_only, tlm_only=tlm_only)

        # Add to this interface
        if target_name not in self.target_names:
            self.target_names.append(target_name)
        if target_name not in self.cmd_target_names or tlm_only:
            self.cmd_target_names.append(target_name)
        if target_name not in self.tlm_target_names or cmd_only:
            self.tlm_target_names.append(target_name)
        self.update()

        # Respawn the microservice
        type = self.__class__.__name__.split("Model")[0].upper()
        microservice_name = f"{self.scope}__{type}__{self.name}"
        microservice = MicroserviceModel.get_model(name=microservice_name, scope=self.scope)
        if target_name not in microservice.target_names:
            microservice.target_names.append(target_name)
        microservice.update()
