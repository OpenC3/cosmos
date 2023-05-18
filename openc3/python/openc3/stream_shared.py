#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
stream_api.py
"""

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Lesser General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt

import json

from cosmosc2.authorization import CosmosAuthorization, generate_auth
from cosmosc2.environment import COSMOS_SCOPE
from cosmosc2.stream import CosmosAsyncStream


class CosmosAsyncClient:
    def __init__(
        self,
        stream: CosmosAsyncStream,
        scope: str = COSMOS_SCOPE,
        auth: CosmosAuthorization = None,
    ) -> None:
        self.stream = stream
        self.scope = scope
        self.auth = generate_auth() if auth is None else auth

    def streaming_id(self):
        """
        generate the streaming id to send on the websocket.

        Returns:
            str: json string for identifier.
        """
        return json.dumps(
            {
                "channel": "StreamingChannel",
                "scope": self.scope,
                "token": self.auth.get(),
            }
        )

    def streaming_channel_sub(self, callback):
        """
        Have the stream subscribe to the streaming channel

        Parameters:
            callback (callable): methods called when data recivied
        """
        self.stream.subscribe(
            "/cosmos-api/cable",
            {"command": "subscribe", "identifier": self.streaming_id()},
            callback,
        )

    def streaming_channel_unsub(self):
        """
        Have the stream unsubscribe from the streaming channel
        """
        self.stream.queue(
            "/cosmos-api/cable",
            {"command": "unsubscribe", "identifier": self.streaming_id()},
        )
        self.stream.unsubscribe("/cosmos-api/cable")

    def streaming_channel_add(
        self,
        items: list,
        mode: str = "DECOM",
        start_time: int = None,
        end_time: int = None,
    ):
        """
        Have the stream already subscribed to the streaming channel
        add items with a time range to the stream.

        Parameters:
            items (list):
            mode (str):
            start_time (int):
            end_time (int):
        """
        data = json.dumps(
            {
                "scope": self.scope,
                "token": self.auth.get(),
                "mode": mode,
                "items": items,
                "start_time": start_time,
                "end_time": end_time,
                "action": "add",
            }
        )
        self.stream.queue(
            "/cosmos-api/cable",
            {
                "command": "message",
                "identifier": self.streaming_id(),
                "data": data,
            },
        )

    def message_id(self, history_count: int):
        """
        generate the message id to send on the websocket.

        Returns:
            history_count (str): stream history to request
        """
        return json.dumps(
            {
                "channel": "MessagesChannel",
                "scope": self.scope,
                "token": self.auth.get(),
                "history_count": history_count,
            }
        )

    def message_channel_sub(self, history_count, callback):
        """
        Have the stream unsubscribe from the streaming channel

        Parameters:
            history_count (int): stream history to request
            callback (callable): methods called when data recivied
        """
        self.stream.subscribe(
            "/cosmos-api/cable",
            {"command": "subscribe", "identifier": self.message_id(history_count)},
            callback,
        )

    def message_channel_unsub(self, history_count: int):
        """
        Have the stream unsubscribe from the streaming channel

        Parameters:
            history_count (int): stream history to request
        """
        self.stream.queue(
            "/cosmos-api/cable",
            {"command": "unsubscribe", "identifier": self.message_id(history_count)},
        )
        self.stream.unsubscribe("/cosmos-api/cable")
