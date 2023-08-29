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

import asyncio
import json
import logging
from threading import Thread
import websockets
from requests.auth import AuthBase

from openc3.environment import *
from .authorization import generate_auth

logger = logging.getLogger("websockets")
logger.setLevel(logging.INFO)
logger.addHandler(logging.StreamHandler())


class CosmosAsyncError(RuntimeError):
    pass


class CosmosAsyncStop(StopAsyncIteration):
    pass


class CosmosAsyncStream(Thread):
    def __init__(
        self,
        schema: str = OPENC3_API_SCHEMA,
        hostname: str = OPENC3_API_HOSTNAME,
        port: int = OPENC3_API_PORT,
        auth: AuthBase = None,
    ):
        """
        Is the base thread class to access cosmos websockets.

        Parameters:
            schema (str): [optional] will default to environment variable
            hostname (str): [optional] will default to environment variable
            port (int): [optional] will default to environment variable
        """
        super().__init__()
        self.auth = generate_auth() if auth is None else auth
        self._tasks = {}
        self._events = {}
        self._queues = {}
        self._loop = asyncio.new_event_loop()
        self._stop_event = asyncio.Event()

        if schema == "http":
            self._url = f"ws://{hostname}:{port}"
        else:
            self._url = f"wss://{hostname}:{port}"

    def run(self):
        """
        Should be called from the thread.start() method.
        """
        try:
            self._loop.run_until_complete(self._stop_event.wait())
            self._loop.run_until_complete(self._clean())
        finally:
            self._loop.close()

    def stop(self):
        """
        Should be called to stop all websockets.
        """
        self._loop.call_soon_threadsafe(self._stop_event.set)

    async def _clean(self):
        """
        Should wait for websockets to shutdown
        """
        for task in self._tasks.values():
            await asyncio.wait_for(task, timeout=5)
        await asyncio.gather(*self._tasks.values())

    def subscribe(self, endpoint, sub_msg, callback):
        """
        Start a new asyncio.Task to the cosmos websocket endpoints.

        Parameters:
            endpoint (str): example: /openc3-api/cable
            sub_msg (dict): send to cosmos once connected
            callback (callable): method to return messages to
        """

        def _subscribe():
            if endpoint not in self._tasks:
                listen = self._listen(endpoint, sub_msg, callback)
                self._tasks[endpoint] = self._loop.create_task(listen)
                self._queues[endpoint] = asyncio.Queue()
                self._events[endpoint] = asyncio.Event()

        self._loop.call_soon_threadsafe(_subscribe)

    def unsubscribe(self, endpoint):
        """
        Stop an asyncio.Task

        Parameters:
            endpoint (str): example: /openc3-api/cable
        """

        def _unsubscribe():
            event = self._events.pop(endpoint, None)
            if event is not None:
                event.set()

        self._loop.call_soon_threadsafe(_unsubscribe)

    def queue(self, endpoint, message):
        """
        Queue a message to send to the websocket.

        Parameters:
            endpoint (str): example: /openc3-api/cable
            message (dict): json based message to send
        """

        def _queue():
            queue = self._queues.get(endpoint, None)
            if queue is not None:
                queue.put_nowait(message)

        self._loop.call_soon_threadsafe(_queue)

    async def _listen(self, endpoint, sub_msg, callback):
        """
        Base asyncio.Task to connect and manage websocket.

        Parameters:
            endpoint (str): example: /openc3-api/cable
            sub_msg (dict): json based message to send
            callback (callable): method/function to call with data
        """
        url = f"{self._url}{endpoint}"
        try:
            ws = await websockets.connect(
                f"{url}?scope={OPENC3_SCOPE}&authorization={self.auth.get()}",
                loop=self._loop,
            )
            await self._welcome(ws)
            await self._confirm(ws, sub_msg)
            await self._handle(endpoint, ws, callback)
            await ws.close()
        except asyncio.CancelledError:
            logging.info(f"{endpoint} has been canceled")
        except CosmosAsyncStop:
            logging.info(f"stopping {endpoint}")
        except CosmosAsyncError as e:
            logging.error(f"failed connection {endpoint}, {e}")
        except Exception as e:
            logging.exception(e)
        finally:
            logging.debug(f"exitting task: {endpoint}")
            self._queues.pop(endpoint, None)
            self._events.pop(endpoint, None)

    @staticmethod
    async def _welcome(ws):
        """
        Confirm welcome from ActionCable websocket.

        Parameters:
            ws (WebSocket): open websocket
        """
        data = await ws.recv()
        data = json.loads(data)
        if data["type"] != "welcome":
            raise CosmosAsyncError("failed to get welcome message")

    @staticmethod
    async def _confirm(ws, sub_msg):
        """
        Send sub_msg to ActionCable websocket.

        Parameters:
            ws (WebSocket): open websocket
            sub_msg (dict): json based object
        """
        json_msg = json.dumps(sub_msg)
        logging.debug(f"sending: {json_msg}")
        await ws.send(json_msg)
        data = await ws.recv()
        data = json.loads(data)
        logging.debug(f"recv: {data}")

    async def _handle(self, endpoint, ws, callback):
        """
        Once connect send messages queued to ActionCable websocket
        and receive messages from.

        Parameters:
            endpoint (str): endpoint of connection
            ws (WebSocket): open websocket
            callback (callable): function/method to send data to
        """
        queue = self._queues[endpoint]
        event = self._events[endpoint]
        while event.is_set() is False and self._stop_event.is_set() is False:
            await self._send(queue, ws)
            data = await ws.recv()
            data = json.loads(data)
            callback(data)

    @staticmethod
    async def _send(queue, ws):
        """
        Send a message in the queue.

        Parameters:
            queue (Queue): Outgoing message queue
            ws (WebSocket): open websocket
        """
        try:
            message = queue.get_nowait()
            if message is None:
                raise CosmosAsyncStop()
            else:
                logging.debug(f"sending: {message}")
                await ws.send(json.dumps(message))
        except asyncio.QueueEmpty:
            pass
