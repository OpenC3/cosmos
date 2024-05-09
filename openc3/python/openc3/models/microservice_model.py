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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from typing import Optional

from openc3.environment import OPENC3_SCOPE
from openc3.models.model import Model

# require 'openc3/models/metric_model'
from openc3.utilities.bucket import Bucket
from openc3.config.config_parser import ConfigParser


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
        updated_at=None,
        plugin=None,
        needs_dependencies=False,
        secrets: Optional[list] = None,
        prefix=None,
        disable_erb=None,
        scope: str = OPENC3_SCOPE,
    ):
        parts = name.split("__")
        if len(parts) != 3:
            raise RuntimeError(f"name '{name}' must be formatted as SCOPE__TYPE__NAME")
        if parts[0] != scope:
            raise RuntimeError(
                f"name '{name}' scope '{parts[0]}' doesn't match scope parameter '{scope}'"
            )

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
        }

    def handle_keyword(self, parser, keyword, parameters):
        match keyword:
            case "ENV":
                parser.verify_num_parameters(2, 2, f"{keyword} <Key> <Value>")
                self.env[parameters[0]] = parameters[1]
            case "WORK_DIR":
                parser.verify_num_parameters(1, 1, f"{keyword} <Dir>")
                self.work_dir = parameters[0]
            case "PORT":
                usage = "PORT <Number> <Protocol (Optional)"
                parser.verify_num_parameters(1, 2, usage)
                try:
                    self.ports.append([int(parameters[0])])
                except ValueError:
                    raise ConfigParser.Error(
                        parser, f"Port must be an integer: {parameters[0]}", usage
                    )
                if len(parameters) > 1:
                    protocol = ConfigParser.handle_none(parameters[1])
                    # Per https://kubernetes.io/docs/concepts/services-networking/service/#protocol-support
                    if protocol.upper() in ["TCP", "UDP", "SCTP"]:
                        self.ports[-1].append(protocol.upper())
                    else:
                        raise ConfigParser.Error(
                            parser, f"Unknown port protocol: {parameters[1]}", usage
                        )
                else:
                    self.ports[-1].append("TCP")
            case "TOPIC":
                parser.verify_num_parameters(1, 1, f"{keyword} <Topic Name>")
                self.topics.append(parameters[0])
            case "TARGET_NAME":
                parser.verify_num_parameters(1, 1, f"{keyword} <Target Name>")
                self.target_names.append(parameters[0])
            case "CMD":
                parser.verify_num_parameters(1, None, f"{keyword} <Args>")
                self.cmd = parameters[:]
            case "OPTION":
                parser.verify_num_parameters(
                    2, None, f"{keyword} <Option Name> <Option Values>"
                )
                self.options.append(parameters[:])
            case "CONTAINER":
                parser.verify_num_parameters(1, 1, f"{keyword} <Container Image Name>")
                self.container = parameters[0]
            case "SECRET":
                parser.verify_num_parameters(
                    3,
                    4,
                    f"{keyword} <Secret Type: ENV or FILE> <Secret Name> <Environment Variable Name or File Path> <Secret Store Name (Optional)>",
                )
                if ConfigParser.handle_none(parameters[3]):
                    self.secrets.append(parameters[:])
                else:
                    self.secrets.append(parameters[0:3])
            case "ROUTE_PREFIX":
                parser.verify_num_parameters(1, 1, f"{keyword} <Route Prefix>")
                self.prefix = parameters[0]
            case "DISABLE_ERB":
                # 0 to unlimited parameters
                if self.disable_erb is None:
                    self.disable_erb = []
                if parameters:
                    self.disable_erb.extend(parameters)
            case _:
                raise ConfigParser.Error(
                    parser,
                    f"Unknown keyword and parameters for Microservice: {keyword} {' '.join(parameters)}",
                )
        return None
