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

from openc3.environment import OPENC3_SCOPE
from openc3.models.model import Model
from openc3.utilities.store import EphemeralStore


class MetricModel(Model):
    PRIMARY_KEY = "__openc3__metric"

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name: str, scope: str):
        return super().get(f"{scope}{MetricModel.PRIMARY_KEY}", name=name)

    @classmethod
    def names(cls, scope: str):
        return super().names(f"{scope}{MetricModel.PRIMARY_KEY}")

    @classmethod
    def all(cls, scope: str):
        return super().all(f"{scope}{MetricModel.PRIMARY_KEY}")

    # Sets (updates) the redis hash of this model
    @classmethod
    def set(cls, json: dict, scope: str = OPENC3_SCOPE, queued: bool = True):
        json["scope"] = scope
        cls(**json).create(force=True, queued=queued)

    @classmethod
    def destroy(cls, scope: str, name: str):
        EphemeralStore.hdel(f"{scope}{MetricModel.PRIMARY_KEY}", name)

    def __init__(self, name: str, values: dict = None, scope: str = OPENC3_SCOPE):
        values = {} if values is None else values
        super().__init__(f"{scope}{MetricModel.PRIMARY_KEY}", name=name, scope=scope)
        self.values = values

    def as_json(self):
        return {"name": self.name, "updated_at": self.updated_at, "values": self.values}
