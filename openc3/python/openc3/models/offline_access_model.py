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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.models.model import Model

# Note: This model is locked to the DEFAULT scope
class OfflineAccessModel(Model):
    PRIMARY_KEY = "DEFAULT__openc3__offline_access"

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name: str, scope: str):
        return super().get(OfflineAccessModel.PRIMARY_KEY, name=name)

    @classmethod
    def names(cls, scope: str):
        return super().names(OfflineAccessModel.PRIMARY_KEY)

    @classmethod
    def all(cls, scope: str):
        return super().all(OfflineAccessModel.PRIMARY_KEY)

    def __init__(
        self, name: str, offline_access_token: str = None, updated_at: float = None, scope: str = 'DEFAULT'
    ):
        super().__init__(OfflineAccessModel.PRIMARY_KEY, name=name, updated_at=updated_at, scope='DEFAULT')
        self.offline_access_token = offline_access_token

    # @return [Hash] JSON encoding of this model
    def as_json(self):
        return {
            "name": self.name,
            "updated_at": self.updated_at,
            "offline_access_token": self.offline_access_token,
            "scope": self.scope,
        }
