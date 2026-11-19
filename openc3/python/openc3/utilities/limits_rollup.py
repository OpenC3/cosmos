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
    "BLUE": "BLUE",
}
# BLUE ranks below GREEN so a rollup is only BLUE when every state is BLUE
SEVERITY = {"BLUE": -1, "GREEN": 0, "YELLOW": 1, "RED": 2}
# A group whose members all have limits disabled
DISABLED = "DISABLED"
# Whether limits are enabled on a group's members: all, none, or some of them
ENABLED_TRUE = "TRUE"
ENABLED_FALSE = "FALSE"
ENABLED_PARTIAL = "PARTIAL"


def color(state: str | None) -> str | None:
    """Return 'BLUE', 'GREEN', 'YELLOW' or 'RED' for a limits state, or None for a missing or unknown state."""
    return COLORS.get(state) if state is not None else None


def worst(states: Iterable[str | None]) -> str | None:
    """Return the most severe color among states, or None if no state counts."""
    colors = [c for c in (color(state) for state in states) if c is not None]
    if not colors:
        return None
    return max(colors, key=lambda c: SEVERITY[c])


def enabled_state(enabled: bool | str | None) -> str:
    """Return ENABLED_TRUE, ENABLED_FALSE or ENABLED_PARTIAL.

    Items pass True or False, nested groups pass their rolled up enabled state.
    """
    if enabled is True:
        return ENABLED_TRUE
    if enabled is False or enabled is None:
        return ENABLED_FALSE
    return enabled


def rollup(members: Iterable[tuple[str | None, bool | str]]) -> tuple[str | None, str]:
    """Roll up a limits group from (limits_state, enabled) per member.

    Items pass True or False for enabled, nested groups pass their rolled up
    (state, enabled). The group is enabled (ENABLED_TRUE) when every member is,
    disabled (ENABLED_FALSE) when no member is or the group is empty, and
    otherwise ENABLED_PARTIAL. A disabled group's state is DISABLED. Otherwise
    it's the most severe state of the members which aren't disabled, ignoring
    missing states. Returns (state, enabled) where state is None when no member
    which counts has a state.
    """
    members = [(state, enabled_state(enabled)) for state, enabled in members]
    enabled_states = {enabled for _, enabled in members}
    if not enabled_states or enabled_states == {ENABLED_FALSE}:
        return DISABLED, ENABLED_FALSE
    enabled = ENABLED_TRUE if enabled_states == {ENABLED_TRUE} else ENABLED_PARTIAL
    states = [state for state, member_enabled in members if member_enabled != ENABLED_FALSE]
    return worst(states), enabled
