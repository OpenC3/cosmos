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

from openc3.environment import OPENC3_SCOPE
from openc3.models.model import Model
from openc3.utilities.store import Store, EphemeralStore


class MetricModel(Model):
    PRIMARY_KEY = "__openc3__metric"

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name: str, scope: str):
        return super().get(f"{scope}{MetricModel.PRIMARY_KEY}", name=name)

    @classmethod
    def names(cls, scope: str):
        return super().names(f"{scope}{MetricModel.PRIMARY_KEY}")

    @classmethod
    def all(cls, scope: str):
        return super().all(f"{scope}{MetricModel.PRIMARY_KEY}")

    # Sets (updates) the redis hash of this model
    @classmethod
    def set(cls, json: dict, scope: str = OPENC3_SCOPE, queued: bool = True):
        json["scope"] = scope
        cls(**json).create(force=True, queued=queued)

    @classmethod
    def destroy(cls, scope: str, name: str):
        EphemeralStore.hdel(f"{scope}{MetricModel.PRIMARY_KEY}", name)

    def __init__(self, name: str, values: dict = None, scope: str = OPENC3_SCOPE):
        values = {} if values is None else values
        super().__init__(f"{scope}{MetricModel.PRIMARY_KEY}", name=name, scope=scope)
        self.values = values

    def as_json(self):
        return {"name": self.name, "updated_at": self.updated_at, "values": self.values}

    @classmethod
    def redis_extract_p50_and_p99_seconds(cls, value):
        if value:
            split_value = str(value).split(",")
            p50 = float(split_value[0].split("=")[-1]) / 1_000_000
            p99 = float(split_value[-1].split("=")[-1]) / 1_000_000
            return p50, p99
        else:
            return 0.0, 0.0

    @classmethod
    def redis_metrics(cls):
        result = {}

        metrics = Store.info("all")
        result["redis_connected_clients_total"] = metrics["connected_clients"]
        result["redis_used_memory_rss_total"] = metrics["used_memory_rss"]
        result["redis_commands_processed_total"] = metrics["total_commands_processed"]
        result["redis_iops"] = metrics["instantaneous_ops_per_sec"]
        result["redis_instantaneous_input_kbps"] = metrics["instantaneous_input_kbps"]
        result["redis_instantaneous_output_kbps"] = metrics["instantaneous_output_kbps"]
        (
            result["redis_hget_p50_seconds"],
            result["redis_hget_p99_seconds"],
        ) = cls.redis_extract_p50_and_p99_seconds(metrics["latency_percentiles_usec_hget"])
        (
            result["redis_hgetall_p50_seconds"],
            result["redis_hgetall_p99_seconds"],
        ) = cls.redis_extract_p50_and_p99_seconds(metrics["latency_percentiles_usec_hgetall"])
        (
            result["redis_hset_p50_seconds"],
            result["redis_hset_p99_seconds"],
        ) = cls.redis_extract_p50_and_p99_seconds(metrics["latency_percentiles_usec_hset"])
        (
            result["redis_xadd_p50_seconds"],
            result["redis_xadd_p99_seconds"],
        ) = cls.redis_extract_p50_and_p99_seconds(metrics["latency_percentiles_usec_xadd"])
        (
            result["redis_xread_p50_seconds"],
            result["redis_xread_p99_seconds"],
        ) = cls.redis_extract_p50_and_p99_seconds(metrics["latency_percentiles_usec_xread"])
        (
            result["redis_xrevrange_p50_seconds"],
            result["redis_xrevrange_p99_seconds"],
        ) = cls.redis_extract_p50_and_p99_seconds(metrics["latency_percentiles_usec_xrevrange"])
        (
            result["redis_xtrim_p50_seconds"],
            result["redis_xtrim_p99_seconds"],
        ) = cls.redis_extract_p50_and_p99_seconds(metrics["latency_percentiles_usec_xtrim"])

        metrics = EphemeralStore.info("all")
        result["redis_ephemeral_connected_clients_total"] = metrics["connected_clients"]
        result["redis_ephemeral_used_memory_rss_total"] = metrics["used_memory_rss"]
        result["redis_ephemeral_commands_processed_total"] = metrics["total_commands_processed"]
        result["redis_ephemeral_iops"] = metrics["instantaneous_ops_per_sec"]
        result["redis_ephemeral_instantaneous_input_kbps"] = metrics["instantaneous_input_kbps"]
        result["redis_ephemeral_instantaneous_output_kbps"] = metrics["instantaneous_output_kbps"]
        (
            result["redis_ephemeral_hget_p50_seconds"],
            result["redis_ephemeral_hget_p99_seconds"],
        ) = cls.redis_extract_p50_and_p99_seconds(metrics["latency_percentiles_usec_hget"])
        (
            result["redis_ephemeral_hgetall_p50_seconds"],
            result["redis_ephemeral_hgetall_p99_seconds"],
        ) = cls.redis_extract_p50_and_p99_seconds(metrics["latency_percentiles_usec_hgetall"])
        (
            result["redis_ephemeral_hset_p50_seconds"],
            result["redis_ephemeral_hset_p99_seconds"],
        ) = cls.redis_extract_p50_and_p99_seconds(metrics["latency_percentiles_usec_hset"])
        (
            result["redis_ephemeral_xadd_p50_seconds"],
            result["redis_ephemeral_xadd_p99_seconds"],
        ) = cls.redis_extract_p50_and_p99_seconds(metrics["latency_percentiles_usec_xadd"])
        (
            result["redis_ephemeral_xread_p50_seconds"],
            result["redis_ephemeral_xread_p99_seconds"],
        ) = cls.redis_extract_p50_and_p99_seconds(metrics["latency_percentiles_usec_xread"])
        (
            result["redis_ephemeral_xrevrange_p50_seconds"],
            result["redis_ephemeral_xrevrange_p99_seconds"],
        ) = cls.redis_extract_p50_and_p99_seconds(metrics["latency_percentiles_usec_xrevrange"])
        (
            result["redis_ephemeral_xtrim_p50_seconds"],
            result["redis_ephemeral_xtrim_p99_seconds"],
        ) = cls.redis_extract_p50_and_p99_seconds(metrics["latency_percentiles_usec_xtrim"])

        return result
