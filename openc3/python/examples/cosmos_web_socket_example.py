import os
from datetime import datetime, timezone, timedelta

# Example Use
# The following lines are only for outside of the COSMOS Docker or Kubernetes Cluster
# Environment variables are already set inside of our containers
# START OUTSIDE OF DOCKER ONLY
os.environ["OPENC3_SCOPE"] = "DEFAULT"
os.environ["OPENC3_API_HOSTNAME"] = "127.0.0.1"
os.environ["OPENC3_API_PORT"] = "2900"
os.environ["OPENC3_SCRIPT_API_HOSTNAME"] = "127.0.0.1"
os.environ["OPENC3_SCRIPT_API_PORT"] = "2900"
os.environ["OPENC3_API_PASSWORD"] = "password"
# END OUTSIDE OF DOCKER ONLY

from openc3.utilities.time import to_nsec_from_epoch
from openc3.script.web_socket_api import StreamingWebSocketApi, MessagesWebSocketApi


api = StreamingWebSocketApi()
api.connect()
api.add(
    items=[
        "DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED",
        "DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED",
    ]
)
for _ in range(5):
    print(api.read())
api.remove(items=["DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED"])
for _ in range(5):
    print(api.read())
api.disconnect()


# Warning this saves all data to RAM. Do not use for large queries
now = datetime.now(timezone.utc)
data = StreamingWebSocketApi.read_all(
    items=[
        "DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED",
        "DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED",
    ],
    start_time=now - timedelta(seconds=30),
    end_time=now + timedelta(seconds=5),
)
print(data)


now = datetime.now(timezone.utc)
api = MessagesWebSocketApi(
    history_count=0,
    start_time=to_nsec_from_epoch(now - timedelta(seconds=86400)),
    end_time=to_nsec_from_epoch(now - timedelta(seconds=60)),
)
api.connect()
for _ in range(500):
    # Note returns batch array
    data = api.read()
    if not data or len(data) == 0:
        break
    print(f"\nReceived {len(data)} log messages:")
    print(data)
api.disconnect()
