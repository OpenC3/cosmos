#!/usr/bin/env python3

# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.models.model import Model
from openc3.environment import OPENC3_SCOPE


class StashModel(Model):
    PRIMARY_KEY = "openc3__stash"

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name, scope=OPENC3_SCOPE):
        super().get(f"{scope}__{StashModel.PRIMARY_KEY}", name=name)

    @classmethod
    def names(cls, scope=OPENC3_SCOPE):
        super().names(f"{scope}__{StashModel.PRIMARY_KEY}")

    @classmethod
    def all(cls, scope=OPENC3_SCOPE):
        super().all(f"{scope}__{StashModel.PRIMARY_KEY}")

    # END NOTE

    def __init__(self, name, value, scope=OPENC3_SCOPE):
        super.__init__(f"{scope}__{StashModel.PRIMARY_KEY}", name=name, scope=scope)
        self.value = value

    # self.return [Hash] JSON encoding of this model
    def as_json(self):
        return {
            "name": self.name,
            "value": self.value.as_json(),
        }
