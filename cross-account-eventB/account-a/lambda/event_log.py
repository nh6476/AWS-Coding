import json
import logging
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    logger.info("📦 Received event:\n%s", json.dumps(event, indent=2))

    # 提取事件详情
    detail = event.get("detail", {})
    state = detail.get("state")
    instance_id = detail.get("instance-id")
    region = event.get("region", "us-east-1")  # 默认 us-east-1，防止缺失

    logger.info(f"🔍 Parsed event detail: state={state}, instance_id={instance_id}, region={region}")

    # 判断是否为 EC2 实例停止事件
    if state == "stopped" and instance_id:
        logger.info(f"🛠 Instance {instance_id} is stopped. Preparing to start...")

        try:
            # Assume B账户角色
            sts = boto3.client("sts")
            assumed = sts.assume_role(
                RoleArn="arn:aws:iam::496390993498:role/ec2-starter-for-a",
                RoleSessionName="StartEC2Session"
            )
            creds = assumed["Credentials"]
            logger.info("✅ AssumeRole succeeded")
            logger.info(f"🔑 Temporary credentials acquired: AccessKeyId={creds['AccessKeyId'][:6]}...")

            # 使用临时凭证调用 EC2 客户端
            ec2 = boto3.client(
                "ec2",
                region_name=region,
                aws_access_key_id=creds["AccessKeyId"],
                aws_secret_access_key=creds["SecretAccessKey"],
                aws_session_token=creds["SessionToken"]
            )

            # 🔍 列出所有实例（权限验证）
            try:
                instances = ec2.describe_instances()
                all_ids = []
                for reservation in instances["Reservations"]:
                    for inst in reservation["Instances"]:
                        all_ids.append(inst["InstanceId"])
                logger.info(f"📋 EC2 instances in B account: {all_ids}")
            except Exception as e:
                logger.error(f"⚠️ Failed to list EC2 instances: {str(e)}", exc_info=True)

            # 🚀 启动目标实例
            try:
                response = ec2.start_instances(InstanceIds=[instance_id])
                logger.info(f"🚀 StartInstances response:\n{json.dumps(response, indent=2)}")
            except Exception as e:
                logger.error(f"❌ StartInstances failed: {str(e)}", exc_info=True)

        except Exception as e:
            logger.error(f"❌ AssumeRole failed: {str(e)}", exc_info=True)
    else:
        logger.info("ℹ️ Event is not a stopped EC2 instance or missing instance ID. No action taken.")
