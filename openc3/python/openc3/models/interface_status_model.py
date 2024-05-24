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


# Stores the status about an interface. This class also implements logic
# to handle status for a router since the functionality is identical
# (only difference is the Redis key used).
class InterfaceStatusModel(Model):
    INTERFACES_PRIMARY_KEY = "openc3_interface_status"
    ROUTERS_PRIMARY_KEY = "openc3_router_status"

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name: str, scope: str):
        return super().get(f"{scope}__{cls._get_key()}", name=name)

    @classmethod
    def names(cls, scope: str):
        return super().names(f"{scope}__{cls._get_key()}")

    @classmethod
    def all(cls, scope: str):
        return super().all(f"{scope}__{cls._get_key()}")

    # END NOTE

    # Helper method to return the correct type based on class name
    @classmethod
    def _get_type(cls):
        return cls.__name__.split("Model")[0].upper()

    # Helper method to return the correct primary key based on class name
    @classmethod
    def _get_key(cls):
        type_ = cls._get_type()
        match type_:
            case "INTERFACESTATUS":
                return InterfaceStatusModel.INTERFACES_PRIMARY_KEY
            case "ROUTERSTATUS":
                return InterfaceStatusModel.ROUTERS_PRIMARY_KEY
            case _:
                raise RuntimeError(f"Unknown type {type_} from class {cls.__name__}")

    def __init__(
        self,
        name,
        state,
        clients=0,
        txsize=0,
        rxsize=0,
        txbytes=0,
        rxbytes=0,
        txcnt=0,
        rxcnt=0,
        updated_at=None,
        plugin=None,
        scope=None,
    ):
        if self.__class__._get_type() == "INTERFACESTATUS":
            super().__init__(
                f"{scope}__{InterfaceStatusModel.INTERFACES_PRIMARY_KEY}",
                name=name,
                updated_at=updated_at,
                plugin=plugin,
                scope=scope,
            )
        else:
            super().__init__(
                f"{scope}__{InterfaceStatusModel.ROUTERS_PRIMARY_KEY}",
                name=name,
                updated_at=updated_at,
                plugin=plugin,
                scope=scope,
            )
        self.state = state
        self.clients = clients
        self.txsize = txsize
        self.rxsize = rxsize
        self.txbytes = txbytes
        self.rxbytes = rxbytes
        self.txcnt = txcnt
        self.rxcnt = rxcnt

    def as_json(self):
        return {
            "name": self.name,
            "state": self.state,
            "clients": self.clients,
            "txsize": self.txsize,
            "rxsize": self.rxsize,
            "txbytes": self.txbytes,
            "rxbytes": self.rxbytes,
            "txcnt": self.txcnt,
            "rxcnt": self.rxcnt,
            "plugin": self.plugin,
            "updated_at": self.updated_at,
        }
