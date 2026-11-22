# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

"""Type aliases shared by the public API signatures."""

from typing import Literal


# Value type of a telemetry or command item. WITH_UNITS is deprecated and
# treated as FORMATTED.
ValueType = Literal["RAW", "CONVERTED", "FORMATTED", "WITH_UNITS"]

# Value type accepted by override_tlm and normalize_tlm, where ALL applies
# to every value type at once.
OverrideValueType = Literal["ALL", "RAW", "CONVERTED", "FORMATTED", "WITH_UNITS"]
