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
import os

from openc3.environment import OPENC3_LOCAL_MODE_PATH


class LocalMode:
    LOCAL_MODE_PATH = OPENC3_LOCAL_MODE_PATH or "/plugins"
    # When updating update local_mode.rb, PluginsTab.vue, plugins.p.spec.ts
    DEFAULT_PLUGINS = [
        "openc3-cosmos-tool-admin",
        "openc3-cosmos-tool-bucketexplorer",
        "openc3-cosmos-tool-cmdsender",
        "openc3-cosmos-tool-cmdqueue",  # Enterprise only
        "openc3-cosmos-tool-cmdhistory",  # Enterprise only
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
        "openc3-cosmos-enterprise-tool-admin",  # Enterprise only
        "openc3-cosmos-tool-autonomic",  # Enterprise only
        "openc3-cosmos-tool-calendar",  # Enterprise only
        "openc3-cosmos-tool-grafana",  # Enterprise only
        "openc3-cosmos-tool-logexplorer",  # Enterprise only
        "openc3-cosmos-tool-notebooks",  # Enterprise only
        "openc3-cosmos-tool-systemhealth",  # Enterprise only
        "openc3-enterprise-tool-base",  # Enterprise only
        "openc3-tool-base",
    ]

    @staticmethod
    def safe_key(key):
        """True if the key has no '.' / '..' segments, no empty segments, no leading
        slash and no backslash. Such a key always resolves under its first segment
        (the scope), both on disk and in the bucket (the bucket normalizes '..')."""
        if not isinstance(key, str) or not key:
            return False
        if key.startswith("/") or "\\" in key or "\0" in key:
            return False
        return all(segment not in ("", ".", "..") for segment in key.split("/"))

    @staticmethod
    def path_within(path, root):
        """True if path resolves to root or somewhere beneath it. Compares against
        root plus a separator so a sibling such as /plugins_old never matches."""
        expanded = os.path.abspath(path)
        root = os.path.abspath(root)
        return expanded == root or expanded.startswith(root + os.sep)

    @classmethod
    def scope_path(cls, scope, relative_path):
        """Local file path for a scope relative path, or None if it would leave the scope directory"""
        if not cls.safe_key(scope) or "/" in scope:
            return None
        scope_root = f"{cls.LOCAL_MODE_PATH}/{scope}"
        full_path = f"{scope_root}/{relative_path}"
        if not cls.path_within(full_path, scope_root):
            return None
        return full_path

    @classmethod
    def put_target_file(cls, path, io_or_string, scope):
        if not cls.safe_key(path) or not path.startswith(f"{scope}/"):
            return
        full_folder_path = f"{cls.LOCAL_MODE_PATH}/{path}"
        os.makedirs(os.path.dirname(full_folder_path), exist_ok=True)
        with open(full_folder_path, "wb") as file:
            if hasattr(io_or_string, "read"):
                data = io_or_string.read()
            else:
                data = io_or_string
            if isinstance(data, str):
                data = data.encode("utf-8")
            file.write(data)

    @classmethod
    def open_local_file(cls, path, scope):
        try:
            full_path = cls.scope_path(scope, f"targets_modified/{path}")
            if full_path and cls.safe_key(path):
                return open(full_path, "rb")
            return None
        except OSError:
            return None

    @classmethod
    def save_tool_config(cls, scope, tool, name, data):
        json_data = json.loads(data)
        config_path = cls.scope_path(scope, f"tool_config/{tool}/{name}.json")
        if config_path and cls.safe_key(f"{tool}/{name}"):
            os.makedirs(os.path.dirname(config_path), exist_ok=True)
            with open(config_path, "w") as file:
                file.write(json.dumps(json_data, indent=2))

    @classmethod
    def delete_tool_config(cls, scope, tool, name):
        config_path = cls.scope_path(scope, f"tool_config/{tool}/{name}.json")
        if config_path and cls.safe_key(f"{tool}/{name}"):
            os.remove(config_path)

    @classmethod
    def save_setting(cls, scope, name, data):
        config_path = cls.scope_path(scope, f"settings/{name}.json")
        if config_path and cls.safe_key(name):
            os.makedirs(os.path.dirname(config_path), exist_ok=True)
            # Anything can be stored as a setting so write it out directly
            with open(config_path, "w") as file:
                file.write(str(data))
