#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
data_extractor_client.py
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
import logging

from openc3.stream import CosmosAsyncStream
from openc3.stream_api.base_client import BaseClient
from openc3.stream_shared import CosmosAsyncClient


class DataExtractorClient(BaseClient):
    def __init__(
        self,
        items: list,
        start_time: str,
        end_time: str,
        timeout: int = 30,
    ) -> None:
        """
        The constructor for the DataExtractorClient.

        Parameters:
            items (list): list of packet items to get from Cosmos.
            start_time (str): The start time of the time range
            end_time (str): The end time of the time range
            timeout (int): how many seconds to wait for messages.
        """
        super().__init__(timeout=timeout)
        self._kwargs = self._validate_args(items, start_time, end_time)

    def _validate_args(
        self,
        items: list,
        start_time: str,
        end_time: str,
    ):
        """
        Validate the input of the object instance.

        Parameters:
            items (list): list of packet items to get from Cosmos.
            start_time (str): The start time of the time range
            end_time (str): The end time of the time range
        """
        start_time_ = datetime.strptime(start_time, "%Y/%m/%d %H:%M:%S")
        end_time_ = datetime.strptime(end_time, "%Y/%m/%d %H:%M:%S")
        items_ = []

        for item in items:
            #item_list = item.split(".")
            #if len(item_list) != 3:
            #    raise ValueError(f"incorrect item format: {item}")
            #item_list.insert(0, "TLM")
            #items_.append("__".join(item_list))
            items_.append(item)

        return {
            "start_time": self._datetime_value(start_time_),
            "end_time": self._datetime_value(end_time_),
            "items": items_,
        }

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
        for data in message:
            t = data.pop("__time")
            for item, value in data.items():
                self._data.append(
                    {
                        "item": item,
                        "value": value,
                        "time": t,
                    }
                )

    def _extract_data(self, message: dict):
        """
        Is used as the callback from the AsyncStream. Should
        filter data base on dict values and pass data along.

        Parameters:
            message (dict): dict to pull information out of
        """
        msg = message.get("message")
        typ = message.get("type")
        if msg == "[]":
            self._event.set()
        elif typ is None and msg is not None:
            self._last_msg = datetime.now().timestamp()
            self._split_data(msg)

    def get(self):
        """
        Get the data from the DataExtractor websocket.

        Returns:
            list: of data pulled from Cosmos.
        """
        if self._data:
            return self._data

        stream = CosmosAsyncStream()
        stream.start()

        client = CosmosAsyncClient(stream)
        client.streaming_channel_sub(self._extract_data)

        logging.debug(f"request being sent with: {self._kwargs}")
        client.streaming_channel_add(**self._kwargs)

        self.wait()

        client.streaming_channel_unsub()
        stream.stop()

        return self._data
