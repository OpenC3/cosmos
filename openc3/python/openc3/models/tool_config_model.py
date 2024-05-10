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

from typing import Any

from openc3.utilities.store import Store
from openc3.utilities.local_mode import LocalMode
from openc3.environment import OPENC3_SCOPE


class ToolConfigModel:
    @classmethod
    def config_tool_names(cls, scope: str = OPENC3_SCOPE):
        cursor, keys = Store.scan(match=f"{scope}__config__*", count=100, _type="HASH")
        result = [key.decode().split("__")[2] for key in keys]
        result.sort()
        return result

    @classmethod
    def list_configs(cls, tool: str, scope: str = OPENC3_SCOPE):
        keys = Store.hkeys(f"{scope}__config__{tool}")
        return [key.decode() for key in keys]

    @classmethod
    def load_config(cls, tool: str, name: str, scope: str = OPENC3_SCOPE):
        return Store.hget(f"{scope}__config__{tool}", name).decode()

    @classmethod
    def save_config(
        cls,
        tool: str,
        name: str,
        data: Any,
        local_mode: bool = True,
        scope: str = OPENC3_SCOPE,
    ):
        Store.hset(f"{scope}__config__{tool}", name, data)
        if local_mode:
            LocalMode.save_tool_config(scope, tool, name, data)

    @classmethod
    def delete_config(cls, tool: str, name: str, local_mode: bool = True, scope: str = OPENC3_SCOPE):
        Store.hdel(f"{scope}__config__{tool}", name)
        if local_mode:
            LocalMode.delete_tool_config(scope, tool, name)
