# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1963

# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1957

import contextlib
import json
from typing import Any

from openc3.api import WHITELIST
from openc3.api.api_types import OverrideValueType, ValueType
from openc3.environment import OPENC3_SCOPE
from openc3.models.cvt_model import CvtModel
from openc3.models.interface_model import InterfaceModel
from openc3.models.target_model import TargetModel
from openc3.packets.packet import Packet
from openc3.topics.decom_interface_topic import DecomInterfaceTopic
from openc3.topics.interface_topic import InterfaceTopic
from openc3.topics.topic import Topic
from openc3.utilities.authorization import authorize
from openc3.utilities.extract import (
    extract_fields_from_set_tlm_text,
    extract_fields_from_tlm_text,
)
from openc3.utilities.questdb_client import TlmItem
from openc3.utilities.store import Store


WHITELIST.extend(
    [
        "tlm",
        "tlm_raw",
        "tlm_formatted",
        "tlm_with_units",  # DEPRECATED
        "set_tlm",
        "inject_tlm",
        "override_tlm",
        "get_overrides",
        "normalize_tlm",
        "get_tlm_buffer",
        "get_tlm_packet",
        "get_tlm_available",
        "get_tlm_values",
        "get_all_tlm",
        "get_all_telemetry",  # DEPRECATED
        "get_all_tlm_names",
        "get_all_telemetry_names",  # DEPRECATED
        "get_all_tlm_item_names",
        "get_tlm",
        "get_telemetry",  # DEPRECATED
        "get_item",
        "subscribe_packets",
        "get_packets",
        "get_tlm_cnt",
        "get_tlm_cnts",
        "get_packet_derived_items",
    ]
)


def tlm(*args: str, type: ValueType = "CONVERTED", cache_timeout: float = 0.1, scope: str = OPENC3_SCOPE) -> Any:
    """Request a telemetry item from a packet.

    Accepts two calling styles. Favor the first as it is more succinct::

        tlm("TGT PKT ITEM")
        tlm("TGT", "PKT", "ITEM")

    A packet name of LATEST reads the item from the packet with the latest
    packet time which contains it.

    Args:
        *args: A single "TGT PKT ITEM" string, or the target, packet and item names.
        type: Value type to return: RAW, CONVERTED (default) or FORMATTED.
        cache_timeout: Seconds a cached current value table read stays valid.
        scope: COSMOS scope.

    Returns:
        The telemetry value in the requested type.
    """
    target_name, packet_name, item_name = _tlm_process_args(args, "tlm", cache_timeout=cache_timeout, scope=scope)
    authorize(permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope)
    return CvtModel.get_item(target_name, packet_name, item_name, type, cache_timeout, scope)


def tlm_raw(*args: str, cache_timeout: float = 0.1, scope: str = OPENC3_SCOPE) -> Any:
    """Request the RAW value of a telemetry item. See `tlm` for the calling styles.

    Args:
        *args: A single "TGT PKT ITEM" string, or the target, packet and item names.
        cache_timeout: Seconds a cached current value table read stays valid.
        scope: COSMOS scope.

    Returns:
        The RAW telemetry value.
    """
    return tlm(*args, type="RAW", cache_timeout=cache_timeout, scope=scope)


def tlm_formatted(*args: str, cache_timeout: float = 0.1, scope: str = OPENC3_SCOPE) -> Any:
    """Request the FORMATTED value of a telemetry item. See `tlm` for the calling styles.

    Args:
        *args: A single "TGT PKT ITEM" string, or the target, packet and item names.
        cache_timeout: Seconds a cached current value table read stays valid.
        scope: COSMOS scope.

    Returns:
        The FORMATTED telemetry value.
    """
    return tlm(*args, type="FORMATTED", cache_timeout=cache_timeout, scope=scope)


def tlm_with_units(*args: str, cache_timeout: float = 0.1, scope: str = OPENC3_SCOPE) -> Any:
    """Request the FORMATTED value of a telemetry item.

    Deprecated: use `tlm_formatted`.

    Args:
        *args: A single "TGT PKT ITEM" string, or the target, packet and item names.
        cache_timeout: Seconds a cached current value table read stays valid.
        scope: COSMOS scope.

    Returns:
        The FORMATTED telemetry value.
    """
    return tlm(*args, type="FORMATTED", cache_timeout=cache_timeout, scope=scope)


def set_tlm(
    *args: Any, type: OverrideValueType = "CONVERTED", cache_timeout: float = 0.1, scope: str = OPENC3_SCOPE
) -> None:
    """Set a telemetry item in the current value table.

    If COSMOS is receiving telemetry for the packet, the next packet can
    overwrite this value at any time. This is best used for testing or for
    items which are not received regularly through the target interface.

    Accepts two calling styles. Favor the first as it is more succinct::

        set_tlm("TGT PKT ITEM = 1.0")
        set_tlm("TGT", "PKT", "ITEM", 10.0)

    Args:
        *args: A single "TGT PKT ITEM = value" string, or the target, packet
            and item names followed by the value.
        type: Value type to set: RAW, CONVERTED (default), FORMATTED, or ALL
            to set every value type.
        cache_timeout: Seconds a cached current value table read stays valid.
        scope: COSMOS scope.
    """
    target_name, packet_name, item_name, value = _set_tlm_process_args(
        args, "set_tlm", cache_timeout=cache_timeout, scope=scope
    )
    authorize(
        permission="tlm_set",
        target_name=target_name,
        packet_name=packet_name,
        scope=scope,
    )
    CvtModel.set_item(target_name, packet_name, item_name, value, type, scope)


def inject_tlm(
    target_name: str,
    packet_name: str,
    item_hash: dict[str, Any] | None = None,
    type: ValueType = "CONVERTED",
    stored: bool = False,
    scope: str = OPENC3_SCOPE,
    received_time: int | None = None,
) -> None:
    """Inject a packet into the system as if it was received from an interface.

    Items not in item_hash keep their current value from the current value table.

    Args:
        target_name: Target name of the packet.
        packet_name: Packet name. LATEST is not supported.
        item_hash: Item names mapped to the values to change.
        type: Value type of the item_hash values: RAW, CONVERTED (default) or FORMATTED.
        stored: Whether to flag the packet as stored (historical) telemetry.
        scope: COSMOS scope.
        received_time: Received time in nanoseconds since the Unix epoch. Defaults to now.

    Raises:
        RuntimeError: If the type is unknown or a CONVERTED value is not a valid state.
    """
    _tlm_reject_latest(str(packet_name).upper(), "inject_tlm")
    _tlm_reject_read_only(str(target_name).upper(), str(packet_name).upper(), "inject_tlm", scope)
    authorize(
        permission="tlm_set",
        target_name=target_name,
        packet_name=packet_name,
        scope=scope,
    )
    target_name = target_name.upper()
    packet_name = packet_name.upper()
    if type not in CvtModel.VALUE_TYPES:
        raise RuntimeError(f"Unknown type '{type}' for {target_name} {packet_name} (inject_tlm)")

    if item_hash:
        item_hash = {k.upper(): v for k, v in item_hash.items()}
        # Check that the items exist ... exceptions are raised if not
        items = TargetModel.packet_items(target_name, packet_name, item_hash.keys(), scope=scope)
        if type == "CONVERTED":
            # If the type is converted, check that the item states are valid
            for item_name, item_value in item_hash.items():
                item = next((i for i in items if i["name"] == item_name.upper()), None)
                if item and item.get("states") and item_value not in item["states"]:
                    raise RuntimeError(
                        f"Unknown state '{item_value}' for {item['name']}, must be one of {', '.join(item['states'].keys())}"
                    )
    else:
        # Check that the packet exists ... exceptions are raised if not
        TargetModel.packet(target_name, packet_name, scope=scope)

    # See if this target has a tlm interface
    interface_name = None
    for _, interface in InterfaceModel.all(scope).items():
        if target_name in interface["tlm_target_names"]:
            interface_name = interface["name"]
            break

    # Use an interface microservice if it exists, other use the decom microservice
    if interface_name:
        InterfaceTopic.inject_tlm(
            interface_name,
            target_name,
            packet_name,
            item_hash,
            type=type,
            stored=stored,
            scope=scope,
            received_time=received_time,
        )
    else:
        DecomInterfaceTopic.inject_tlm(
            target_name,
            packet_name,
            item_hash,
            type=type,
            stored=stored,
            scope=scope,
            received_time=received_time,
        )


def override_tlm(*args: Any, type: OverrideValueType = "ALL", scope: str = OPENC3_SCOPE) -> None:
    """Override an item in the current value table so it always returns the same value.

    The override persists when new packets are received from the target.
    Call `normalize_tlm` to remove it.

    Accepts two calling styles. Favor the first as it is more succinct::

        override_tlm("TGT PKT ITEM = 1.0")
        override_tlm("TGT", "PKT", "ITEM", 10.0)

    A packet name of LATEST overrides the item in every packet which contains it.

    Args:
        *args: A single "TGT PKT ITEM = value" string, or the target, packet
            and item names followed by the value.
        type: Value type to override: ALL (default), RAW, CONVERTED or FORMATTED.
        scope: COSMOS scope.
    """
    target_name, packet_names, item_name, value = _set_tlm_process_args_all_packets(args, "override_tlm", scope=scope)
    for packet_name in packet_names:
        authorize(permission="tlm_set", target_name=target_name, packet_name=packet_name, scope=scope)
    for packet_name in packet_names:
        CvtModel.override(target_name, packet_name, item_name, value, type=type, scope=scope)


def get_overrides(scope: str = OPENC3_SCOPE) -> list[dict[str, Any]]:
    """Return the current value table overrides set by `override_tlm`.

    Args:
        scope: COSMOS scope.

    Returns:
        One dict per override with target_name, packet_name, item_name,
        value_type and value keys.
    """
    authorize(permission="tlm", scope=scope)
    return CvtModel.overrides(scope=scope)


def normalize_tlm(*args: str, type: OverrideValueType = "ALL", scope: str = OPENC3_SCOPE) -> None:
    """Remove an override set by `override_tlm` to restore normal telemetry processing.

    Accepts two calling styles. Favor the first as it is more succinct::

        normalize_tlm("TGT PKT ITEM")
        normalize_tlm("TGT", "PKT", "ITEM")

    A packet name of LATEST normalizes the item in every packet which contains it.

    Args:
        *args: A single "TGT PKT ITEM" string, or the target, packet and item names.
        type: Value type to normalize: ALL (default), RAW, CONVERTED or FORMATTED.
        scope: COSMOS scope.
    """
    target_name, packet_names, item_name = _tlm_process_args_all_packets(args, "normalize_tlm", scope=scope)
    for packet_name in packet_names:
        authorize(permission="tlm_set", target_name=target_name, packet_name=packet_name, scope=scope)
    for packet_name in packet_names:
        CvtModel.normalize(target_name, packet_name, item_name, type=type, scope=scope)


def get_tlm_buffer(*args: str, scope: str = OPENC3_SCOPE, timeout: float = 5) -> dict[str, Any] | None:
    """Return the most recent raw buffer for a telemetry packet.

    Accepts two calling styles::

        get_tlm_buffer("TGT PKT")
        get_tlm_buffer("TGT", "PKT")

    Args:
        *args: A single "TGT PKT" string, or the target and packet names.
        scope: COSMOS scope.
        timeout: Seconds to wait for a subpacket buffer from the decom microservice.

    Returns:
        The packet message with the raw bytes under the "buffer" key, or None
        if the packet has not been received.
    """
    target_name, packet_name = _extract_target_packet_names("get_tlm_buffer", *args)
    authorize(permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope)
    model = TargetModel.packet(target_name, packet_name, scope=scope)
    if model.get("subpacket"):
        msg_hash = DecomInterfaceTopic.get_tlm_buffer(target_name, packet_name, timeout=timeout, scope=scope)
        return {k.decode(): v for (k, v) in msg_hash.items()}
    else:
        topic = f"{scope}__TELEMETRY__{{{target_name}}}__{packet_name}"
        db_shard = Store.db_shard_for_target(target_name, scope=scope)
        msg_id, msg_hash = Topic.get_newest_message(topic, db_shard=db_shard)
        if msg_id:
            # Decode the keys for user convenience
            return {k.decode(): v for (k, v) in msg_hash.items()}
    return None


def get_tlm_packet(
    *args: str, stale_time: int = 30, type: ValueType = "CONVERTED", scope: str = OPENC3_SCOPE
) -> list[list[Any]]:
    """Return all the values, along with their limits state, for a packet.

    Accepts two calling styles::

        get_tlm_packet("TGT PKT")
        get_tlm_packet("TGT", "PKT")

    Args:
        *args: A single "TGT PKT" string, or the target and packet names.
        stale_time: Seconds since the packet was received before it is marked stale.
        type: Value type to return: RAW, CONVERTED (default) or FORMATTED.
        scope: COSMOS scope.

    Returns:
        One [item name, value, limits state] list per item, where the limits
        state is a string such as "GREEN", "RED_LOW" or "STALE", or None.

    Raises:
        TypeError: If the type is unknown.
    """
    target_name, packet_name = _extract_target_packet_names("get_tlm_packet", *args)
    authorize(permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope)
    packet = TargetModel.packet(target_name, packet_name, scope=scope)
    t = _validate_tlm_type(type)
    if t is None:
        raise TypeError(f"Unknown type '{type}' for {target_name} {packet_name} (get_tlm_packet)")
    cvt_items = []
    for item in packet["items"]:
        if not item.get("hidden", False):
            cvt_items.append(item)
    cvt_items = [TlmItem(target_name, packet_name, item["name"].upper(), type) for item in cvt_items]
    # This returns an array of arrays containing the value and the limits state:
    # [[0, None], [0, 'RED_LOW'], ... ]
    current_values = CvtModel.get_tlm_values(cvt_items, stale_time=stale_time, scope=scope)
    return [[cvt_items[index].item_name, item[0], item[1]] for index, item in enumerate(current_values)]


def get_tlm_available(items: list[str], manual: bool = False, scope: str = OPENC3_SCOPE) -> list[str | None]:
    """Return the value type actually available for each requested telemetry item.

    For example an item without a format string or units requested as
    FORMATTED is available as CONVERTED or RAW. The result can be passed
    directly to `get_tlm_values`.

    Args:
        items: Items formatted as TGT__PKT__ITEM__TYPE.
        manual: Whether this is a manual request. Unused in Python.
        scope: COSMOS scope.

    Returns:
        One TGT__PKT__ITEM__TYPE string per item with the available type,
        suffixed with __LIMITS if the item has limits, or None if the item
        does not exist.

    Raises:
        ValueError: If an item is not formatted as TGT__PKT__ITEM__TYPE.
    """
    results = []
    for item in items:
        item_upcase = str(item).upper()
        try:
            target_name, orig_packet_name, item_name, value_type = item_upcase.split("__")
        except ValueError:
            raise ValueError("items must be formatted as TGT__PKT__ITEM__TYPE") from None

        packet_name = orig_packet_name
        if orig_packet_name == "LATEST":
            # A LATEST item can come from any packet containing it. Report the best value
            # type and limits of any of them since the CVT falls back to the available
            # type and historical lookups check the type available in each packet.
            # We can have a large cache_timeout of 1 because all we're trying to do is lookup a packet
            packet_name = CvtModel.determine_latest_packet_for_item(
                target_name, item_name, cache_timeout=1, scope=scope
            )
            packet_names = _tlm_packet_names(target_name, orig_packet_name, item_name, scope)
        else:
            packet_names = [packet_name]

        # Authorize every packet whose definition is read below, not just the latest one
        for name in dict.fromkeys([*packet_names, packet_name]):
            authorize(
                permission="tlm",
                target_name=target_name,
                packet_name=name,
                scope=scope,
            )

        try:
            item_configs = [TargetModel.packet_item(target_name, name, item_name, scope=scope) for name in packet_names]
            available_type = max(
                (_tlm_available_value_type(item_config, item_name, value_type) for item_config in item_configs),
                key=VALUE_TYPE_ORDER.index,
            )
            result_item = "__".join([target_name, orig_packet_name, item_name, available_type])

            # Tack on __LIMITS to notify that we have an available limits value
            if any(item_config.get("limits", {}).get("DEFAULT") for item_config in item_configs):
                result_item += "__LIMITS"

            results.append(result_item)
        except Exception:
            results.append(None)

    return results


def get_tlm_values(
    items: list[str | None],
    stale_time: int = 30,
    cache_timeout: float = 0.1,
    start_time: str | None = None,
    end_time: str | None = None,
    scope: str = OPENC3_SCOPE,
) -> Any:
    """Return the values, along with their limits state, of items from any packets.

    Items must be fully qualified with their target and packet names. A packet
    name of LATEST reads the item from the packet with the latest packet time
    which contains it.

    Args:
        items: Items formatted as TGT__PKT__ITEM__TYPE, optionally suffixed with
            __LIMITS. None entries (from `get_tlm_available`) return [None, None].
        stale_time: Seconds since the packet was received before an item is marked stale.
        cache_timeout: Seconds a cached current value table read stays valid.
        start_time: Read historical values from the time series database at
            this ISO 8601 time instead of the current values.
        end_time: With start_time, read every value up to this ISO 8601 time.
        scope: COSMOS scope.

    Returns:
        Without start_time, one [value, limits state] list per item, where the
        limits state is a string such as "GREEN", "RED_LOW" or "STALE", or None.
        With start_time, the historical rows from the time series database.

    Raises:
        TypeError: If items is not a non-empty list of strings.
        ValueError: If an item is not formatted as TGT__PKT__ITEM__TYPE.
    """
    if not isinstance(items, list) or len(items) == 0:
        raise TypeError("items must be array of strings: ['TGT__PKT__ITEM__TYPE', ...]")
    packets = []
    cvt_items = []
    # Index of each historical LATEST item in cvt_items => every packet containing the item
    latest_candidates = {}
    for item in items:
        # get_tlm_available returns None for items which don't exist and its result is
        # passed directly here, so None is a placeholder which returns a None value
        if item is None:
            cvt_items.append(TlmItem(None, None, None, None, None))
            continue
        if not isinstance(item, str):
            raise TypeError("items must be array of strings: ['TGT__PKT__ITEM__TYPE', ...]")
        # get_tlm_available tacks on __LIMITS to indicate a limits value is available
        # so accept both TGT__PKT__ITEM__TYPE and TGT__PKT__ITEM__TYPE__LIMITS
        parts = item.upper().split("__")
        if len(parts) < 4 or len(parts) > 5:
            raise ValueError("items must be formatted as TGT__PKT__ITEM__TYPE")
        target_name, packet_name, item_name, value_type = parts[0:4]
        limits = parts[4] if len(parts) == 5 else None
        if packet_name == "LATEST":
            if start_time is not None:
                # The packet received most recently now isn't necessarily the one received most
                # recently at start_time so keep every candidate packet for _tlm_latest_history
                # Each packet must be queried for the value type and limits it has or the query fails
                candidates = []
                for candidate in _tlm_packet_names(target_name, packet_name, item_name, scope):
                    packets.append([target_name, candidate])
                    candidate_item = TargetModel.packet_item(target_name, candidate, item_name, scope=scope)
                    candidate_limits = limits if limits and candidate_item.get("limits", {}).get("DEFAULT") else None
                    candidate_type = _tlm_available_value_type(candidate_item, item_name, value_type)
                    candidates.append(TlmItem(target_name, candidate, item_name, candidate_type, candidate_limits))
                latest_candidates[len(cvt_items)] = candidates
                cvt_items.append(TlmItem(target_name, packet_name, item_name, value_type, limits))
                continue
            packet_name = CvtModel.determine_latest_packet_for_item(target_name, item_name, cache_timeout, scope)
        # NOTE: limits is required by the historical (start_time) QuestDB lookup
        cvt_items.append(TlmItem(target_name, packet_name, item_name, value_type, limits))
        packets.append([target_name, packet_name])
    # Make the array of arrays unique
    packets = [list(x) for x in {tuple(x) for x in packets}]
    for name in packets:
        authorize(
            permission="tlm",
            target_name=name[0],
            packet_name=name[1],
            scope=scope,
        )
    if latest_candidates and start_time is not None:
        return _tlm_latest_history(cvt_items, latest_candidates, start_time, end_time, cache_timeout, scope)
    return CvtModel.get_tlm_values(cvt_items, stale_time, cache_timeout, start_time, end_time, scope)


def get_all_tlm(target_name: str, scope: str = OPENC3_SCOPE) -> list[dict[str, Any]]:
    """Return the definitions of all the telemetry packets in a target.

    Args:
        target_name: Name of the target.
        scope: COSMOS scope.

    Returns:
        One packet definition dict per telemetry packet.
    """
    target_name = target_name.upper()
    authorize(permission="tlm", target_name=target_name, scope=scope)
    return TargetModel.packets(target_name, type="TLM", scope=scope)


# get_all_telemetry is DEPRECATED
get_all_telemetry = get_all_tlm


def get_all_tlm_names(target_name: str, hidden: bool = False, scope: str = OPENC3_SCOPE) -> list[str]:
    """Return the names of all the telemetry packets in a target.

    Args:
        target_name: Name of the target.
        hidden: Whether to include packets marked HIDDEN.
        scope: COSMOS scope.

    Returns:
        The packet names, or an empty list if the target does not exist or
        the user is not authorized.
    """
    target_name = target_name.upper()
    # Only the names are needed so avoid parsing every packet definition
    try:
        authorize(permission="tlm", target_name=target_name, scope=scope)
        names = TargetModel.packet_names(target_name, type="TLM", scope=scope)
        if not hidden:
            hidden_names = set(TargetModel.hidden_packet_names(target_name, type="TLM", scope=scope))
            names = [name for name in names if name not in hidden_names]
    except Exception:
        names = []
    return names


def get_all_tlm_item_names(target_name: str, hidden: bool = False, scope: str = OPENC3_SCOPE) -> list[bytes]:
    """Return the names of all the telemetry items in every packet of a target.

    Args:
        target_name: Name of the target.
        hidden: Unused in Python.
        scope: COSMOS scope.

    Returns:
        The unique item names as bytes (unlike Ruby, which returns strings),
        or an empty list if the target does not exist.
    """
    authorize(permission="tlm", target_name=target_name, scope=scope)
    try:
        items = TargetModel.all_item_names(target_name, scope=scope)
    except Exception:
        items = []
    return items


# get_all_telemetry_names is DEPRECATED
get_all_telemetry_names = get_all_tlm_names


def get_tlm(*args: str, scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Return the definition of a telemetry packet.

    Accepts two calling styles::

        get_tlm("TGT PKT")
        get_tlm("TGT", "PKT")

    Args:
        *args: A single "TGT PKT" string, or the target and packet names.
        scope: COSMOS scope.

    Returns:
        The packet definition, including its items.
    """
    target_name, packet_name = _extract_target_packet_names("get_tlm", *args)
    authorize(permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope)
    return TargetModel.packet(target_name, packet_name, scope=scope)


# get_telemetry is DEPRECATED
get_telemetry = get_tlm


def get_item(*args: str, scope: str = OPENC3_SCOPE, cache_timeout: float = 0.1) -> dict[str, Any]:
    """Return the definition of a telemetry item.

    Accepts two calling styles::

        get_item("TGT PKT ITEM")
        get_item("TGT", "PKT", "ITEM")

    A packet name of LATEST returns the item from the packet with the latest
    packet time which contains it.

    Args:
        *args: A single "TGT PKT ITEM" string, or the target, packet and item names.
        scope: COSMOS scope.
        cache_timeout: Seconds a cached LATEST packet lookup stays valid.

    Returns:
        The item definition.
    """
    target_name, packet_name, item_name = _extract_target_packet_item_names("get_item", *args)
    if packet_name == "LATEST":
        packet_name = CvtModel.determine_latest_packet_for_item(
            target_name, item_name, cache_timeout=cache_timeout, scope=scope
        )
    authorize(permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope)
    return TargetModel.packet_item(target_name, packet_name, item_name, scope=scope)


# 2x double underscore since __ is reserved
SUBSCRIPTION_DELIMITER = "____"


def subscribe_packets(packets: list[list[str]], scope: str = OPENC3_SCOPE) -> str:
    """Subscribe to telemetry packets. Pass the returned ID to `get_packets`.

    Args:
        packets: [target name, packet name] pairs. LATEST is not supported.
        scope: COSMOS scope.

    Returns:
        Subscription ID to pass to `get_packets`.

    Raises:
        RuntimeError: If packets is not a nested list.
    """
    if not isinstance(packets, list) or not isinstance(packets[0], list):
        raise RuntimeError("packets must be nested array: [['TGT','PKT'],...]")

    result = {}
    for target_name, packet_name in packets:
        target_name = target_name.upper()
        packet_name = packet_name.upper()
        _tlm_reject_latest(packet_name, "subscribe_packets")
        authorize(
            permission="tlm",
            target_name=target_name,
            packet_name=packet_name,
            scope=scope,
        )
        topic = f"{scope}__DECOM__{{{target_name}}}__{packet_name}"
        db_shard = Store.db_shard_for_target(target_name, scope=scope)
        id_, _ = Topic.get_newest_message(topic, db_shard=db_shard)
        result[topic] = id_ if id_ else "0-0"

    mylist = []
    for k, v in result.items():
        mylist += [k, v]
    return SUBSCRIPTION_DELIMITER.join(mylist)


def get_packets(id: str, count: int = 1000, scope: str = OPENC3_SCOPE) -> tuple[str, list[dict[str, Any]]]:
    """Return the packets received since the last call, using an ID from `subscribe_packets`.

    Packets are ordered within each subscribed packet stream (target/packet pair)
    but are NOT interleaved by time across streams. If chronological order across
    streams is required, sort the returned list by the 'time' field. Sorting only
    orders the current batch - packets across separate get_packets calls may still
    arrive out of order, so subscribers needing global ordering must buffer and merge
    across calls.

    Args:
        id: ID returned from `subscribe_packets` or the last call to get_packets.
        count: Maximum number of packets to return from EACH packet stream.
        scope: COSMOS scope.

    Returns:
        The ID to pass to the next call, and the decommutated packets found.
    """
    authorize(permission="tlm", scope=scope)
    # Split the list of topic, ID values and turn it into a hash for easy updates
    items = id.split(SUBSCRIPTION_DELIMITER)
    # Convert it back into a dict to create a lookup
    lookup = dict(zip(items[::2], items[1::2], strict=False))
    packets = []
    # Group topics by db_shard for multi-db_shard support
    db_shard_groups = {}
    for topic, offset in lookup.items():
        target_name = Topic.target_name_from_topic(topic)
        db_shard = Store.db_shard_for_target(target_name, scope=scope)
        if db_shard not in db_shard_groups:
            db_shard_groups[db_shard] = {"topics": [], "offsets": []}
        db_shard_groups[db_shard]["topics"].append(topic)
        db_shard_groups[db_shard]["offsets"].append(offset)
    for db_shard, group in db_shard_groups.items():
        for topic, topic_id, msg_hash, _ in Topic.read_topics(
            group["topics"], group["offsets"], None, count, db_shard=db_shard
        ):
            lookup[topic] = topic_id  # save the new ID
            # decode the binary string keys and values to strings
            msg_hash = {k.decode(): v.decode() for (k, v) in msg_hash.items()}
            json_hash = json.loads(msg_hash["json_data"])
            msg_hash.pop("json_data")
            packets.append(msg_hash | json_hash)
    mylist = []
    for k, v in lookup.items():
        mylist += [k, v]
    return (SUBSCRIPTION_DELIMITER.join(mylist), packets)


def get_tlm_cnt(*args: str, scope: str = OPENC3_SCOPE) -> int:
    """Return the receive count for a telemetry packet.

    Accepts two calling styles::

        get_tlm_cnt("TGT PKT")
        get_tlm_cnt("TGT", "PKT")

    Args:
        *args: A single "TGT PKT" string, or the target and packet names.
        scope: COSMOS scope.

    Returns:
        Number of times the packet has been received.
    """
    target_name, packet_name = _extract_target_packet_names("get_tlm_cnt", *args)
    authorize(
        permission="system",
        target_name=target_name,
        packet_name=packet_name,
        scope=scope,
    )
    TargetModel.packet(target_name, packet_name, scope=scope)
    return TargetModel.get_telemetry_count(target_name, packet_name, scope=scope)


def get_tlm_cnts(target_packets: list[list[str]], scope: str = OPENC3_SCOPE) -> list[int]:
    """Return the receive counts for several telemetry packets.

    Args:
        target_packets: [target name, packet name] pairs.
        scope: COSMOS scope.

    Returns:
        The receive count of each packet, in the same order.
    """
    authorize(permission="system", scope=scope)
    return TargetModel.get_telemetry_counts(target_packets, scope=scope)


def get_packet_derived_items(*args: str, scope: str = OPENC3_SCOPE) -> list[str]:
    """Return the names of the DERIVED items in a telemetry packet.

    Accepts two calling styles::

        get_packet_derived_items("TGT PKT")
        get_packet_derived_items("TGT", "PKT")

    Args:
        *args: A single "TGT PKT" string, or the target and packet names.
        scope: COSMOS scope.

    Returns:
        The DERIVED item names.
    """
    target_name, packet_name = _extract_target_packet_names("get_packet_derived_items", *args)
    authorize(permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope)
    packet = TargetModel.packet(target_name, packet_name, scope=scope)
    return [item["name"] for item in packet["items"] if item["data_type"] == "DERIVED"]


def _extract_target_packet_names(method_name: str, *args: str):
    target_name = None
    packet_name = None
    match len(args):
        case 1:
            with contextlib.suppress(ValueError):
                # We get ValueError if passing not enough parameters
                # The check below for None handles this case
                target_name, packet_name = args[0].upper().split()
        case 2:
            target_name = args[0].upper()
            packet_name = args[1].upper()
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()")
    if target_name is None or packet_name is None:
        raise RuntimeError(
            f'ERROR: Both target name and packet name required. Usage: {method_name}("TGT PKT") or {method_name}("TGT", "PKT")'
        )
    _tlm_reject_latest(packet_name, method_name)
    return target_name, packet_name


# LATEST picks a packet per item so it can't identify a whole packet
def _tlm_reject_latest(packet_name: str, method_name: str):
    if packet_name == "LATEST":
        raise RuntimeError(f"ERROR: LATEST is not supported by {method_name}(), specify a packet name")


# <TARGET> LIMITS_GROUP of a target which defines limits groups is computed by
# the limits group microservice so it can't be written. A target without limits
# groups can still have a packet of its own named LIMITS_GROUP.
def _tlm_reject_read_only(target_name: str, packet_name: str, method_name: str, scope: str):
    if TargetModel.generated_limits_group_packet(target_name, packet_name, scope=scope):
        raise RuntimeError(f"ERROR: {target_name} {packet_name} is read-only and is not supported by {method_name}()")


def _extract_target_packet_item_names(method_name: str, *args: str):
    target_name = None
    packet_name = None
    item_name = None
    match len(args):
        case 1:
            with contextlib.suppress(ValueError):
                # Thrown when not enough items given
                target_name, packet_name, item_name = args[0].upper().split()
        case 3:
            target_name = args[0].upper()
            packet_name = args[1].upper()
            item_name = args[2].upper()
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()")
    if target_name is None or packet_name is None or item_name is None:
        raise RuntimeError(
            f'ERROR: Target name, packet name and item name required. Usage: {method_name}("TGT PKT ITEM") or {method_name}("TGT", "PKT", "ITEM")'
        )
    return target_name, packet_name, item_name


def _validate_tlm_type(tlm_type: str):
    match tlm_type:
        case "RAW":
            return ""
        case "CONVERTED":
            return "C"
        case "FORMATTED" | "WITH_UNITS":
            return "F"
    return None


def _tlm_process_args(args: tuple[str, ...], method_name: str, cache_timeout: float = 0.1, scope: str = OPENC3_SCOPE):
    target_name, packet_name, item_name = _tlm_extract_args(args, method_name)
    packet_name = _tlm_resolve_packet_name(target_name, packet_name, item_name, cache_timeout, scope)
    return target_name, packet_name, item_name


def _set_tlm_process_args(
    args: tuple[Any, ...], method_name: str, cache_timeout: float = 0.1, scope: str = OPENC3_SCOPE
):
    target_name, packet_name, item_name, value = _set_tlm_extract_args(args, method_name)
    _tlm_reject_read_only(target_name, packet_name, method_name, scope)
    packet_name = _tlm_resolve_packet_name(target_name, packet_name, item_name, cache_timeout, scope)
    return target_name, packet_name, item_name, value


# Like _tlm_process_args but returns a list of packet names where LATEST
# expands to every packet containing the item. Used by APIs which change
# an item so the change applies wherever the item appears.
def _tlm_process_args_all_packets(args: tuple[str, ...], method_name: str, scope: str = OPENC3_SCOPE):
    target_name, packet_name, item_name = _tlm_extract_args(args, method_name)
    return target_name, _tlm_packet_names(target_name, packet_name, item_name, scope), item_name


def _set_tlm_process_args_all_packets(args: tuple[Any, ...], method_name: str, scope: str = OPENC3_SCOPE):
    target_name, packet_name, item_name, value = _set_tlm_extract_args(args, method_name)
    _tlm_reject_read_only(target_name, packet_name, method_name, scope)
    return target_name, _tlm_packet_names(target_name, packet_name, item_name, scope), item_name, value


def _tlm_extract_args(args: tuple[str, ...], method_name: str):
    match len(args):
        case 1:
            target_name, packet_name, item_name = extract_fields_from_tlm_text(args[0])
        case 3:
            target_name = args[0]
            packet_name = args[1]
            item_name = args[2]
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()")
    return target_name.upper(), packet_name.upper(), item_name.upper()


def _set_tlm_extract_args(args: tuple[Any, ...], method_name: str):
    match len(args):
        case 1:
            target_name, packet_name, item_name, value = extract_fields_from_set_tlm_text(args[0])
        case 4:
            target_name = args[0]
            packet_name = args[1]
            item_name = args[2]
            value = args[3]
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()")
    return target_name.upper(), packet_name.upper(), item_name.upper(), value


# Resolve LATEST to the packet with the latest packet time containing the item
def _tlm_resolve_packet_name(
    target_name: str, packet_name: str, item_name: str, cache_timeout: float = 0.1, scope: str = OPENC3_SCOPE
):
    if packet_name == "LATEST":
        return CvtModel.determine_latest_packet_for_item(target_name, item_name, cache_timeout, scope)
    # Determine if this item exists, it will raise appropriate errors if not
    TargetModel.packet_item(target_name, packet_name, item_name, scope=scope)
    return packet_name


VALUE_TYPE_ORDER = ["RAW", "CONVERTED", "FORMATTED"]


# Returns the value type available for an item given the requested value type
def _tlm_available_value_type(item_config: dict[str, Any], item_name: str, value_type: str):
    # Must request the raw value when dealing with the reserved items
    if item_name in Packet.RESERVED_ITEM_NAMES:
        return "RAW"
    # Arrays must be accessed as RAW since there's no conversion
    if item_config.get("array_size") is not None:
        return "RAW"
    # This logic must match the logic in Packet.decom
    converted = item_config.get("states") or (
        item_config.get("read_conversion") and item_config.get("data_type") != "DERIVED"
    )
    if value_type == "FORMATTED" or value_type == "WITH_UNITS":
        if item_config.get("format_string") or item_config.get("units"):
            return "FORMATTED"
        return "CONVERTED" if converted else "RAW"
    if value_type == "CONVERTED":
        return "CONVERTED" if converted else "RAW"
    return "RAW"  # RAW or unknown


# Historical lookup where some items are LATEST. latest_candidates maps the index
# of each LATEST item in cvt_items to the item to look up in every packet which contains it.
def _tlm_latest_history(
    cvt_items: list[TlmItem],
    latest_candidates: dict[int, list[TlmItem]],
    start_time: str,
    end_time: str | None,
    cache_timeout: float,
    scope: str,
):
    regular = [index for index in range(len(cvt_items)) if index not in latest_candidates]

    # The QuestDB lookup ASOF JOINs every packet to the rows of the first, so
    # a range needs a regular item first to drive the rows. Without one keep
    # the realtime behavior of using the packet received most recently now.
    if end_time is not None and all(cvt_items[index].item_name is None for index in regular):
        resolved = []
        for index, cvt_item in enumerate(cvt_items):
            if cvt_item.packet_name == "LATEST":
                packet_name = CvtModel.determine_latest_packet_for_item(
                    cvt_item.target_name, cvt_item.item_name, cache_timeout, scope
                )
                # Use the candidate so the query asks for the value type and limits that packet has
                cvt_item = next(
                    (candidate for candidate in latest_candidates[index] if candidate.packet_name == packet_name),
                    cvt_item._replace(packet_name=packet_name),
                )
            resolved.append(cvt_item)
        return CvtModel.tsdb_lookup(resolved, start_time=start_time, end_time=end_time, scope=scope)

    # A packet without a table fails the query so skip those candidates
    packets = list(
        dict.fromkeys(
            (candidate.target_name, candidate.packet_name)
            for candidates in latest_candidates.values()
            for candidate in candidates
        )
    )
    existing = CvtModel.tsdb_packets_with_tables(packets, scope=scope)
    latest_candidates = {
        index: [candidate for candidate in candidates if (candidate.target_name, candidate.packet_name) in existing]
        for index, candidates in latest_candidates.items()
    }

    if end_time is not None:
        query = []
        query_index = {}

        def _add_query_item(query_item: TlmItem):
            if query_item not in query_index:
                query_index[query_item] = len(query)
                query.append(query_item)
            return query_index[query_item]

        # Regular items go in the query first so the first packet drives the rows
        positions: dict[int, int | list[tuple[int, int]]] = {}
        for index in regular:
            positions[index] = _add_query_item(cvt_items[index])
        for index, candidates in latest_candidates.items():
            positions[index] = [
                (
                    _add_query_item(candidate),
                    _add_query_item(
                        TlmItem(candidate.target_name, candidate.packet_name, "PACKET_TIMESECONDS", "RAW", None)
                    ),
                )
                for candidate in candidates
            ]
        rows = CvtModel.tsdb_lookup(query, start_time=start_time, end_time=end_time, scope=scope, flatten=False)
        if not isinstance(rows, list) or len(rows) == 0:
            return rows
        collapsed = []
        for row in rows:
            values = []
            for index in range(len(cvt_items)):
                position = positions[index]
                if isinstance(position, int):
                    values.append(row[position])
                else:
                    # Take the candidate with the newest packet time at this row
                    newest = _tlm_newest(
                        [(row[time_index][0], row[value_index]) for value_index, time_index in position]
                    )
                    values.append(newest or [None, None])
            collapsed.append(values)
        # Match tsdb_lookup which returns a flat array for a single row
        return collapsed[0] if len(collapsed) == 1 else collapsed

    # A point in time returns the last row of the first packet before start_time
    # with the other packets ASOF JOINed at that row. A candidate packet received
    # after that row would be missed so query each candidate packet on its own.
    found = False
    row = [[None, None] for _ in cvt_items]
    if not all(cvt_items[index].item_name is None for index in regular):
        result = CvtModel.tsdb_lookup(
            [cvt_items[index] for index in regular], start_time=start_time, scope=scope, flatten=False
        )
        if isinstance(result, list) and len(result) > 0:
            found = True
            for result_index, index in enumerate(regular):
                row[index] = result[0][result_index]
    # Group the LATEST items by candidate packet so each packet is queried once
    by_packet = {}
    for index, candidates in latest_candidates.items():
        for candidate in candidates:
            by_packet.setdefault((candidate.target_name, candidate.packet_name), {})[index] = candidate
    found_values = {}
    for (target_name, packet_name), packet_items in by_packet.items():
        query = list(dict.fromkeys(packet_items.values()))
        query.append(TlmItem(target_name, packet_name, "PACKET_TIMESECONDS", "RAW", None))
        result = CvtModel.tsdb_lookup(query, start_time=start_time, scope=scope, flatten=False)
        if not isinstance(result, list) or len(result) == 0:
            continue
        values = result[0]
        for index, query_item in packet_items.items():
            found_values.setdefault(index, []).append((values[-1][0], values[query.index(query_item)]))
    for index, candidates in found_values.items():
        value = _tlm_newest(candidates)
        if value is None:
            continue
        found = True
        row[index] = value
    return row if found else {}


# Return the value with the newest time from (time, value) pairs, or None
def _tlm_newest(candidates: list[tuple[Any, Any]]):
    candidates = [candidate for candidate in candidates if candidate[0] is not None]
    if not candidates:
        return None
    return max(candidates, key=lambda candidate: candidate[0])[1]


# Expand LATEST to every packet containing the item
def _tlm_packet_names(target_name: str, packet_name: str, item_name: str, scope: str = OPENC3_SCOPE):
    if packet_name == "LATEST":
        packet_names = TargetModel.get_item_to_packet_map(target_name, scope=scope).get(item_name)
        if packet_names is None:
            raise RuntimeError(f"Item '{target_name} LATEST {item_name}' does not exist for scope: {scope}")
        return packet_names
    # Determine if this item exists, it will raise appropriate errors if not
    TargetModel.packet_item(target_name, packet_name, item_name, scope=scope)
    return [packet_name]
