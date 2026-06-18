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

from openc3.environment import OPENC3_CONFIG_BUCKET, OPENC3_LOCAL_MODE
from openc3.utilities.bucket import Bucket
from openc3.utilities.local_mode import LocalMode


class TargetFile:
    @classmethod
    def body(cls, scope, name, original=False):
        # When original is True, read only the read-only plugin-installed targets/ tree
        # and ignore the user-writable targets_modified/ overlay. Use this for any path
        # that executes the file as code (e.g. GENERIC_*_CONVERSION evaluation) so a
        # non-admin overlay write cannot inject code.
        name = name.split("*")[0]  # Split '*' that indicates modified
        # First try opening a potentially modified version by looking for the modified target.
        # Skipped entirely when original is requested so the overlay is never treated as code.
        if not original and OPENC3_LOCAL_MODE:
            local_file = LocalMode.open_local_file(name, scope=scope)
            if local_file:
                return local_file.read()

        bucket = Bucket.get_client()
        resp = None if original else bucket.get_object(bucket=OPENC3_CONFIG_BUCKET, key=f"{scope}/targets_modified/{name}")
        if not resp:
            # Now try the original
            resp = bucket.get_object(bucket=OPENC3_CONFIG_BUCKET, key=f"{scope}/targets/{name}")
        if resp and resp["Body"]:
            return resp["Body"].read()
        else:
            return None
