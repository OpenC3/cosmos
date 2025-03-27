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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
import time
from typing import Any

from openc3.utilities.store import Store
from openc3.utilities.store_queued import StoreQueued
from openc3.models.model import Model
from openc3.models.target_model import TargetModel
from openc3.environment import OPENC3_SCOPE
from openc3.utilities.json import JsonEncoder, JsonDecoder


class CvtModel(Model):
    packet_cache = {}
    override_cache = {}

    VALUE_TYPES = {"RAW", "CONVERTED", "FORMATTED", "WITH_UNITS"}

    @classmethod
    def build_json_from_packet(cls, packet):
        return packet.decom()

    @classmethod
    def delete(cls, target_name: str, packet_name: str, scope: str = OPENC3_SCOPE):
        """Delete the current value table for a target"""
        key = f"{scope}__tlm__{target_name}"
        tgt_pkt_key = key + f"__{packet_name}"
        CvtModel.packet_cache[tgt_pkt_key] = None
        Store.hdel(key, packet_name)

    @classmethod
    def set(cls, hash: dict, target_name: str, packet_name: str, queued: bool = False, scope: str = OPENC3_SCOPE):
        """Set the current value table for a target, packet"""
        packet_json = json.dumps(hash, cls=JsonEncoder)
        key = f"{scope}__tlm__{target_name}"
        tgt_pkt_key = key + f"__{packet_name}"
        CvtModel.packet_cache[tgt_pkt_key] = [time.time(), hash]
        if queued:
            StoreQueued.hset(key, packet_name, packet_json)
        else:
            Store.hset(key, packet_name, packet_json)

    # Get the dict for packet in the CVT
    # Note: Does not apply overrides
    @classmethod
    def get(cls, target_name: str, packet_name: str, cache_timeout: float = 0.1, scope: str = OPENC3_SCOPE):
        key = f"{scope}__tlm__{target_name}"
        tgt_pkt_key = key + f"__{packet_name}"
        now = time.time()
        if tgt_pkt_key in CvtModel.packet_cache:
            cache_time, pkt_hash = CvtModel.packet_cache[tgt_pkt_key]
            if (now - cache_time) < cache_timeout:
                return pkt_hash
        packet = Store.hget(key, packet_name)
        if packet is None:
            raise RuntimeError(f"Packet '{target_name} {packet_name}' does not exist")
        pkt_hash = json.loads(packet, cls=JsonDecoder)
        CvtModel.packet_cache[tgt_pkt_key] = [now, pkt_hash]
        return pkt_hash

    # Set an item in the current value table
    @classmethod
    def set_item(
        cls,
        target_name: str,
        packet_name: str,
        item_name: str,
        value: Any,
        type: str,
        queued: bool = False,
        scope: str = OPENC3_SCOPE,
    ):
        pkt_hash = cls.get(target_name, packet_name, cache_timeout=0.0, scope=scope)
        match type:
            case "WITH_UNITS":
                pkt_hash[f"{item_name}__U"] = str(value)  # WITH_UNITS should always be a string
            case "FORMATTED":
                pkt_hash[f"{item_name}__F"] = str(value)  # FORMATTED should always be a string
            case "CONVERTED":
                pkt_hash[f"{item_name}__C"] = value
            case "RAW":
                pkt_hash[item_name] = value
            case "ALL":
                pkt_hash[f"{item_name}__U"] = str(value)  # WITH_UNITS should always be a string
                pkt_hash[f"{item_name}__F"] = str(value)  # FORMATTED should always be a string
                pkt_hash[f"{item_name}__C"] = value
                pkt_hash[item_name] = value
            case _:
                raise RuntimeError(f"Unknown type '{type}' for {target_name} {packet_name} {item_name}")
        cls.set(pkt_hash, target_name=target_name, packet_name=packet_name, queued=queued, scope=scope)

    # Get an item from the current value table
    @classmethod
    def get_item(
        cls,
        target_name,
        packet_name,
        item_name,
        type,
        cache_timeout=0.1,
        scope=OPENC3_SCOPE,
    ):
        result, types = cls._handle_item_override(
            target_name,
            packet_name,
            item_name,
            type=type,
            cache_timeout=cache_timeout,
            scope=scope,
        )
        if result is not None:
            return result
        pkt_hash = cls.get(target_name, packet_name, scope=scope)
        for cvt_value in [pkt_hash[x] for x in types if x in pkt_hash]:
            if cvt_value is not None:
                if type == "FORMATTED" or type == "WITH_UNITS":
                    return str(cvt_value)
                return cvt_value
        # RECEIVED_COUNT is a special case where it is 0 if it doesn't exist
        # This allows scripts to check against the value to see if the packet was ever received
        if item_name == "RECEIVED_COUNT":
            return 0
        else:
            return None

    # Return all item values and limit state from the CVT
    #
    # @param items [Array<String>] Items to return. Must be formatted as TGT__PKT__ITEM__TYPE
    # @param stale_time [Integer] Time in seconds from Time.now that value will be marked stale
    # @return [Array] Array of values
    @classmethod
    def get_tlm_values(cls, items: list, stale_time: int = 30, cache_timeout: float = 0.1, scope: str = OPENC3_SCOPE):
        now = time.time()
        results = []
        lookups = []
        packet_lookup = {}
        overrides = {}
        # First generate a lookup dict of all the items represented so we can query the CVT
        for item in items:
            cls._parse_item(now, lookups, overrides, item, cache_timeout=cache_timeout, scope=scope)

        for target_packet_key, target_name, packet_name, value_keys in lookups:
            if target_packet_key not in packet_lookup:
                packet_lookup[target_packet_key] = cls.get(
                    target_name,
                    packet_name,
                    cache_timeout,
                    scope,
                )
            pkt_hash = packet_lookup[target_packet_key]
            item_result = []
            if isinstance(value_keys, dict):  # Set in _parse_item to indicate override
                item_result.insert(0, value_keys["value"])
            else:
                for key in value_keys:
                    if key in pkt_hash:
                        item_result.insert(0, pkt_hash[key])
                        break  # We want the first value
                # If we were able to find a value, try to get the limits state
                if len(item_result) > 0 and item_result[0] is not None:
                    if now - pkt_hash["RECEIVED_TIMESECONDS"] > stale_time:
                        item_result.insert(1, "STALE")
                    else:
                        # The last key is simply the name (RAW) so we can append __L
                        # If there is no limits then it returns None which is acceptable
                        item_result.insert(1, pkt_hash.get(f"{value_keys[-1]}__L"))
                else:
                    if value_keys[-1] not in pkt_hash:
                        raise RuntimeError(f"Item '{target_name} {packet_name} {value_keys[-1]}' does not exist")
                    else:
                        item_result.insert(1, None)
            results.append(item_result)
        return results

    @classmethod
    def overrides(cls, scope=OPENC3_SCOPE):
        """Return all the overrides"""
        overrides = []
        for target_name in TargetModel.names(scope):
            all = Store.hgetall(f"{scope}__override__{target_name}")
            if len(all) == 0:
                continue
            # decode the binary string keys to strings
            all = {k.decode(): v for (k, v) in all.items()}
            for packet_name, pkt_hash in all.items():
                items = json.loads(pkt_hash, cls=JsonDecoder)
                for key, value in items.items():
                    item = {}
                    item["target_name"] = target_name
                    item["packet_name"] = packet_name
                    if "__" in key:
                        item_name, value_type_key = key.split("__")
                    else:  # RAW item which doesn't have an underscore
                        item_name = key
                        value_type_key = "R"
                    item["item_name"] = item_name
                    match value_type_key:
                        case "U":
                            item["value_type"] = "WITH_UNITS"
                        case "F":
                            item["value_type"] = "FORMATTED"
                        case "C":
                            item["value_type"] = "CONVERTED"
                        case "R":
                            item["value_type"] = "RAW"
                    item["value"] = value
                    overrides.append(item)
        return overrides

    @classmethod
    def override(cls, target_name, packet_name, item_name, value, type="ALL", scope=OPENC3_SCOPE):
        """Override a current value table item such that it always returns the same value for the given type"""
        pkt_hash = Store.hget(f"{scope}__override__{target_name}", packet_name)
        if pkt_hash is not None:
            pkt_hash = json.loads(pkt_hash)
        else:
            pkt_hash = {}
        match type:
            case "ALL":
                pkt_hash[item_name] = value
                pkt_hash[f"{item_name}__C"] = value
                pkt_hash[f"{item_name}__F"] = str(value)
                pkt_hash[f"{item_name}__U"] = str(value)
            case "RAW":
                pkt_hash[item_name] = value
            case "CONVERTED":
                pkt_hash[f"{item_name}__C"] = value
            case "FORMATTED":
                pkt_hash[f"{item_name}__F"] = str(value)  # Always a String
            case "WITH_UNITS":
                pkt_hash[f"{item_name}__U"] = str(value)  # Always a String
            case _:
                raise RuntimeError(f"Unknown type '{type}' for {target_name} {packet_name} {item_name}")
        tgt_pkt_key = f"{scope}__tlm__{target_name}__{packet_name}"
        CvtModel.override_cache[tgt_pkt_key] = [time.time(), pkt_hash]
        Store.hset(f"{scope}__override__{target_name}", packet_name, json.dumps(pkt_hash))

    # Normalize a current value table item such that it returns the actual value
    @classmethod
    def normalize(cls, target_name, packet_name, item_name, type="ALL", scope=OPENC3_SCOPE):
        pkt_hash = Store.hget(f"{scope}__override__{target_name}", packet_name)
        if pkt_hash is not None:
            pkt_hash = json.loads(pkt_hash)
        else:
            pkt_hash = {}
        match type:
            case "ALL":
                pkt_hash.pop(item_name, None)
                pkt_hash.pop(f"{item_name}__C", None)
                pkt_hash.pop(f"{item_name}__F", None)
                pkt_hash.pop(f"{item_name}__U", None)
            case "RAW":
                if item_name in pkt_hash:
                    pkt_hash.pop(item_name)
            case "CONVERTED":
                if f"{item_name}__C" in pkt_hash:
                    pkt_hash.pop(f"{item_name}__C")
            case "FORMATTED":
                if f"{item_name}__F" in pkt_hash:
                    pkt_hash.pop(f"{item_name}__F")
            case "WITH_UNITS":
                if f"{item_name}__U" in pkt_hash:
                    pkt_hash.pop(f"{item_name}__U")
            case _:
                raise RuntimeError(f"Unknown type '{type}' for {target_name} {packet_name} {item_name}")
        tgt_pkt_key = f"{scope}__tlm__{target_name}__{packet_name}"
        if len(pkt_hash) == 0:
            if tgt_pkt_key in CvtModel.override_cache:
                CvtModel.override_cache.pop(tgt_pkt_key)
            Store.hdel(f"{scope}__override__{target_name}", packet_name)
        else:
            CvtModel.override_cache[tgt_pkt_key] = [time.time(), pkt_hash]
            Store.hset(f"{scope}__override__{target_name}", packet_name, json.dumps(pkt_hash))

    @classmethod
    def determine_latest_packet_for_item(cls, target_name, item_name, cache_timeout=0.1, scope=OPENC3_SCOPE):
        item_map = TargetModel.get_item_to_packet_map(target_name, scope=scope)
        packet_names = item_map.get(item_name)
        if packet_names is None:
            raise RuntimeError(f"Item '{target_name} LATEST {item_name}' does not exist for scope: {scope}")

        latest = -1
        latest_packet_name = None
        for packet_name in packet_names:
            pkt_hash = cls.get(
                target_name,
                packet_name,
                cache_timeout,
                scope,
            )
            if pkt_hash["PACKET_TIMESECONDS"] and pkt_hash["PACKET_TIMESECONDS"] > latest:
                latest = pkt_hash["PACKET_TIMESECONDS"]
                latest_packet_name = packet_name
        if latest == -1:
            raise RuntimeError(f"Item '{target_name} LATEST {item_name}' does not exist for scope: {scope}")
        return latest_packet_name

    @classmethod
    def _handle_item_override(
        cls,
        target_name,
        packet_name,
        item_name,
        type,
        cache_timeout,
        scope=OPENC3_SCOPE,
    ):
        override_key = item_name
        types = []
        match type:
            case "WITH_UNITS":
                types = [
                    f"{item_name}__U",
                    f"{item_name}__F",
                    f"{item_name}__C",
                    item_name,
                ]
                override_key = f"{item_name}__U"
            case "FORMATTED":
                types = [f"{item_name}__F", f"{item_name}__C", item_name]
                override_key = f"{item_name}__F"
            case "CONVERTED":
                types = [f"{item_name}__C", item_name]
                override_key = f"{item_name}__C"
            case "RAW":
                types = [item_name]
            case _:
                raise RuntimeError(f"Unknown type '{type}' for {target_name} {packet_name} {item_name}")

        tgt_pkt_key = f"{scope}__tlm__{target_name}__{packet_name}"
        overrides = cls._get_overrides(
            time.time(),
            tgt_pkt_key,
            {},
            target_name,
            packet_name,
            cache_timeout=cache_timeout,
            scope=scope,
        )
        result = overrides.get(override_key)
        if result is not None:
            return result, types
        return None, types

    @classmethod
    def _get_overrides(cls, now, tgt_pkt_key, overrides, target_name, packet_name, cache_timeout, scope):
        if tgt_pkt_key in CvtModel.override_cache:
            cache_time, pkt_hash = CvtModel.override_cache[tgt_pkt_key]
            if (now - cache_time) < cache_timeout:
                overrides[tgt_pkt_key] = pkt_hash
                return pkt_hash
        override_data = Store.hget(f"{scope}__override__{target_name}", packet_name)
        if override_data is not None:
            pkt_hash = json.loads(override_data)
            overrides[tgt_pkt_key] = pkt_hash
        else:
            pkt_hash = {}
            overrides[tgt_pkt_key] = {}
        CvtModel.override_cache[tgt_pkt_key] = [now, pkt_hash]  # always update
        return pkt_hash

    # parse item and update lookups with packet_name and target_name and keys
    # return an ordered array of dict with keys
    @classmethod
    def _parse_item(cls, now, lookups, overrides, item, cache_timeout, scope):
        target_name, packet_name, item_name, value_type = item

        # We build lookup keys by including all the less formatted types to gracefully degrade lookups
        # This allows the user to specify WITH_UNITS and if there is no conversions it will simply return the RAW value
        match str(value_type):
            case "RAW":
                keys = [item_name]
            case "CONVERTED":
                keys = [f"{item_name}__C", item_name]
            case "FORMATTED":
                keys = [f"{item_name}__F", f"{item_name}__C", item_name]
            case "WITH_UNITS":
                keys = [
                    f"{item_name}__U",
                    f"{item_name}__F",
                    f"{item_name}__C",
                    item_name,
                ]
            case _:
                raise ValueError(f"Unknown value type '{value_type}'")

        # Check the overrides cache for this target / packet
        tgt_pkt_key = f"{scope}__tlm__{target_name}__{packet_name}"
        if tgt_pkt_key not in overrides:
            cls._get_overrides(
                now,
                tgt_pkt_key,
                overrides,
                target_name,
                packet_name,
                cache_timeout=cache_timeout,
                scope=scope,
            )

        # Set the result as a Hash to distinguish it from the key array and from an overridden Array value
        if tgt_pkt_key in overrides and keys[0] in overrides[tgt_pkt_key]:
            keys = {"value": overrides[tgt_pkt_key][keys[0]]}

        lookups.append([tgt_pkt_key, target_name, packet_name, keys])
