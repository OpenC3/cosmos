# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os
import re
from collections.abc import Callable
from typing import Any

# TODO: ImportError: cannot import name 'DISCONNECT' from partially initialized module 'openc3.script' (most likely due to a circular import) (/usr/lib/python3.11/site-packages/openc3/script/__init__.py)
# from openc3.script import DISCONNECT
import openc3.script
from openc3.environment import *
from openc3.io.json_api_object import JsonApiObject
from openc3.io.json_drb_object import JsonDRbObject
from openc3.utilities.authentication import OpenC3Authentication, authentication_from_environment


class ApiServerProxy:
    """Proxy calls to the cmd-tlm-api JSON-RPC server through a JsonDRbObject.

    Any attribute access returns a function that forwards the call to the API
    method of the same name. A ``scope`` keyword of OPENC3_SCOPE is added when
    not given. In disconnect mode only read-only methods are forwarded::

        proxy = ApiServerProxy()
        proxy.tlm("INST HEALTH_STATUS TEMP1")
    """

    def generate_url(self) -> str:
        """Build the openc3-cosmos-cmd-tlm-api URL from environment variables.

        Returns:
            The URL, using 127.0.0.1 when OPENC3_DEVEL is set and
            OPENC3_API_HOSTNAME is not.
        """
        hostname = os.environ.get("OPENC3_API_HOSTNAME")
        if not hostname:
            devel = os.environ.get("OPENC3_DEVEL")
            if devel:
                hostname = "127.0.0.1"
            else:
                hostname = "openc3-cosmos-cmd-tlm-api"

        return f"{OPENC3_API_SCHEMA}://{hostname}:{OPENC3_API_PORT}"

    def generate_timeout(self) -> float:
        """Return the openc3-cosmos-cmd-tlm-api timeout from environment variables.

        Returns:
            The OPENC3_API_TIMEOUT in seconds.
        """
        return float(OPENC3_API_TIMEOUT)

    def generate_auth(self) -> OpenC3Authentication | None:
        """Build the standard OpenC3 authentication object from environment configuration.

        Returns:
            The authentication, or None if the environment configures none.
        """
        return authentication_from_environment()

    def __init__(self) -> None:
        """Create a JsonDRbObject connection to the API server."""
        self.json_drb = JsonDRbObject(
            url=self.generate_url(),
            timeout=self.generate_timeout(),
            authentication=self.generate_auth(),
        )

    def __getattr__(self, func: str) -> Callable[..., Any]:
        """Return a function that calls the named method on the API server.

        The returned function adds ``scope=OPENC3_SCOPE`` when no scope is
        given. ``shutdown`` and ``request`` go straight to the JsonDRbObject.
        Other methods pop a ``disconnect`` keyword: in disconnect mode a truthy
        ``disconnect`` value is returned instead of calling the server, read-only
        methods (``*_get``, ``get_*``, ``*_list``, ``list_*``, ``tlm*``,
        ``limits_enabled`` and ``subscribe``) are still called, and any other
        method returns None.

        Args:
            func: Name of the API method.

        Returns:
            A function taking the API method's arguments and returning its
            result.
        """

        def method(*args: Any, **kwargs: Any):
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
    """Proxy requests to the Script Runner API through a JsonApiObject."""

    def generate_url(self) -> str:
        """Build the openc3-cosmos-script-runner-api URL from environment variables.

        Returns:
            The URL, using 127.0.0.1 when OPENC3_DEVEL is set and
            OPENC3_SCRIPT_API_HOSTNAME is not.
        """
        hostname = os.environ.get("OPENC3_SCRIPT_API_HOSTNAME")
        if not hostname:
            devel = os.environ.get("OPENC3_DEVEL")
            if devel:
                hostname = "127.0.0.1"
            else:
                hostname = "openc3-cosmos-script-runner-api"
        return f"{OPENC3_SCRIPT_API_SCHEMA}://{hostname}:{OPENC3_SCRIPT_API_PORT}"

    def generate_timeout(self) -> float:
        """Return the openc3-cosmos-script-runner-api timeout from environment variables.

        Returns:
            The OPENC3_SCRIPT_API_TIMEOUT in seconds.
        """
        return float(OPENC3_SCRIPT_API_TIMEOUT)

    def __init__(self) -> None:
        """Create a JsonApiObject connection to the Script Runner API."""
        self.json_api = JsonApiObject(
            url=self.generate_url(),
            timeout=self.generate_timeout(),
            # JsonApiObject calls generate_auth
        )

    def shutdown(self) -> None:
        """Permanently disconnect from the Script Runner API."""
        self.json_api.shutdown()

    def request(self, *method_params: Any, **kw_params: Any) -> Any:
        """Make an HTTP request to the Script Runner API.

        Adds ``scope=OPENC3_SCOPE`` when no scope is given. In disconnect mode
        a truthy ``disconnect`` keyword value is returned instead of making the
        request.

        Args:
            *method_params: The HTTP method and endpoint, passed to
                JsonApiObject.request.
            **kw_params: Request options (data, json, query, headers, scope,
                disconnect, ...) passed to JsonApiObject.request.

        Returns:
            The JsonApiObject.request result (the HTTP response), or the
            ``disconnect`` value in disconnect mode.
        """
        if "scope" not in kw_params:
            kw_params["scope"] = OPENC3_SCOPE

        # If 'disconnect' is there delete it and return the value
        disconnect = kw_params.pop("disconnect", None)
        if openc3.script.DISCONNECT and disconnect:
            # If they overrode the return value using the disconnect keyword then return that
            return disconnect
        else:
            return self.json_api.request(*method_params, **kw_params)
