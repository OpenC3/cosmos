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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os
from openc3.top_level import get_class_from_module
from openc3.utilities.string import filename_to_class_name

if os.getenv("OPENC3_SECRET_BACKEND") is None:
    os.environ["OPENC3_SECRET_BACKEND"] = "redis"


class Secrets:
    def __init__(self):
        self.local_secrets = {}

    @classmethod
    def getClient(cls):
        if os.getenv("OPENC3_SECRET_BACKEND") is None:
            raise RuntimeError("OPENC3_SECRET_BACKEND environment variable is required")
        secrets_file = os.getenv("OPENC3_SECRET_BACKEND").lower() + "_secrets"
        klass = get_class_from_module(
            f"openc3.utilities.{secrets_file}",
            filename_to_class_name(secrets_file),
        )
        return klass()

    def keys(self, secret_store=None, scope=None):
        raise RuntimeError(f"{self.__class__.__name__} has not implemented method 'keys'")

    def get(self, key, secret_store=None, scope=None):
        return self.local_secrets[key]

    def set(self, key, value, secret_store=None, scope=None):
        raise RuntimeError(f"{self.__class__.__name__} has not implemented method 'set'")

    def delete(self, key, secret_store=None, scope=None):
        raise RuntimeError(f"{self.__class__.__name__} has not implemented method 'delete'")

    def setup(self, secrets):
        for type, key, data, secret_store in secrets:
            match type:
                case "ENV":
                    self.local_secrets[key] = os.environ.get(data)
                case "FILE":
                    with open(data) as file:
                        self.local_secrets[key] = file.read()
                case _:
                    raise RuntimeError(f"Unknown secret type: {type}")
