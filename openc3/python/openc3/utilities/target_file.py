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
    # The file listing appends '*' to a name to mark it as modified on the server
    # (see TargetFile.all in the Ruby library). The marker is display-only, so
    # every read strips it.
    #
    # Strip only '*' at the end of a file name. '*' is a legal S3 object key character
    # and is allowed by FileOpenSaveDialog's filename charset, so files named that
    # way exist in the field and have to stay addressable.
    @classmethod
    def strip_modified(cls, name):
        return name[:-1] if name.endswith("*") else name

    @classmethod
    def body(cls, scope, name):
        name = cls.strip_modified(name)  # Remove '*' that indicates modified
        # First try opening a potentially modified version by looking for the modified target
        if OPENC3_LOCAL_MODE:
            local_file = LocalMode.open_local_file(name, scope=scope)
            if local_file:
                return local_file.read()

        bucket = Bucket.get_client()
        resp = bucket.get_object(bucket=OPENC3_CONFIG_BUCKET, key=f"{scope}/targets_modified/{name}")
        if not resp:
            # Now try the original
            resp = bucket.get_object(bucket=OPENC3_CONFIG_BUCKET, key=f"{scope}/targets/{name}")
        if resp and resp["Body"]:
            return resp["Body"].read()
        else:
            return None
