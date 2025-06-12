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

import json
from openc3.models.model import Model
from openc3.utilities.store import Store

class ScriptEngineModel(Model):
    PRIMARY_KEY = 'openc3_script_engines'

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name, scope = None):
        return super().get(cls.PRIMARY_KEY, name = name)

    @classmethod
    def names(cls, scope = None):
        array = []
        for name, _script_engine in cls.all(scope = scope).items():
            array.append(name)
        return array

    @classmethod
    def all(cls, scope = None):
        tools = Store.hgetall(cls.PRIMARY_KEY)
        for key, value in tools.items():
            tools[key] = json.loads(value)
        return tools

    def __init__(
        self,
        name,
        updated_at = None,
        plugin = None,
        filename = None,
        scope = None,
    ):
        super().__init__(self.PRIMARY_KEY, name = name, plugin = plugin, updated_at = updated_at, scope = scope)
        self.filename = filename

    def as_json(self):
        return {
          'name': self.name,
          'updated_at': self.updated_at,
          'plugin': self.plugin,
          'filename': self.filename
        }
