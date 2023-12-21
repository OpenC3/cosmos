from datetime import datetime, timezone, timedelta
from openc3.script.web_socket_api import StreamingWebSocketApi


with StreamingWebSocketApi() as api:
    api.add(
        # Get a list of individual telemetry items
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
