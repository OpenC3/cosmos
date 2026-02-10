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

from openc3.environment import *


if OPENC3_REDIS_CLUSTER:
    openc3_redis_cluster = True
else:
    openc3_redis_cluster = False



if openc3_redis_cluster:
    import openc3enterprise.utilities.store  # noqa: F401
