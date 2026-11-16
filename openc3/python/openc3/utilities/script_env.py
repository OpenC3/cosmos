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

# Environment handling for the child processes that execute user scripts
# (script runs and suite analysis). Processes are spawned from Ruby, see
# openc3/lib/openc3/utilities/script_env.rb

import os

from openc3.utilities.bucket import Bucket
from openc3.utilities.store import EphemeralStore, Store


# Not used by script processes so never passed to them
UNUSED_VARS = [
    # This actually contains the password via redis://openc3:XXXXXXXX@openc3-redis:6379
    "ANYCABLE_REDIS_URL",
    "OPENC3_TSDB_USERNAME",
    "OPENC3_TSDB_PASSWORD",
    "KC_DB_USERNAME",
    "KC_DB_PASSWORD",
    "KEYCLOAK_ADMIN",
    "KEYCLOAK_ADMIN_PASSWORD",
]
# Cleared by script processes once they have connected
CLEARED_VARS = [
    "OPENC3_BUCKET_USERNAME",
    "OPENC3_BUCKET_PASSWORD",
    "OPENC3_REDIS_USERNAME",
    "OPENC3_REDIS_PASSWORD",
    "OPENC3_API_PASSWORD",
    "OPENC3_SERVICE_PASSWORD",
] + UNUSED_VARS


def clear_credentials():
    """Called in the script process before any user code runs"""
    # Load the bucket client code to ensure we authenticate outside ENV vars
    Bucket.get_client()
    # Preload Store and remove Redis secrets from ENV
    Store.instance()
    EphemeralStore.instance()
    for key in CLEARED_VARS:
        os.environ.pop(key, None)
