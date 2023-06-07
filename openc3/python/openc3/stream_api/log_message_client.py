#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
log_message_client.py
"""

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Lesser General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from datetime import datetime
import json

from openc3.stream import CosmosAsyncStream
from openc3.stream_api.base_client import BaseClient
from openc3.stream_shared import CosmosAsyncClient


class LogMessageClient(BaseClient):
    def __init__(
        self,
        count: int,
        timeout: int = 30,
    ) -> None:
        """
        The constructor for the LogMessageClient.

        Parameters:
            count (int): the number of messages to get from Cosmos.
            timeout (int): how many seconds to wait for messages.
        """
        super().__init__(timeout=timeout)
        self.count = count
        self._count = 0

    @staticmethod
    def _datetime_value(dt: datetime = None):
        """
        Make a datetime object into unix EPOC seconds and
        times it by one billion?

        Parameters:
            dt (datetime): [optional] converted to int
        """
        if dt is None:
            dt = datetime.now()
        return int(dt.timestamp() * 1000000000)

    def _split_data(self, message: str):
        """
        Splits the data from _extract_data and adds it to
        instances _data list.

        Parameters:
            message (str): string to convert to dict and
        """
        for data in json.loads(message):
            self._count += 1
            self._data.append(data)

    def _extract_data(self, message: dict):
        """
        Is used as the callback from the AsyncClient. Should
        filter data base on dict values and pass data along.

        Parameters:
            message (dict): dict to pull information out of
        """
        msg = message.get("message")
        typ = message.get("type")
        if self._count == self.count:
            self._event.set()
        elif typ is None and msg is not None:
            self._last_msg = datetime.now().timestamp()
            self._split_data(msg)

    def get(self):
        """
        Get the data from the LogMessage websocket.

        Returns:
            list: of data pulled from Cosmos.
        """
        if self._data:
            return self._data

        stream = CosmosAsyncStream()
        stream.start()

        client = CosmosAsyncClient(stream)
        client.message_channel_sub(0, self._extract_data)

        self.wait()

        client.message_channel_unsub()
        stream.stop()

        return self._data
