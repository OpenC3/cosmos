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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import re
from openc3.environment import *
from openc3.utilities.authentication import (
    OpenC3Authentication,
    OpenC3KeycloakAuthentication,
)
from openc3.io.json_drb_object import JsonDRbObject

# TODO: ImportError: cannot import name 'DISCONNECT' from partially initialized module 'openc3.script' (most likely due to a circular import) (/usr/lib/python3.11/site-packages/openc3/script/__init__.py)
# from openc3.script import DISCONNECT
import openc3.script


class ServerProxy:
    """Provides a proxy to the JsonDRbObject which communicates with the API server"""

    def generate_url(self):
        """pull openc3-cosmos-cmd-tlm-api url from environment variables"""
        return f"{OPENC3_API_SCHEMA}://{OPENC3_API_HOSTNAME}:{OPENC3_API_PORT}"

    def generate_timeout(self):
        """pull openc3-cosmos-cmd-tlm-api timeout from environment variables"""
        return float(OPENC3_API_TIMEOUT)

    # generate the auth object
    def generate_auth(self):
        if OPENC3_API_TOKEN is None and OPENC3_API_USER is None:
            if OPENC3_API_PASSWORD:
                return OpenC3Authentication()
            else:
                return None
        else:
            return OpenC3KeycloakAuthentication(OPENC3_KEYCLOAK_URL)

    # Create a JsonDRbObject connection to the API server
    def __init__(self):
        self.json_drb = JsonDRbObject(
            url=self.generate_url(),
            timeout=self.generate_timeout(),
            authentication=self.generate_auth(),
        )

    # Proxy methods to the API server through the JsonDRbObject
    def __getattr__(self, func):
        def method(*args, **kwargs):
            if "scope" not in kwargs:
                kwargs["scope"] = OPENC3_SCOPE
            match func:
                case "shutdown":
                    return self.json_drb.shutdown()
                case "request":
                    return self.json_drb.request(*args, **kwargs)
                case _:
                    if openc3.script.DISCONNECT:
                        result = None
                        disconnect = kwargs.pop("disconnect", None)
                        # The only commands allowed through in disconnect mode are read-only
                        # Thus we allow the get, list, tlm and limits_enabled and subscribe methods
                        if re.compile(
                            r"get_\w*|list_\w*|^tlm|limits_enabled|subscribe"
                        ).match(func):
                            result = getattr(self.json_drb, func)(*args, **kwargs)
                        # If they overrode the return value using the disconnect keyword then return that
                        if disconnect:
                            return disconnect
                        else:
                            return result
                    else:
                        return getattr(self.json_drb, func)(*args, **kwargs)

        return method
