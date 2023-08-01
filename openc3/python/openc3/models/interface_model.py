#!/usr/bin/env python3

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

from openc3.models.model import Model


class InterfaceModel(Model):
    INTERFACES_PRIMARY_KEY = "openc3_interfaces"
    ROUTERS_PRIMARY_KEY = "openc3_routers"

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name, scope):
        return super().__init__(f"{scope}__{cls._get_key()}", name)

    @classmethod
    def names(cls, scope):
        return super(f"{scope}__{cls._get_key()}")

    @classmethod
    def all(cls, scope):
        return super(f"{scope}__{cls._get_key()}")

    # END NOTE

    @classmethod
    def _get_type(cls):
        """Helper method to return the correct type based on class name"""
        return cls.__name__.split("Model")[0].upper()

    @classmethod
    def _get_key(cls):
        """Helper method to return the correct primary key based on class name"""
        type = cls._get_type()
        match type:
            case "INTERFACE":
                return cls.INTERFACES_PRIMARY_KEY
            case "ROUTER":
                return cls.ROUTERS_PRIMARY_KEY
            case _:
                raise RuntimeError(f"Unknown type {type} from class {cls.__name__}")
