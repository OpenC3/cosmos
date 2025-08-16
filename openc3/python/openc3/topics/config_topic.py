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

from openc3.topics.topic import Topic


class ConfigTopic(Topic):
    PRIMARY_KEY = "__CONFIG"

    @classmethod
    def write(cls, config, scope):
        """Write a configuration change to the topic

        Args:
            config (dict): Hash with required keys 'kind', 'name', 'type'
            scope (str): Scope for the topic
        """
        if 'kind' not in config:
            raise ValueError("ConfigTopic error, required key kind: not given")

        if config['kind'] not in ['created', 'deleted']:
            raise ValueError(f"ConfigTopic error unknown kind: {config['kind']}")

        if 'name' not in config:
            raise ValueError("ConfigTopic error, required key name: not given")

        if 'type' not in config:
            raise ValueError("ConfigTopic error, required key type: not given")

        # Limit the configuration topics to 1000 entries
        Topic.write_topic(f"{scope}{cls.PRIMARY_KEY}", config, '*', 1000)

    @classmethod
    def read(cls, offset=None, count=100, scope=None):
        """Read configuration changes from the topic

        Args:
            offset (str, optional): Offset to start reading from
            count (int): Number of entries to read (default: 100)
            scope (str): Scope for the topic

        Returns:
            list: Array of configuration entries
        """
        topic = f"{scope}{cls.PRIMARY_KEY}"

        if offset is not None:
            result = []
            for topic, msg_id, msg_hash, _ in Topic.read_topics([topic], [offset], None, count):
                if msg_hash is None:
                    continue
                result.append((msg_id, msg_hash))
            if not result:
                return []  # We want to return an empty array rather than an empty hash
            else:
                # result is a hash with the topic key followed by an array of results
                # This returns just the array of arrays [[offset, hash], [offset, hash], ...]
                return result
        else:
            result = Topic.get_newest_message(topic)
            if result and result[0] is not None:
                return [result]
            return []