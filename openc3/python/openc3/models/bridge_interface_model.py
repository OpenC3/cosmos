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

from openc3.models.model import Model


class BridgeInterfaceModel(Model):
    """The COSMOS-side identity of a bridge_interface for the Iroh data path.

    Each COSMOS ``bridge_interface`` binds a per-process Iroh keypair and records
    its public key (EndpointId) here, keyed by interface name. The
    bridge_microservice hub reads it to verify the trusted COSMOS ``stream/<name>``
    leg, mirroring how host-side interfaces are authorized on ``host/<name>``.

    One record per interface name (so each interface writes only its own field —
    no read-modify-write races on a shared record).
    """

    PRIMARY_KEY = "openc3_bridge_interface_keys"

    # NOTE: The following class methods are reimplemented so the base Model
    # class methods work with this scoped primary key.
    @classmethod
    def get(cls, name: str, scope: str):
        return super().get(f"{scope}__{cls.PRIMARY_KEY}", name)

    @classmethod
    def names(cls, scope: str):
        return super().names(f"{scope}__{cls.PRIMARY_KEY}")

    @classmethod
    def all(cls, scope: str):
        return super().all(f"{scope}__{cls.PRIMARY_KEY}")

    # END NOTE

    def __init__(
        self,
        name: str,
        scope: str,
        public_key: str = None,
        updated_at: int = None,
        plugin: str = None,
    ):
        super().__init__(
            f"{scope}__{self.PRIMARY_KEY}",
            name=name,
            scope=scope,
            updated_at=updated_at,
            plugin=plugin,
        )
        # The bridge_interface's Iroh public key (EndpointId) as a hex string.
        self.public_key = public_key

    def as_json(self):
        return {
            "name": self.name,
            "scope": self.scope,
            "updated_at": self.updated_at,
            "plugin": self.plugin,
            "public_key": self.public_key,
        }
