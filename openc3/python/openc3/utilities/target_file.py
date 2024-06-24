# Copyright 2023 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.environment import OPENC3_LOCAL_MODE, OPENC3_CONFIG_BUCKET
from openc3.utilities.local_mode import LocalMode
from openc3.utilities.bucket import Bucket


class TargetFile:
    @classmethod
    def body(cls, scope, name):
        name = name.split("*")[0]  # Split '*' that indicates modified
        # First try opening a potentially modified version by looking for the modified target
        if OPENC3_LOCAL_MODE:
            local_file = LocalMode.open_local_file(name, scope=scope)
            if local_file:
                return local_file.read()

        bucket = Bucket.getClient()
        resp = bucket.get_object(bucket=OPENC3_CONFIG_BUCKET, key=f"{scope}/targets_modified/{name}")
        if not resp:
            # Now try the original
            resp = bucket.get_object(bucket=OPENC3_CONFIG_BUCKET, key=f"{scope}/targets/{name}")
        if resp and resp["Body"]:
            return resp["Body"].read()
        else:
            return None
