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

from openc3.environment import OPENC3_SCOPE
from openc3.models.model import Model


class MicroserviceStatusModel(Model):
    PRIMARY_KEY = "openc3_microservice_status"

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name: str, scope: str = OPENC3_SCOPE):
        return super().get(f"{scope}__{MicroserviceStatusModel.PRIMARY_KEY}", name=name)

    @classmethod
    def names(cls, scope: str = OPENC3_SCOPE):
        return super().names(f"{scope}__{MicroserviceStatusModel.PRIMARY_KEY}")

    @classmethod
    def all(cls, scope: str = OPENC3_SCOPE):
        return super().all(f"{scope}__{MicroserviceStatusModel.PRIMARY_KEY}")

    def __init__(
        self,
        name,
        state=None,
        count=0,
        error=None,
        custom=None,
        updated_at=None,
        plugin=None,
        scope=None,
    ):
        super().__init__(
            f"{scope}__{MicroserviceStatusModel.PRIMARY_KEY}",
            name=name,
            updated_at=updated_at,
            plugin=plugin,
            scope=scope,
        )
        self.state = state
        self.count = count
        self.error = error
        self.custom = custom

    def as_json(self):
        json = {
            "name": self.name,
            "state": self.state,
            "count": self.count,
            "plugin": self.plugin,
            "updated_at": self.updated_at,
        }
        if self.error is not None:
            json["error"] = repr(self.error)
        if self.custom is not None:
            json["custom"] = self.custom.as_json()
        return json
