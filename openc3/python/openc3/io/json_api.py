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

import os

from openc3.environment import (
    OPENC3_API_PASSWORD,
    OPENC3_API_TOKEN,
    OPENC3_API_USER,
    OPENC3_KEYCLOAK_URL,
    OPENC3_SCOPE,
)
from openc3.io.json_api_object import JsonApiObject
from openc3.utilities.authentication import (
    OpenC3Authentication,
    OpenC3KeycloakAuthentication,
)


class JsonApi:
    def __init__(
        self,
        microservice_name: str,
        prefix: str,
        port: int,
        schema: str = "http",
        hostname: str | None = None,
        timeout: float = 5.0,
        url: str | None = None,
        scope: str | None = None,
    ):
        """Create a JsonApiObject connection to the API server.

        Args:
            microservice_name: Name of the microservice (used to build the kubernetes hostname)
            prefix: URL path prefix (e.g. '/openc3-api')
            port: Port the service is listening on
            schema: URL schema, defaults to 'http'
            hostname: Optional explicit hostname override
            timeout: Request timeout in seconds
            url: Optional fully-formed URL; bypasses URL generation when provided
            scope: Optional scope override; defaults to OPENC3_SCOPE env var
        """
        if scope is None:
            scope = OPENC3_SCOPE
        if url is None:
            url = self._generate_url(
                microservice_name=microservice_name,
                prefix=prefix,
                port=port,
                schema=schema,
                hostname=hostname,
                scope=scope,
            )
        self.json_api = JsonApiObject(
            url=url,
            timeout=timeout,
            authentication=self._generate_auth(),
        )

    def shutdown(self):
        self.json_api.shutdown()

    # private

    # pull openc3-cosmos-script-runner-api url from environment variables
    def _generate_url(
        self,
        microservice_name: str,
        prefix: str,
        port: int,
        schema: str = "http",
        hostname: str | None = None,
        scope: str | None = None,
    ) -> str:
        if not prefix.startswith("/"):
            prefix = "/" + prefix
        operator_hostname = os.environ.get("OPENC3_OPERATOR_HOSTNAME")
        if operator_hostname:
            if not hostname:
                hostname = operator_hostname
            return f"{schema}://{hostname}:{int(port)}{prefix}"
        else:
            if os.environ.get("KUBERNETES_SERVICE_HOST"):
                if not hostname:
                    hostname = f"{scope}__USER__{microservice_name}"
                hostname = hostname.lower().replace("__", "-").replace("_", "-")
                return f"{schema}://{hostname}-service:{int(port)}{prefix}"
            else:
                if not hostname:
                    hostname = "openc3-operator"
                return f"{schema}://{hostname}:{int(port)}{prefix}"

    # generate the auth object
    @staticmethod
    def _generate_auth():
        if OPENC3_API_TOKEN is None and OPENC3_API_USER is None:
            if OPENC3_API_PASSWORD:
                return OpenC3Authentication()
            else:
                return None
        else:
            return OpenC3KeycloakAuthentication(OPENC3_KEYCLOAK_URL)

    def _request(self, *method_params, **kw_params):
        if not kw_params.get("scope"):
            kw_params["scope"] = OPENC3_SCOPE
        kw_params["json"] = True # This is JsonApi so should always be speaking json
        return self.json_api.request(*method_params, **kw_params)
