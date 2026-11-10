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

from openc3.utilities import script_env


def test_cleared_vars_include_unused_vars():
    for key in script_env.UNUSED_VARS:
        assert key in script_env.CLEARED_VARS


def test_clear_credentials_connects_before_clearing(monkeypatch):
    for key in script_env.CLEARED_VARS:
        monkeypatch.setenv(key, "value")
    monkeypatch.setenv("OPENC3_SCOPE", "DEFAULT")
    calls = []

    def record(name):
        def side_effect():
            calls.append((name, all(key in os.environ for key in script_env.CLEARED_VARS)))

        return side_effect

    monkeypatch.setattr(script_env.Bucket, "get_client", record("bucket"))
    monkeypatch.setattr(script_env.Store, "instance", record("store"))
    monkeypatch.setattr(script_env.EphemeralStore, "instance", record("ephemeral"))

    script_env.clear_credentials()

    assert calls == [("bucket", True), ("store", True), ("ephemeral", True)]
    for key in script_env.CLEARED_VARS:
        assert key not in os.environ
    assert os.environ["OPENC3_SCOPE"] == "DEFAULT"


def test_clear_credentials_ignores_missing_vars(monkeypatch):
    for key in script_env.CLEARED_VARS:
        monkeypatch.delenv(key, raising=False)
    monkeypatch.setattr(script_env.Bucket, "get_client", lambda: None)
    monkeypatch.setattr(script_env.Store, "instance", lambda: None)
    monkeypatch.setattr(script_env.EphemeralStore, "instance", lambda: None)

    script_env.clear_credentials()

    for key in script_env.CLEARED_VARS:
        assert key not in os.environ
