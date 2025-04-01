# Copyright 2025 OpenC3, Inc.
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
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1953 and https://github.com/OpenC3/cosmos/pull/1963

# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1957

import json
import time
from typing import Any
from datetime import datetime, timezone
from openc3.environment import OPENC3_SCOPE
from openc3.topics.topic import Topic
from openc3.models.model import Model
from openc3.models.microservice_model import MicroserviceModel
from openc3.utilities.json import JsonEncoder
from openc3.utilities.store import Store
from openc3.utilities.logger import Logger
from openc3.utilities.bucket import Bucket
from openc3.environment import OPENC3_CONFIG_BUCKET


# Manages the target in Redis. It stores the target itself under the
# <SCOPE>__openc3_targets key under the target name field. All the command packets
# in the target are stored under the <SCOPE>__openc3cmd__<TARGET NAME> key and the
# telemetry under the <SCOPE>__openc3tlm__<TARGET NAME> key. Any new limits sets
# are merged into the <SCOPE>__limits_sets key as fields. Any new limits groups are
# created under <SCOPE>__limits_groups with field name. These Redis key/fields are
# all removed when the undeploy method is called.
class TargetModel(Model):
    PRIMARY_KEY = "openc3_targets"
    VALID_TYPES = {"CMD", "TLM"}
    ITEM_MAP_CACHE_TIMEOUT = 10.0
    item_map_cache = {}

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name: str, scope: str):
        return super().get(f"{scope}__{TargetModel.PRIMARY_KEY}", name)

    @classmethod
    def names(cls, scope: str):
        return super().names(f"{scope}__{TargetModel.PRIMARY_KEY}")

    @classmethod
    def all(cls, scope: str):
        return super().all(f"{scope}__{TargetModel.PRIMARY_KEY}")

    @classmethod
    def packet(
        cls,
        target_name: str,
        packet_name: str,
        type: str = "TLM",
        scope: str = OPENC3_SCOPE,
    ):
        """@return [Hash] Packet hash or raises an exception"""
        if type not in cls.VALID_TYPES:
            raise RuntimeError(f"Unknown type {type} for {target_name} {packet_name}")

        # Assume it exists and just try to get it to avoid an extra call to Store.exist?
        json_data = Store.hget(f"{scope}__openc3{type.lower()}__{target_name}", packet_name)
        if not json_data:
            raise RuntimeError(f"Packet '{target_name} {packet_name}' does not exist")
        return json.loads(json_data)

    @classmethod
    def packets(cls, target_name: str, type: str = "TLM", scope: str = OPENC3_SCOPE):
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
    def set_packet(
        cls,
        target_name: str,
        packet_name: str,
        packet: Any,
        type: str = "TLM",
        scope: str = OPENC3_SCOPE,
    ):
        if type not in cls.VALID_TYPES:
            raise RuntimeError(f"Unknown type {type} for {target_name} {packet_name}")

        try:
            Store.hset(
                f"{scope}__openc3{type.lower()}__{target_name}",
                packet_name,
                json.dumps(packet),
            )
        except (TypeError, RuntimeError) as error:
            Logger.error(f"Invalid text present in {target_name} {packet_name} {type.lower()} packet")
            raise error

    @classmethod
    def packet_item(
        cls,
        target_name: str,
        packet_name: str,
        item_name,
        type: str = "TLM",
        scope: str = OPENC3_SCOPE,
    ):
        """@return [Hash] Item hash or raises an exception"""
        packet = cls.packet(target_name, packet_name, type=type, scope=scope)
        found = None
        for item in packet["items"]:
            if item["name"] == item_name:
                found = item
                break
        if not found:
            raise RuntimeError(f"Item '{packet['target_name']} {packet['packet_name']} {item_name}' does not exist")
        return found

    # @return [Array<Hash>] Item hash array or raises an exception
    @classmethod
    def packet_items(
        cls,
        target_name: str,
        packet_name: str,
        items: Any,
        type: str = "TLM",
        scope: str = OPENC3_SCOPE,
    ):
        packet = cls.packet(target_name, packet_name, type=type, scope=scope)
        found = []
        for item in packet["items"]:
            if item["name"] in items:
                found.append(item)
        if len(found) != len(items):  # we didn't find them all
            found_items = [item["name"] for item in found]
            not_found = []
            for item in list(set(items) - set(found_items)):
                not_found.append(f"'{target_name} {packet_name} {item}'")
            # 'does not exist' not grammatically correct but we use it in every other exception
            raise RuntimeError(f"Item(s) {', '.join(not_found)} does not exist")
        return found

    # @return [List<String>] All the item names for every packet in a target
    @classmethod
    def all_item_names(cls, target_name: str, type: str = "TLM", scope: str = OPENC3_SCOPE):
        items = Store.zrange(f"{scope}__openc3tlm__{target_name}__allitems", 0, -1)
        if not items:
            items = cls.rebuild_target_allitems_list(target_name, type=type, scope=scope)
        return items

    @classmethod
    def rebuild_target_allitems_list(cls, target_name: str, type: str = "TLM", scope: str = OPENC3_SCOPE):
        for packet in cls.packets(target_name, scope=scope):
            for item in packet["items"]:
                cls.add_to_target_allitems_list(target_name, item["name"], scope=scope)
        return Store.zrange(f"{scope}__openc3tlm__{target_name}__allitems", 0, -1) # return the new sorted set to let redis do the sorting

    @classmethod
    def add_to_target_allitems_list(cls, target_name: str, item_name: str, scope: str = OPENC3_SCOPE):
        score = 0 # https://redis.io/docs/latest/develop/data-types/sorted-sets/#lexicographical-scores
        Store.zadd(f"{scope}__openc3tlm__{target_name}__allitems", score, item_name)

    # @return [Hash{String => Array<Array<String, String, String>>}]
    @classmethod
    def limits_groups(cls, scope: str = OPENC3_SCOPE):
        groups = Store.hgetall(f"{scope}__limits_groups")
        if groups:
            return {k.decode(): json.loads(v) for (k, v) in groups.items()}
        else:
            return {}

    @classmethod
    def get_item_to_packet_map(cls, target_name: str, scope: str = OPENC3_SCOPE):
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
    def build_item_to_packet_map(cls, target_name: str, scope: str = OPENC3_SCOPE):
        item_map = {}
        for packet in cls.packets(target_name, scope=scope):
            items = packet["items"]
            for item in items:
                item_name = item["name"]
                if item_map.get(item_name) is None:
                    item_map[item_name] = []
                item_map[item_name].append(packet["packet_name"])
        return item_map


    @classmethod
    def increment_telemetry_count(cls, target_name: str, packet_name: str, count: int, scope: str = OPENC3_SCOPE):
        result = Store.hincrby(f"{scope}__TELEMETRYCNTS__{{{target_name}}}", packet_name, count)
        if isinstance(result, (bytes, bytearray)):
            return int(result)
        else:
            return result


    @classmethod
    def get_all_telemetry_counts(cls, target_name: str, scope: str = OPENC3_SCOPE):
        result = {}
        get_all = Store.hgetall(f"{scope}__TELEMETRYCNTS__{{{target_name}}}")
        if get_all is dict:
            for key, value in get_all.items():
                result[key] = int(value)
            return result
        else:
            return get_all

    @classmethod
    def get_telemetry_count(cls, target_name: str, packet_name: str, scope: str = OPENC3_SCOPE):
        value = Store.hget(f"{scope}__TELEMETRYCNTS__{{{target_name}}}", packet_name)
        if value is None:
            return 0
        elif isinstance(value, (bytes, bytearray)):
            return int(value)
        else:
            return value

    @classmethod
    def get_telemetry_counts(cls, target_packets: list, scope: str = OPENC3_SCOPE):
        result = []
        with Store.instance().redis_pool.get() as redis:
            pipeline = redis.pipeline(transaction=False)
            for target_name, packet_name in target_packets:
                target_name = target_name.upper()
                packet_name = packet_name.upper()
                pipeline.hget(f"{scope}__TELEMETRYCNTS__{{{target_name}}}", packet_name)
            result = pipeline.execute()

        counts = []
        for count in result:
            if count is None:
                counts.append(0)
            else:
                counts.append(int(count))
        return counts

    @classmethod
    def increment_command_count(cls, target_name: str, packet_name: str , count: int, scope: str = OPENC3_SCOPE):
        result = Store.hincrby(f"{scope}__COMMANDCNTS__{{{target_name}}}", packet_name, count)
        if isinstance(result, (bytes, bytearray)):
            return int(result)
        else:
            return result

    @classmethod
    def get_all_command_counts(cls, target_name: str, scope: str = OPENC3_SCOPE):
        result = {}
        get_all = Store.hgetall(f"{scope}__COMMANDCNTS__{{{target_name}}}")
        if get_all is dict:
            for key, value in get_all.items():
                result[key] = int(value)
            return result
        else:
            return get_all

    @classmethod
    def get_command_count(cls, target_name: str, packet_name: str, scope: str = OPENC3_SCOPE):
        value = Store.hget(f"{scope}__COMMANDCNTS__{{{target_name}}}", packet_name)
        if value is None:
            return 0
        elif isinstance(value, (bytes, bytearray)):
            return int(value)
        else:
            return value

    @classmethod
    def get_command_counts(cls, target_packets: list, scope: str = OPENC3_SCOPE):
        result = []
        with Store.instance().redis_pool.get() as redis:
            pipeline = redis.pipeline(transaction=False)
            for target_name, packet_name in target_packets:
                target_name = target_name.upper()
                packet_name = packet_name.upper()
                pipeline.hget(f"{scope}__COMMANDCNTS__{{{target_name}}}", packet_name)
            result = pipeline.execute()

        counts = []
        for count in result:
            if count is None:
                counts.append(0)
            else:
                counts.append(int(count))
        return counts


    # Most of these parameters are unused but they must match the Ruby implementation
    # so we can call TargetModel.get_model which calls Model.get_model which does
    #   json_data = cls.get(name, scope)
    #   return cls.from_json(json_data, scope)
    # cls.from_json calls cls(**json_data) which is the constructor which takes
    # all the keyword arguments from the json_data which were set during installation
    # by the Ruby code
    def __init__(
        self,
        name: str,
        folder_name=None,
        requires=[],
        ignored_parameters=[],
        ignored_items=[],
        limits_groups=[],
        cmd_tlm_files=[],
        cmd_unique_id_mode=False,
        tlm_unique_id_mode=False,
        id=None,
        updated_at=None,
        plugin=None,
        cmd_buffer_depth=5,
        cmd_log_cycle_time=600,
        cmd_log_cycle_size=50_000_000,
        cmd_log_retain_time=None,
        cmd_decom_log_cycle_time=600,
        cmd_decom_log_cycle_size=50_000_000,
        cmd_decom_log_retain_time=None,
        tlm_buffer_depth=60,
        tlm_log_cycle_time=600,
        tlm_log_cycle_size=50_000_000,
        tlm_log_retain_time=None,
        tlm_decom_log_cycle_time=600,
        tlm_decom_log_cycle_size=50_000_000,
        tlm_decom_log_retain_time=None,
        reduced_minute_log_retain_time=None,
        reduced_hour_log_retain_time=None,
        reduced_day_log_retain_time=None,
        cleanup_poll_time=600,
        needs_dependencies=False,
        target_microservices={"REDUCER": [[]]},
        reducer_disable=False,
        reducer_max_cpu_utilization=30.0,
        disable_erb=None,
        shard=0,
        scope: str = OPENC3_SCOPE,
    ):
        super().__init__(
            f"{scope}__{self.PRIMARY_KEY}",
            name=name,
            updated_at=updated_at,
            plugin=plugin,
            scope=scope,
        )

    def update_store_telemetry(self, packet_hash, clear_old=True):
        for target_name, packets in packet_hash.items():
            if clear_old:
                Store.delete(f"{self.scope}__openc3tlm__{target_name}")
                Store.delete(f"{self.scope}__openc3tlm__{target_name}__allitems")
            for packet_name, packet in packets.items():
                Logger.debug(f"Configuring tlm packet= {target_name} {packet_name}")
                try:
                    Store.hset(f"{self.scope}__openc3tlm__{target_name}", packet_name, json.dumps(packet.as_json()))
                except Exception as e:
                    Logger.error(f"Invalid text present in {target_name} {packet_name} tlm packet")
                    raise e
                json_hash = {}
                for item in packet.sorted_items:
                    json_hash[item.name] = None
                    TargetModel.add_to_target_allitems_list(target_name, item.name, scope=self.scope)
                # Use Store.hset directly instead of CvtModel.set to avoid circular dependency
                Store.hset(
                    f"{self.scope}__tlm__{packet.target_name}",
                    packet.packet_name,
                    json.dumps(json_hash, cls=JsonEncoder),
                )

    def update_store_commands(self, packet_hash, clear_old=True):
        for target_name, packets in packet_hash.items():
            if clear_old:
                Store.delete(f"{self.scope}__openc3cmd__{target_name}")
            for packet_name, packet in packets.items():
                Logger.debug(f"Configuring cmd packet= {target_name} {packet_name}")
                try:
                    Store.hset(f"{self.scope}__openc3cmd__{target_name}", packet_name, json.dumps(packet.as_json()))
                except Exception as e:
                    Logger.error(f"Invalid text present in {target_name} {packet_name} cmd packet")
                    raise e

    def update_store_item_map(self):
        # Create item_map
        item_map_key = f"{self.scope}__{self.name}__item_to_packet_map"
        item_map = TargetModel.build_item_to_packet_map(self.name, scope=self.scope)
        Store.set(item_map_key, json.dumps(item_map))
        TargetModel.item_map_cache[self.name] = [datetime.now(timezone.utc), item_map]

    def dynamic_update(self, packets, cmd_or_tlm="TELEMETRY", filename="dynamic_tlm.txt"):
        # Build hash of targets/packets
        packet_hash = {}
        for packet in packets:
            target_name = packet.target_name.upper()
            if not packet_hash.get(target_name, None):
                packet_hash[target_name] = {}
            packet_name = packet.packet_name.upper()
            packet_hash[target_name][packet_name] = packet

        # Update Redis
        if cmd_or_tlm == "TELEMETRY":
            self.update_store_telemetry(packet_hash, clear_old=False)
            self.update_store_item_map()
        else:
            self.update_store_commands(packet_hash, clear_old=False)

        # Build dynamic file for cmd_tlm
        configs = {}
        for packet in packets:
            target_name = packet.target_name.upper()
            if not configs.get(target_name, None):
                configs[target_name] = ""
            config = configs[target_name]
            config += packet.to_config(cmd_or_tlm)
            config += "\n"
        for target_name, config in configs.items():
            bucket_key = f"{self.scope}/targets_modified/{target_name}/cmd_tlm/{filename}"
            client = Bucket.getClient()
            client.put_object(
                # Use targets_modified to save modifications
                # This keeps the original target clean (read-only)
                bucket=OPENC3_CONFIG_BUCKET,
                key=bucket_key,
                body=config,
            )

        # Inform microservices of new topics
        # Need to tell loggers to log, and decom to decom
        # We do this for no downtime
        raw_topics = []
        decom_topics = []
        for packet in packets:
            if cmd_or_tlm == "TELEMETRY":
                raw_topics.append(f"{self.scope}__TELEMETRY__{{{self.name}}}__{packet.packet_name.upper()}")
                decom_topics.append(f"{self.scope}__DECOM__{{{self.name}}}__{packet.packet_name.upper()}")
            else:
                raw_topics.append(f"{self.scope}__COMMAND__{{{self.name}}}__{packet.packet_name.upper()}")
                decom_topics.append(f"{self.scope}__DECOMCMD__{{{self.name}}}__{packet.packet_name.upper()}")
        if cmd_or_tlm == "TELEMETRY":
            Topic.write_topic(
                f"MICROSERVICE__{self.scope}__PACKETLOG__{self.name}",
                {"command": "ADD_TOPICS", "topics": json.dumps(raw_topics, cls=JsonEncoder)},
            )
            self.add_topics_to_microservice(f"{self.scope}__PACKETLOG__{self.name}", raw_topics)
            Topic.write_topic(
                f"MICROSERVICE__{self.scope}__DECOMLOG__{self.name}",
                {"command": "ADD_TOPICS", "topics": json.dumps(decom_topics, cls=JsonEncoder)},
            )
            self.add_topics_to_microservice(f"{self.scope}__DECOMLOG__{self.name}", decom_topics)
            Topic.write_topic(
                f"MICROSERVICE__{self.scope}__DECOM__{self.name}",
                {"command": "ADD_TOPICS", "topics": json.dumps(raw_topics, cls=JsonEncoder)},
            )
            self.add_topics_to_microservice(f"{self.scope}__DECOM__{self.name}", raw_topics)
        else:
            Topic.write_topic(
                f"MICROSERVICE__{self.scope}__COMMANDLOG__{self.name}",
                {"command": "ADD_TOPICS", "topics": json.dumps(raw_topics, cls=JsonEncoder)},
            )
            self.add_topics_to_microservice(f"{self.scope}__COMMANDLOG__{self.name}", raw_topics)
            Topic.write_topic(
                f"MICROSERVICE__{self.scope}__DECOMCMDLOG__{self.name}",
                {"command": "ADD_TOPICS", "topics": json.dumps(decom_topics, cls=JsonEncoder)},
            )
            self.add_topics_to_microservice(f"{self.scope}__DECOMCMDLOG__{self.name}", decom_topics)

    def add_topics_to_microservice(self, microservice_name, topics):
        model = MicroserviceModel.get_model(name=microservice_name, scope=self.scope)
        model.topics.extend(topics)
        model.topics = list(set(model.topics))
        model.ignore_changes = True  # Don't restart the microservice right now
        model.update()
