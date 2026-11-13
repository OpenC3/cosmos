# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

"""Reduces item limits states to a single color.

Shared by get_overall_limits_state and the limits group rollup so they rank
states the same way. Keep in sync with lib/openc3/utilities/limits_rollup.rb
"""

from collections.abc import Iterable


COLORS = {
    "RED": "RED",
    "RED_HIGH": "RED",
    "RED_LOW": "RED",
    "YELLOW": "YELLOW",
    "YELLOW_HIGH": "YELLOW",
    "YELLOW_LOW": "YELLOW",
    "GREEN": "GREEN",
    "GREEN_HIGH": "GREEN",
    "GREEN_LOW": "GREEN",
    "BLUE": "GREEN",
}
SEVERITY = {"GREEN": 0, "YELLOW": 1, "RED": 2}


def color(state: str | None) -> str | None:
    """Return 'GREEN', 'YELLOW' or 'RED' for a limits state, or None for a missing or unknown state."""
    return COLORS.get(state) if state is not None else None


def worst(states: Iterable[str | None]) -> str | None:
    """Return the most severe color among states, or None if no state counts."""
    colors = [c for c in (color(state) for state in states) if c is not None]
    if not colors:
        return None
    return max(colors, key=lambda c: SEVERITY[c])


def rollup(members: Iterable[tuple[str | None, bool]]) -> tuple[str | None, bool]:
    """Roll up a limits group from (limits_state, enabled) per member.

    Members with limits disabled are ignored for the color, as are missing states.
    The group is enabled only when it has members and every one is enabled.
    Returns (color, enabled) where color is None when no enabled member has a state.
    """
    members = list(members)
    states = [state for state, enabled in members if enabled]
    enabled = bool(members) and all(member_enabled for _, member_enabled in members)
    return worst(states), enabled
