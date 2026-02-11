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

from openc3.models.secret_model import SecretModel
from openc3.utilities.secrets import Secrets


class RedisSecrets(Secrets):
    def keys(self, secret_store=None, scope=None):
        return SecretModel.names(scope=scope)

    def get(self, key, secret_store=None, scope=None):
        data = SecretModel.get(name=key, scope=scope)
        if data is not None:
            return data["value"]
        else:
            return None

    def set(self, key, value, secret_store=None, scope=None):
        SecretModel.set({"name": key, "value": str(value)}, scope=scope)

    def delete(self, key, secret_store=None, scope=None):
        model = SecretModel.get_model(name=key, scope=scope)
        if model:
            model.destroy()
