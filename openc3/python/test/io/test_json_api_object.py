# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
from unittest.mock import MagicMock, patch

from requests.exceptions import ConnectTimeout, ReadTimeout

from openc3.io.json_api_object import RETRY_COUNT, JsonApiObject
from openc3.io.json_drb_object import JsonDRbObject


URL = "http://openc3-cosmos-cmd-tlm-api:2901"


class TestJsonApiObjectReadTimeout(unittest.TestCase):
    def test_defaults_to_default_read_timeout(self):
        api_object = JsonApiObject(URL, timeout=1.0)
        self.assertEqual(api_object.read_timeout, JsonApiObject.DEFAULT_READ_TIMEOUT_S)
        # Must be well beyond any per request application timeout, e.g. cmd() with
        # timeout: 100 waiting on an interface ack.
        self.assertGreater(api_object.read_timeout, 60)

    def test_honors_the_read_timeout_keyword(self):
        api_object = JsonApiObject(URL, timeout=1.0, read_timeout=120.0)
        self.assertEqual(api_object.read_timeout, 120.0)

    @patch("openc3.io.json_api_object.OPENC3_API_READ_TIMEOUT", 300.0)
    def test_honors_the_openc3_api_read_timeout_environment_variable(self):
        api_object = JsonApiObject(URL, timeout=1.0)
        self.assertEqual(api_object.read_timeout, 300.0)

    @patch("openc3.io.json_api_object.OPENC3_API_READ_TIMEOUT", 300.0)
    def test_prefers_the_read_timeout_keyword_over_the_environment_variable(self):
        api_object = JsonApiObject(URL, timeout=1.0, read_timeout=120.0)
        self.assertEqual(api_object.read_timeout, 120.0)

    def test_does_not_use_the_connect_timeout_as_the_read_timeout(self):
        # timeout is the connection phase limit only. A short one must not cut off a
        # long running response.
        api_object = JsonApiObject(URL, timeout=1.0)
        kwargs = api_object._generate_kwargs({"scope": "DEFAULT"})
        self.assertEqual(kwargs["timeout"], (1.0, JsonApiObject.DEFAULT_READ_TIMEOUT_S))

    def test_passes_the_timeout_tuple_to_requests(self):
        # requests has no default timeout at all, so it must be passed explicitly or
        # every call blocks forever.
        api_object = JsonApiObject(URL, timeout=2.0, read_timeout=30.0)
        api_object.http = MagicMock()
        api_object.request("get", "/openc3-api/timeline", scope="DEFAULT")
        self.assertEqual(api_object.http.get.call_args.kwargs["timeout"], (2.0, 30.0))

    def test_lets_a_caller_override_the_timeout_per_request(self):
        api_object = JsonApiObject(URL, timeout=2.0, read_timeout=30.0)
        api_object.http = MagicMock()
        api_object.request("get", "/openc3-api/timeline", scope="DEFAULT", timeout=(5.0, 6.0))
        self.assertEqual(api_object.http.get.call_args.kwargs["timeout"], (5.0, 6.0))

    def test_treats_an_explicit_timeout_of_none_as_unset(self):
        # requests reads timeout=None as "block forever", which is the bug this whole
        # change exists to prevent. A caller writing None means "use the default".
        api_object = JsonApiObject(URL, timeout=2.0, read_timeout=30.0)
        http = api_object.http = MagicMock()
        api_object.request("get", "/openc3-api/timeline", scope="DEFAULT", timeout=None)
        self.assertEqual(http.get.call_args.kwargs["timeout"], (2.0, 30.0))

    def test_json_drb_object_passes_read_timeout_through(self):
        drb_object = JsonDRbObject(URL, timeout=1.0, read_timeout=120.0)
        self.assertEqual(drb_object.read_timeout, 120.0)


class TestJsonApiObjectRetry(unittest.TestCase):
    def test_does_not_retry_after_a_read_timeout(self):
        # The request was fully sent, so the server may have already acted on it.
        # Retrying a non idempotent POST would duplicate the operation.
        api_object = JsonApiObject(URL, timeout=1.0)
        # Hold our own reference, disconnect() sets api_object.http to None.
        http = api_object.http = MagicMock()
        http.post.side_effect = ReadTimeout("timed out")

        def reconnect():
            api_object.http = http

        # connect() is stubbed so a retry would reach the same mock. Without that the
        # real connect() replaces it and the call count stays at 1 either way.
        with (
            patch.object(JsonApiObject, "connect", side_effect=reconnect),
            patch("openc3.io.json_api_object.time.sleep"),
        ):
            with self.assertRaises(RuntimeError):
                api_object.request("post", "/openc3-api/timeline", scope="DEFAULT")
            self.assertEqual(http.post.call_count, 1)

    def test_retries_after_a_connect_timeout(self):
        # Nothing was successfully sent, so replaying is safe.
        api_object = JsonApiObject(URL, timeout=1.0)
        http = api_object.http = MagicMock()
        http.post.side_effect = ConnectTimeout("timed out")

        def reconnect():
            api_object.http = http

        with (
            patch.object(JsonApiObject, "connect", side_effect=reconnect),
            patch("openc3.io.json_api_object.time.sleep"),
        ):
            with self.assertRaises(RuntimeError):
                api_object.request("post", "/openc3-api/timeline", scope="DEFAULT")
            self.assertEqual(http.post.call_count, RETRY_COUNT + 1)

    def test_read_timeout_disconnects_so_the_socket_is_not_reused(self):
        # A late response may still arrive on that socket.
        api_object = JsonApiObject(URL, timeout=1.0)
        http = api_object.http = MagicMock()
        http.post.side_effect = ReadTimeout("timed out")
        with self.assertRaises(RuntimeError):
            api_object.request("post", "/openc3-api/timeline", scope="DEFAULT")
        self.assertIsNone(api_object.http)
        http.close.assert_called_once()


if __name__ == "__main__":
    unittest.main()
