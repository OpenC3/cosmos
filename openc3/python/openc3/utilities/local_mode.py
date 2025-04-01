# Copyright 2024 OpenC3, Inc.
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

import os
import json
from openc3.environment import OPENC3_LOCAL_MODE_PATH


class LocalMode:
    LOCAL_MODE_PATH = OPENC3_LOCAL_MODE_PATH or "/plugins"
    # When updating update local_mode.rb, PluginsTab.vue, plugins.spec.ts
    DEFAULT_PLUGINS = [
        "openc3-cosmos-tool-admin",
        "openc3-cosmos-tool-bucketexplorer",
        "openc3-cosmos-tool-cmdsender",
        "openc3-cosmos-tool-cmdhistory",
        "openc3-cosmos-tool-cmdtlmserver",
        "openc3-cosmos-tool-dataextractor",
        "openc3-cosmos-tool-dataviewer",
        "openc3-cosmos-tool-docs",
        "openc3-cosmos-tool-handbooks",
        "openc3-cosmos-tool-iframe",
        "openc3-cosmos-tool-limitsmonitor",
        "openc3-cosmos-tool-packetviewer",
        "openc3-cosmos-tool-scriptrunner",
        "openc3-cosmos-tool-tablemanager",
        "openc3-cosmos-tool-tlmgrapher",
        "openc3-cosmos-tool-tlmviewer",
        "openc3-cosmos-enterprise-tool-admin",
        "openc3-cosmos-tool-autonomic",
        "openc3-cosmos-tool-calendar",
        "openc3-cosmos-tool-grafana",
        "openc3-enterprise-tool-base",
        "openc3-tool-base",
    ]

    @classmethod
    def put_target_file(cls, path, io_or_string, scope):
        full_folder_path = f"{cls.LOCAL_MODE_PATH}/{path}"
        if not os.path.normpath(full_folder_path).startswith(cls.LOCAL_MODE_PATH):
            return
        os.makedirs(os.path.dirname(full_folder_path), exist_ok=True)
        flags = "w"
        if isinstance(io_or_string, (bytes, bytearray)):
            flags += "b"
        with open(full_folder_path, flags) as file:
            if hasattr(io_or_string, "read"):
                data = io_or_string.read()
            else:  # str or bytes
                data = io_or_string
            file.write(data)

    @classmethod
    def open_local_file(cls, path, scope):
        try:
            full_path = f"{cls.LOCAL_MODE_PATH}/{scope}/targets_modified/{path}"
            if os.path.normpath(full_path).startswith(cls.LOCAL_MODE_PATH):
                return open(full_path, "rb")
            return None
        except OSError:
            return None

    @classmethod
    def save_tool_config(cls, scope, tool, name, data):
        json_data = json.loads(data)
        config_path = f"{cls.LOCAL_MODE_PATH}/{scope}/tool_config/{tool}/{name}.json"
        if os.path.normpath(config_path).startswith(cls.LOCAL_MODE_PATH):
            os.makedirs(os.path.dirname(config_path), exist_ok=True)
            with open(config_path, "w") as file:
                file.write(json.dumps(json_data, indent=2))

    @classmethod
    def delete_tool_config(cls, scope, tool, name):
        config_path = f"{cls.LOCAL_MODE_PATH}/{scope}/tool_config/{tool}/{name}.json"
        if os.path.normpath(config_path).startswith(cls.LOCAL_MODE_PATH):
            os.remove(config_path)

    @classmethod
    def save_setting(cls, scope, name, data):
        config_path = f"{cls.LOCAL_MODE_PATH}/{scope}/settings/{name}.json"
        if os.path.normpath(config_path).startswith(cls.LOCAL_MODE_PATH):
            os.makedirs(os.path.dirname(config_path), exist_ok=True)
            # Anything can be stored as a setting so write it out directly
            with open(config_path, "w") as file:
                file.write(str(data))
