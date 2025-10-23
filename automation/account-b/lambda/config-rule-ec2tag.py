import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

config = boto3.client("config")

ALLOWED_ENVS = {"dev", "staging", "prod"}

def lambda_handler(event, context):
    # 入参日志
    logger.info("📥 Received event:")
    logger.info(json.dumps(event, indent=2))

    # 解析事件
    invoking_event = json.loads(event["invokingEvent"])
    configuration_item = invoking_event["configurationItem"]
    resource_type = configuration_item["resourceType"]
    resource_id = configuration_item["resourceId"]
    capture_time = configuration_item["configurationItemCaptureTime"]
    tags = configuration_item.get("tags") or {}

    logger.info(f"🔍 Evaluating resource: {resource_id} ({resource_type}) at {capture_time}")
    logger.info(f"🏷️ Tags: {tags}")

    # 如果资源被删除或不可评估，返回 NOT_APPLICABLE（可选）
    if configuration_item.get("configurationItemStatus") in ("Deleted", "ResourceDeleted"):
        logger.info("🗑️ Resource is deleted; marking NOT_APPLICABLE")
        return put_and_log(event["resultToken"], resource_type, resource_id,
                           "NOT_APPLICABLE", "Resource deleted", capture_time)

    # 明确区分：缺失 vs 非法
    env_value = tags.get("env")
    if env_value is None or str(env_value).strip() == "":
        compliance_type = "NON_COMPLIANT"
        annotation = "Missing env tag"
    elif str(env_value).lower() in ALLOWED_ENVS:
        compliance_type = "COMPLIANT"
        annotation = f"env tag is valid: {env_value}"
    else:
        compliance_type = "NON_COMPLIANT"
        annotation = f"Invalid env tag: {env_value}. Allowed: {sorted(ALLOWED_ENVS)}"

    # 上报评估
    return put_and_log(event["resultToken"], resource_type, resource_id,
                       compliance_type, annotation, capture_time)


def put_and_log(result_token, resource_type, resource_id,
                compliance_type, annotation, capture_time):
    evaluation = {
        "ComplianceResourceType": resource_type,
        "ComplianceResourceId": resource_id,
        "ComplianceType": compliance_type,
        "Annotation": annotation[:256],  # Annotation 最长 256 字符
        "OrderingTimestamp": capture_time,
    }

    logger.info("📊 Evaluation to submit:")
    logger.info(json.dumps(evaluation, indent=2))

    response = config.put_evaluations(
        Evaluations=[evaluation],
        ResultToken=result_token
    )
    logger.info("✅ PutEvaluations response:")
    logger.info(json.dumps(response, indent=2))
    return response
