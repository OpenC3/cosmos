import os
from .connection import CosmosConnection

COSMOS = CosmosConnection()

def update_scope(scope: str):
    """Update the Cosmos scope selection

    Parameters:
        scope (str): The scope to use on Cosmos v5
    """
    global COSMOS
    COSMOS.scope = str(scope)
    os.environ["OPENC3_SCOPE"] = str(scope)


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

from .api_shared import *
from .cosmos_api import *
from .commands import *
from .extract import *
from .internal_api import *
from .limits import *
from .telemetry import *
from .timeline_api import *
from .tools import *
