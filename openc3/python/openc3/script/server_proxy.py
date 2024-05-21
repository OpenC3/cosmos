# Copyright 2024 OpenC3, Inc.
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

import os
import re
from openc3.environment import *
from openc3.utilities.authentication import (
    OpenC3Authentication,
    OpenC3KeycloakAuthentication,
)
from openc3.io.json_drb_object import JsonDRbObject
from openc3.io.json_api_object import JsonApiObject

# TODO: ImportError: cannot import name 'DISCONNECT' from partially initialized module 'openc3.script' (most likely due to a circular import) (/usr/lib/python3.11/site-packages/openc3/script/__init__.py)
# from openc3.script import DISCONNECT
import openc3.script


class ApiServerProxy:
    """Provides a proxy to the JsonDRbObject which communicates with the API server"""

    def generate_url(self):
        """pull openc3-cosmos-cmd-tlm-api url from environment variables"""
        hostname = os.environ.get("OPENC3_API_HOSTNAME")
        if not hostname:
            devel = os.environ.get("OPENC3_DEVEL")
            if devel:
                hostname = "127.0.0.1"
            else:
                hostname = "openc3-cosmos-cmd-tlm-api"

        return f"{OPENC3_API_SCHEMA}://{hostname}:{OPENC3_API_PORT}"

    def generate_timeout(self):
        """pull openc3-cosmos-cmd-tlm-api timeout from environment variables"""
        return float(OPENC3_API_TIMEOUT)

    def generate_auth(self):
        """Generate auth object for use with the JsonDRbObject"""
        if OPENC3_API_TOKEN is None and OPENC3_API_USER is None:
            if OPENC3_API_PASSWORD:
                return OpenC3Authentication()
            else:
                return None
        else:
            return OpenC3KeycloakAuthentication(OPENC3_KEYCLOAK_URL)

    def __init__(self):
        """Create a JsonDRbObject connection to the API server"""
        self.json_drb = JsonDRbObject(
            url=self.generate_url(),
            timeout=self.generate_timeout(),
            authentication=self.generate_auth(),
        )

    def __getattr__(self, func):
        """Proxy methods to the API server through the JsonDRbObject"""

        def method(*args, **kwargs):
            if "scope" not in kwargs:
                kwargs["scope"] = OPENC3_SCOPE
            match func:
                case "shutdown":
                    return self.json_drb.shutdown()
                case "request":
                    return self.json_drb.request(*args, **kwargs)
                case _:
                    disconnect = kwargs.pop("disconnect", None)
                    if openc3.script.DISCONNECT:
                        if disconnect:
                            return disconnect
                        else:
                            # The only commands allowed through in disconnect mode are read-only
                            # Thus we allow the get, list, tlm and limits_enabled and subscribe methods
                            if re.compile(
                                r"\w*_get$|^get_\w*|\w*_list$|^list_\w*|^tlm|^limits_enabled$|^subscribe$"
                            ).match(func):
                                return getattr(self.json_drb, func)(*args, **kwargs)
                            else:
                                return None
                    else:
                        return getattr(self.json_drb, func)(*args, **kwargs)

        return method


class ScriptServerProxy:
    """Provides a proxy to the Script Runner API which communicates with the API server"""

    def generate_url(self):
        """pull openc3-cosmos-script-runner-api url from environment variables"""
        hostname = os.environ.get("OPENC3_SCRIPT_API_HOSTNAME")
        if not hostname:
            devel = os.environ.get("OPENC3_DEVEL")
            if devel:
                hostname = "127.0.0.1"
            else:
                hostname = "openc3-cosmos-script-runner-api"
        return f"{OPENC3_SCRIPT_API_SCHEMA}://{hostname}:{OPENC3_SCRIPT_API_PORT}"

    def generate_timeout(self):
        """pull openc3-cosmos-script-runner-api timeout from environment variables"""
        return float(OPENC3_SCRIPT_API_TIMEOUT)

    def __init__(self):
        """Create a JsonApiObject connection to the API server"""
        self.json_api = JsonApiObject(
            url=self.generate_url(),
            timeout=self.generate_timeout(),
            # JsonApiObject calls generate_auth
        )

    def shutdown(self):
        self.json_api.shutdown()

    def request(self, *method_params, **kw_params):
        if "scope" not in kw_params:
            kw_params["scope"] = OPENC3_SCOPE

        # If 'disconnect' is there delete it and return the value
        disconnect = kw_params.pop("disconnect", None)
        if openc3.script.DISCONNECT and disconnect:
            # If they overrode the return value using the disconnect keyword then return that
            return disconnect
        else:
            return self.json_api.request(*method_params, **kw_params)
