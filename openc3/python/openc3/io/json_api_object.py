# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
import time
import traceback
from threading import Lock

from requests import Session
from requests.exceptions import ReadTimeout

from openc3.environment import (
    OPENC3_API_PASSWORD,
    OPENC3_API_READ_TIMEOUT,
    OPENC3_API_TOKEN,
    OPENC3_API_USER,
    OPENC3_KEYCLOAK_URL,
)
from openc3.utilities.authentication import (
    OpenC3Authentication,
    OpenC3KeycloakAuthentication,
)
from openc3.utilities.logger import Logger


# Number of times to retry a request when a connection error occurs
RETRY_COUNT = 3
# Delay between retries in seconds
RETRY_DELAY = 0.1


class JsonApiError(Exception):
    pass


class JsonApiObject:
    """Used to forward all method calls to the remote server object. Before using
    this class ensure the remote service has been started in the server class:

        json = JsonApiObject('127.0.0.1', 7777, self)

    Now the JsonApiObject can be used to call server methods directly:

        server = JsonApiObject('http://openc3-cosmos-cmd-tlm-api:2901', 1.0)
        server.cmd(*args)

    """

    USER_AGENT = "OpenC3 v7 (python/openc3/io/json_api_object)"

    # Time limit for the first response byte from the server. Requests can
    # legitimately block for a long time, e.g. cmd() with a large timeout waiting
    # on an interface ack, so this is effectively "wait forever" while still
    # bounded so a wedged connection eventually releases the thread.
    DEFAULT_READ_TIMEOUT_S = 86400

    def __init__(
        self,
        url: str,
        timeout: float = 1.0,
        authentication: OpenC3Authentication | None = None,
        read_timeout: float | None = None,
    ):
        """
        Args:
            url (str): The url of openc3-cosmos-cmd-tlm-api http://openc3-cosmos-cmd-tlm-api:2901
            timeout (float): The time to wait for the connection phase before disconnecting default = 1.0
            authentication (OpenC3Authentication): The authentication object if None initialize will generate default
            read_timeout (float): The time to wait for the first response byte from the server.
                Defaults to the OPENC3_API_READ_TIMEOUT environment variable or DEFAULT_READ_TIMEOUT_S.
        """
        self.http = None
        self.mutex = Lock()
        self.request_data = ""
        self.response_data = ""
        self.url: str = url
        self.log = [None, None, None]
        self.authentication = authentication if authentication else self.generate_auth()
        self.timeout: float = timeout
        if read_timeout is None:
            read_timeout = OPENC3_API_READ_TIMEOUT
        if read_timeout is None:
            read_timeout = self.DEFAULT_READ_TIMEOUT_S
        self.read_timeout: float = float(read_timeout)
        self._shutdown: bool = False

    @staticmethod
    def generate_auth():
        """generate the auth object"""
        if OPENC3_API_TOKEN is None and OPENC3_API_USER is None:
            return OpenC3Authentication() if OPENC3_API_PASSWORD else None
        else:
            return OpenC3KeycloakAuthentication(OPENC3_KEYCLOAK_URL)

    def request(self, *method_params, **keyword_params):
        """Forwards all method calls to the remote service.
        Args:
            method_params (list) Array of parameters to pass to the method
            keyword_params (dict <Symbol, Variable>) Hash of keyword parameters
        Returns:
            return The result of the method call.
        """
        if self._shutdown:
            raise JsonApiError("Shutdown")
        method = method_params[0]
        endpoint = method_params[1]
        with self.mutex:
            kwargs = self._generate_kwargs(keyword_params)
            self.log = [None, None, None]
            if not self.http:
                self.connect()
            return self._send_request(method, endpoint, kwargs)

    def disconnect(self):
        """Disconnects from http server"""
        if self.http:
            self.http.close()
        self.http = None

    def shutdown(self):
        """Permanently disconnects from the http server"""
        self._shutdown = True
        self.disconnect()

    def connect(self):
        try:
            self.http = Session()
        except Exception as error:
            raise JsonApiError(error) from error

    def _generate_kwargs(self, keyword_params):
        """NOTE: This is a helper method and should not be called directly"""
        kwargs = {}
        for key, value in keyword_params.items():
            kwargs[key] = value

        kwargs["scope"] = self._generate_scope(kwargs)
        kwargs["headers"] = self._generate_headers(kwargs)
        kwargs["data"] = self._generate_data(kwargs)
        kwargs["query"] = self._generate_query(kwargs)
        # (connect, read) tuple. requests has no default timeout at all, so this must be
        # set explicitly or every call blocks forever. A caller may pass their own per
        # request timeout, but timeout=None means "unset, use the default" here rather
        # than requests' "block forever", matching how read_timeout=None is treated above.
        timeout = kwargs.pop("timeout", None)
        kwargs["timeout"] = timeout if timeout is not None else (self.timeout, self.read_timeout)
        kwargs["params"] = kwargs["query"]
        del kwargs["query"]
        del kwargs["scope"]
        return kwargs

    @staticmethod
    def _generate_scope(kwargs):
        """NOTE: This is a helper method and should not be called directly"""
        scope = kwargs.get("scope", None)
        if not scope:
            raise JsonApiError(f"no scope keyword found: {kwargs}")
        elif not isinstance(scope, str):
            raise JsonApiError(f"incorrect type for keyword 'scope' MUST be String: {scope}")
        return scope

    def _generate_headers(self, kwargs):
        """NOTE: This is a helper method and should not be called directly"""
        headers = kwargs.get("headers", None)
        if not headers:
            headers = kwargs["headers"] = {}
        elif not isinstance(headers, dict):
            raise JsonApiError(f"incorrect type for keyword 'headers' MUST be Dictionary: {headers}")

        if "json" in kwargs and kwargs["json"]:
            headers["Content-Type"] = "application/json"
        token = kwargs.get("token", None)
        if self.authentication and not token:
            token = self.authentication.token()
        if token:
            headers["User-Agent"] = self.USER_AGENT
            headers["Authorization"] = token
        else:
            headers["User-Agent"] = self.USER_AGENT
        return headers

    @staticmethod
    def _generate_data(kwargs):
        """NOTE: This is a helper method and should not be called directly"""
        data = kwargs.get("data", None)
        if not data:
            data = kwargs["data"] = {}
        elif not isinstance(data, dict) and not isinstance(data, str):
            raise JsonApiError(f"incorrect type for keyword 'data' MUST be Dictionary or String: {data}")
        if "json" in kwargs and kwargs["json"]:
            return json.dumps(kwargs["data"])
        else:
            return kwargs["data"]

    @staticmethod
    def _generate_query(kwargs):
        """NOTE: This is a helper method and should not be called directly"""
        query = kwargs.get("query", None)
        if query is None:
            query = kwargs["query"] = {}
        elif not isinstance(query, dict):
            raise JsonApiError(f"incorrect type for keyword 'query' MUST be Dictionary: {query}")
        if "scope" in kwargs and kwargs["scope"]:
            kwargs["query"]["scope"] = kwargs["scope"]
        return kwargs["query"]

    def _send_request(self, method, endpoint, kwargs):
        """NOTE: This is a helper method and should not be called directly"""
        kwargs["url"] = f"{self.url}{endpoint}"
        self.log[0] = f"{method} Request: {kwargs}"

        retry = 0
        while retry <= RETRY_COUNT:
            try:
                resp = getattr(self.http, method)(**kwargs)
                self.log[1] = f"{method} Response: {resp.status_code} {resp.headers} {resp.text}"
                self.response_data = resp.text
                return resp
            except ReadTimeout as e:
                # NOT retryable. A read timeout means the request was fully sent and the
                # server may have already acted on it. Many endpoints are not idempotent
                # (create_activity, script_run, cmd), so a retry risks duplicating the
                # operation. It would also blow past the caller's deadline by RETRY_COUNT
                # times. Ruby matches this: Faraday::TimeoutError is not in its retry list.
                # NOTE: ReadTimeout subclasses OSError, so this must precede that branch.
                self.log[2] = f"{method} Exception: {traceback.format_exc()}"
                self.disconnect()
                error = f"Api Exception: {self.log[0]} ::: {self.log[1]} ::: {self.log[2]}"
                raise RuntimeError(error) from e
            except OSError as e:
                # Retryable. Nothing was successfully sent, so replaying is safe. This
                # includes ConnectTimeout, which covers a service that is still starting up.
                retry += 1
                self.log[2] = f"{method} Exception: {traceback.format_exc()}"
                if retry <= RETRY_COUNT:
                    Logger.warn(f"JsonApiObject: Connection error, retry {retry}/{RETRY_COUNT}: {repr(e)}")
                    self.disconnect()
                    time.sleep(RETRY_DELAY)
                    self.connect()
                else:
                    error = f"Api Exception: {self.log[0]} ::: {self.log[1]} ::: {self.log[2]}"
                    raise RuntimeError(error) from e
            except Exception as e:
                self.log[2] = f"{method} Exception: {traceback.format_exc()}"
                self.disconnect()
                error = f"Api Exception: {self.log[0]} ::: {self.log[1]} ::: {self.log[2]}"
                raise RuntimeError(error) from e
        # Should not reach here, but just in case
        error = f"Api Exception: {self.log[0]} ::: {self.log[1]} ::: {self.log[2]}"
        raise RuntimeError(error)
