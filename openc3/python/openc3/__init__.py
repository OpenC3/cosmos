#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
__init__.py
"""

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Lesser General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt

import os
import logging
from cosmosc2.environment import LOG_LEVEL
from cosmosc2.connection import CosmosConnection

logging.basicConfig(
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
    level=logging.getLevelName(LOG_LEVEL),
)

COSMOS = CosmosConnection()


def update_scope(scope: str):
    """Update the Cosmos scope selection

    Parameters:
        scope (str): The scope to use on Cosmos v5
    """
    global COSMOS
    COSMOS.scope = str(scope)
    os.environ["COSMOS_SCOPE"] = str(scope)


def initialize_connection(hostname: str = None, port: int = None):
    """Generate the current session with Cosmos

    Parameters:
        hostname (str): The hostname to connect to Cosmos v5
        port (int): The port to connect to Cosmos v5
    """
    global COSMOS

    if COSMOS:
        COSMOS.shutdown()

    if hostname and port:
        COSMOS = CosmosConnection(hostname, port)
    else:
        COSMOS = CosmosConnection()


def shutdown():
    """Shutdown the current session with Cosmos"""
    global COSMOS
    COSMOS.shutdown()


from cosmosc2.api_shared import *
from cosmosc2.cosmos_api import *
from cosmosc2.commands import *
from cosmosc2.extract import *
from cosmosc2.internal_api import *
from cosmosc2.limits import *
from cosmosc2.telemetry import *
from cosmosc2.timeline_api import *
from cosmosc2.tools import *
