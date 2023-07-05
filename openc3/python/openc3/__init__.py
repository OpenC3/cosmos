import logging
from openc3.environment import OPENC3_LOG_LEVEL

logging.basicConfig(
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
    level=logging.getLevelName(OPENC3_LOG_LEVEL),
)
