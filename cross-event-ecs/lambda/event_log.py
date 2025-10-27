import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    logger.info("📦 Event received:\n%s", json.dumps(event, indent=2))
