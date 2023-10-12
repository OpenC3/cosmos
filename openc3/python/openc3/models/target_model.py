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

import json
import time
from openc3.models.model import Model
from openc3.utilities.store import Store
from openc3.environment import OPENC3_SCOPE


# Manages the target in Redis. It stores the target itself under the
# <SCOPE>__openc3_targets key under the target name field. All the command packets
# in the target are stored under the <SCOPE>__openc3cmd__<TARGET NAME> key and the
# telemetry under the <SCOPE>__openc3tlm__<TARGET NAME> key. Any new limits sets
# are merged into the <SCOPE>__limits_sets key as fields. Any new limits groups are
# created under <SCOPE>__limits_groups with field name. These Redis key/fields are
# all removed when the undeploy method is called.
class TargetModel(Model):
    PRIMARY_KEY = "openc3_targets"
    VALID_TYPES = ["CMD", "TLM"]
    ITEM_MAP_CACHE_TIMEOUT = 10.0
    item_map_cache = {}

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name, scope):
        return super().get(f"{scope}__{TargetModel.PRIMARY_KEY}", name)

    @classmethod
    def names(cls, scope):
        return super().names(f"{scope}__{TargetModel.PRIMARY_KEY}")

    @classmethod
    def all(cls, scope):
        return super().all(f"{scope}__{TargetModel.PRIMARY_KEY}")

    @classmethod
    def packet_names(cls, target_name, type="TLM", scope=OPENC3_SCOPE):
        """@return [Array] Array of all the packet names"""
        if type not in cls.VALID_TYPES:
            raise RuntimeError(f"Unknown type {type} for {target_name}")
        # If the key doesn't exist or if there are no packets we return empty array
        names = Store.hkeys(f"{scope}__openc3{type.lower()}__{target_name}")
        names = [name.decode() for name in names]
        names.sort()
        return names

    @classmethod
    def packet(cls, target_name, packet_name, type="TLM", scope=OPENC3_SCOPE):
        """@return [Hash] Packet hash or raises an exception"""
        if type not in cls.VALID_TYPES:
            raise RuntimeError(f"Unknown type {type} for {target_name} {packet_name}")

        # Assume it exists and just try to get it to avoid an extra call to Store.exist?
        json_data = Store.hget(
            f"{scope}__openc3{type.lower()}__{target_name}", packet_name
        )
        if not json_data:
            raise RuntimeError(f"Packet '{target_name} {packet_name}' does not exist")
        return json.loads(json_data)

    @classmethod
    def packets(cls, target_name, type="TLM", scope=OPENC3_SCOPE):
        """@return [Array>Hash>] All packet hashes under the target_name"""
        if type not in cls.VALID_TYPES:
            raise RuntimeError(f"Unknown type {type} for {target_name}")
        if not cls.get(name=target_name, scope=scope):
            raise RuntimeError(f"Target '{target_name}' does not exist")

        result = []
        packets = Store.hgetall(f"{scope}__openc3{type.lower()}__{target_name}")
        for _, packet_json in packets.items():
            result.append(json.loads(packet_json))
        return result

    @classmethod
    def packet_item(
        cls, target_name, packet_name, item_name, type="TLM", scope=OPENC3_SCOPE
    ):
        """@return [Hash] Item hash or raises an exception"""
        packet = cls.packet(target_name, packet_name, type=type, scope=scope)
        found = None
        for item in packet["items"]:
            if item["name"] == item_name:
                found = item
                break
        if not found:
            raise RuntimeError(
                f"Item '{packet['target_name']} {packet['packet_name']} {item_name}' does not exist"
            )
        return found

    # @return [Array<Hash>] Item hash array or raises an exception
    @classmethod
    def packet_items(
        cls, target_name, packet_name, items, type="TLM", scope=OPENC3_SCOPE
    ):
        packet = cls.packet(target_name, packet_name, type=type, scope=scope)
        found = []
        for item in packet["items"]:
            if item["name"] in items:
                found.append(item)
        #   found = packet['items'].find_all { |item| items.map(&:to_s).include?(item['name']) }
        if len(found) != len(items):  # we didn't find them all
            found_items = [item["name"] for item in found]
            not_found = []
            for item in items - found_items:
                not_found.append(f"'{target_name} {packet_name} {item}'")
            # 'does not exist' not gramatically correct but we use it in every other exception
            raise RuntimeError(f"Item(s) {', '.join(not_found)} does not exist")
        return found

    @classmethod
    def get_item_to_packet_map(cls, target_name, scope=OPENC3_SCOPE):
        if target_name in TargetModel.item_map_cache:
            cache_time, item_map = TargetModel.item_map_cache[target_name]
            if (time.time() - cache_time) < TargetModel.ITEM_MAP_CACHE_TIMEOUT:
                return item_map
        item_map_key = f"{scope}__{target_name}__item_to_packet_map"
        target_name = target_name.upper()
        json_data = Store.get(item_map_key)
        if json_data:
            item_map = json.loads(json_data)
        else:
            item_map = cls.build_item_to_packet_map(target_name, scope=scope)
            Store.set(item_map_key, json.dumps(item_map))
        TargetModel.item_map_cache[target_name] = [time.time(), item_map]
        return item_map

    @classmethod
    def build_item_to_packet_map(cls, target_name, scope=OPENC3_SCOPE):
        item_map = {}
        for packet in cls.packets(target_name, scope=scope):
            items = packet["items"]
            for item in items:
                item_name = item["name"]
                if item_map.get(item_name) is None:
                    item_map[item_name] = []
                item_map[item_name].append(packet["packet_name"])
        return item_map

    # TODO: Not nearly complete ... see target_model.rb
    def __init__(
        self, name, folder_name=None, updated_at=None, plugin=None, scope=OPENC3_SCOPE
    ):
        super().__init__(
            f"{scope}__{self.PRIMARY_KEY}",
            name=name,
            plugin=plugin,
            updated_at=updated_at,
            scope=scope,
        )
        self.folder_name = folder_name
