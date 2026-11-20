# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import logging
import time
import warnings

import requests

from openc3.__version__ import __title__
from openc3.environment import *

from .decorators import request_wrapper


LOGGER = logging.getLogger(__title__)


def generate_auth() -> "CosmosAuthorization":
    """Pick the authorization class based on environment variables.

    Returns:
        A `CosmosKeycloakAuthorization` if OPENC3_API_USER is set, otherwise a
        `CosmosAuthorization`.
    """
    if OPENC3_API_USER is None:
        return CosmosAuthorization()
    return CosmosKeycloakAuthorization()


class CosmosAuthorization(requests.auth.AuthBase):
    """Hold the password token for COSMOS Core.

    Use it as the ``auth`` of a requests call to call COSMOS server methods
    directly::

        auth = CosmosAuthorization()
        requests.get("example.org", auth=auth)
    """

    def get(self) -> str | None:
        """Return the authorization header value.

        Returns:
            The OPENC3_API_PASSWORD environment value, or None if it is not set.
        """
        return OPENC3_API_PASSWORD

    def __call__(self, r: requests.PreparedRequest) -> requests.PreparedRequest:
        """Add the Authorization header to a request.

        Args:
            r: The request to authorize.

        Returns:
            The same request with its Authorization header set.
        """
        r.headers["Authorization"] = OPENC3_API_PASSWORD
        return r

    def __repr__(self) -> str:
        """Return the class name without exposing the token."""
        return f"<{self.__class__.__name__}>"

    def __str__(self) -> str:
        """Return the class name without exposing the token."""
        return f"<{self.__class__.__name__}>"


class CosmosKeycloakAuthorization(CosmosAuthorization):
    """Generate and refresh a Keycloak token for COSMOS Enterprise.

    See https://developers.redhat.com/blog/2020/01/29/api-login-and-jwt-token-generation-using-keycloak

    Use it as the ``auth`` of a requests call to call COSMOS server methods
    directly::

        auth = CosmosKeycloakAuthorization()
        requests.get("example.org", auth=auth)

    Tokens are requested from OPENC3_KEYCLOAK_URL in the Keycloak realm
    OPENC3_KEYCLOAK_REALM.
    """

    def __init__(
        self,
        schema: str | None = None,
        hostname: str | None = None,
        port: int | None = None,
    ) -> None:
        """Create the authorization. Tokens are requested lazily on first use.

        The token is always requested from OPENC3_KEYCLOAK_URL.

        Args:
            schema: Deprecated and unused. Passing a value emits a DeprecationWarning.
            hostname: Deprecated and unused. Passing a value emits a DeprecationWarning.
            port: Deprecated and unused. Passing a value emits a DeprecationWarning.
        """
        if schema is not None or hostname is not None or port is not None:
            warnings.warn(
                "CosmosKeycloakAuthorization ignores schema, hostname and port; tokens are always requested "
                "from OPENC3_KEYCLOAK_URL. These arguments are deprecated and will be removed.",
                DeprecationWarning,
                stacklevel=2,
            )
        self.request_url = OPENC3_KEYCLOAK_URL
        self.refresh_token = None
        self.expires_at = None
        self.refresh_expires_at = None
        self.token = None

    def _time_logic(self):
        current_time = time.time()
        if self.token is None or self.refresh_expires_at < current_time:
            self._make_token()
        elif self.expires_at < current_time:
            self._refresh_token()

    def get(self) -> str:
        """Return the authorization header value, requesting or refreshing the token if needed.

        Returns:
            The token as "Bearer <token>".
        """
        self._time_logic()
        return f"Bearer {self.token}"

    def __call__(self, r: requests.PreparedRequest) -> requests.PreparedRequest:
        """Add the Authorization header to a request, requesting or refreshing the token if needed.

        Args:
            r: The request to authorize.

        Returns:
            The same request with its Authorization header set.
        """
        self._time_logic()
        r.headers["Authorization"] = f"Bearer {self.token}"
        return r

    def _make_token(self):
        """Request a new token, or refresh it when no user and password are set.

        The Keycloak response looks like::

            {
                "access_token": "",
                "expires_in": 600,
                "refresh_expires_in": 1800,
                "refresh_token": "",
                "token_type": "bearer",
                "id_token": "",
                "not-before-policy": 0,
                "session_state": "",
                "scope": "openid email profile",
            }
        """
        oath = None
        if OPENC3_API_USER and OPENC3_API_PASSWORD:
            oath = self._make_token_request().json()
        else:
            oath = self._make_refresh_request().json()
        self.token = oath["access_token"]
        self.refresh_token = oath["refresh_token"]
        current_time = time.time()
        self.expires_at = current_time + oath["expires_in"]
        self.refresh_expires_at = current_time + oath["refresh_expires_in"]

    @request_wrapper
    def _make_token_request(self):
        """Use the python requests library to request a token from Cosmos Keycloak.

        This is an internal method decorated with request_wrapper, which
        captures errors from the request library.

        Returns:
            The requests.Response, see
            https://docs.python-requests.org/en/master/user/quickstart/#json-response-content

        Raises:
            RuntimeError: If the request fails or returns an HTTP error status.
        """
        request_kwargs = {
            "url": f"{self.request_url}/realms/{OPENC3_KEYCLOAK_REALM}/protocol/openid-connect/token",
            "data": f"username={OPENC3_API_USER}&password={OPENC3_API_PASSWORD}&client_id={OPENC3_API_CLIENT}&grant_type=password&scope=openid",
            "headers": {
                "User-Agent": OPENC3_USER_AGENT,
                "Content-Type": "application/x-www-form-urlencoded",
            },
        }
        resp = requests.post(**request_kwargs)
        LOGGER.debug(
            "resp: %s total_seconds: %f content: %s",
            resp,
            resp.elapsed.total_seconds(),
            resp.content,
        )
        resp.raise_for_status()
        return resp

    def _refresh_token(self):
        """Refresh the token using the refresh token.

        The Keycloak response looks like::

            {
                "access_token": "",
                "expires_in": 600,
                "refresh_expires_in": 1800,
                "refresh_token": "",
                "token_type": "bearer",
                "id_token": "",
                "not-before-policy": 0,
                "session_state": "",
                "scope": "openid email profile",
            }
        """
        oath = self._make_refresh_request().json()
        self.token = oath["access_token"]
        self.refresh_token = oath["refresh_token"]
        current_time = time.time()
        self.expires_at = current_time + oath["expires_in"]
        self.refresh_expires_at = current_time + oath["refresh_expires_in"]

    @request_wrapper
    def _make_refresh_request(self):
        """Use the python requests library to refresh the token.

        This is an internal method decorated with request_wrapper, which
        captures errors from the request library.

        Returns:
            The requests.Response, see
            https://docs.python-requests.org/en/master/user/quickstart/#json-response-content

        Raises:
            RuntimeError: If the request fails or returns an HTTP error status.
        """
        request_kwargs = {
            "url": f"{self.request_url}/realms/{OPENC3_KEYCLOAK_REALM}/protocol/openid-connect/token",
            "data": f"client_id={OPENC3_API_CLIENT}&grant_type=refresh_token&refresh_token={self.refresh_token}",
            "headers": {
                "User-Agent": OPENC3_USER_AGENT,
                "Content-Type": "application/x-www-form-urlencoded",
            },
        }
        LOGGER.debug("calling with %s", request_kwargs)
        resp = requests.post(**request_kwargs)
        LOGGER.debug(
            "resp: %s total_seconds: %f content: %s",
            resp,
            resp.elapsed.total_seconds(),
            resp.content,
        )
        resp.raise_for_status()
        return resp
