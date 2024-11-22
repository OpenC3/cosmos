# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
from openc3.topics.topic import Topic
from openc3.models.cvt_model import CvtModel
from openc3.utilities.json import JsonEncoder
from openc3.utilities.time import to_nsec_from_epoch


class TelemetryDecomTopic(Topic):
    @classmethod
    def write_packet(cls, packet, id=None, scope=None):
        # OpenC3.in_span("write_packet") do
        # Need to build a JSON hash of the decommutated data
        # Support "downward typing"
        # everything base name is RAW (including DERIVED)
        # Request for WITH_UNITS, etc will look down until it finds something
        # If nothing - item does not exist - nil
        # __ as separators ITEM1, ITEM1__C, ITEM1__F, ITEM1__U

        json_hash = CvtModel.build_json_from_packet(packet)
        # Write to stream
        msg_hash = {
            "time": to_nsec_from_epoch(packet.packet_time),
            "stored": str(packet.stored),
            "target_name": packet.target_name,
            "packet_name": packet.packet_name,
            "received_count": packet.received_count,
            "json_data": json.dumps(json_hash, cls=JsonEncoder),
        }
        Topic.write_topic(
            f"{scope}__DECOM__{{{packet.target_name}}}__{packet.packet_name}",
            msg_hash,
            id,
        )

        if not packet.stored:
            # Also update the current value table with the latest decommutated data
            CvtModel.set(
                json_hash,
                packet.target_name,
                packet.packet_name,
                scope=scope,
            )
