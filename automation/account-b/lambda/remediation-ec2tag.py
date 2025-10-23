# import boto3

# def lambda_handler(event, context):
#     instance_id = event.get("instanceId")
#     if not instance_id:
#         print("❌ Missing instanceId in event")
#         return {"statusCode": 400, "body": "Missing instanceId"}

#     print(f"📥 Received event: {event}")
#     print(f"🔍 Target EC2 instance: {instance_id}")

#     ec2 = boto3.client("ec2")

#     try:
#         response = ec2.describe_instances(InstanceIds=[instance_id])
#         tags = []
#         for reservation in response.get("Reservations", []):
#             for instance in reservation.get("Instances", []):
#                 tags.extend(instance.get("Tags", []))
#         print(f"🏷️ Retrieved tags: {tags}")
#     except Exception as e:
#         print(f"❗ Error fetching instance tags: {str(e)}")
#         return {"statusCode": 500, "body": f"Error fetching instance tags: {str(e)}"}

#     # 提取 owner 和 env 标签
#     owner_value = None
#     env_exists = False
#     for tag in tags:
#         key = tag.get("Key", "").lower()
#         value = tag.get("Value", "")
#         print(f"🔸 Tag found — {key}: {value}")
#         if key == "owner":
#             owner_value = value
#         elif key == "env":
#             env_exists = True

#     # 决定 env 的值
#     env_value = owner_value if owner_value else "dev"
#     print(f"🧠 Decision: env tag will be set to '{env_value}'")

#     try:
#         ec2.create_tags(
#             Resources=[instance_id],
#             Tags=[{"Key": "env", "Value": env_value}]
#         )
#         print(f"✅ 'env' tag applied to instance {instance_id}: {env_value}")
#         return {
#             "statusCode": 200,
#             "body": f"'env' tag set to '{env_value}' for instance {instance_id}"
#         }
#     except Exception as e:
#         print(f"❗ Error setting env tag: {str(e)}")
#         return {"statusCode": 500, "body": f"Error setting env tag: {str(e)}"}



# import boto3

# def lambda_handler(event, context):
#     instance_id = event.get("instanceId")
#     if not instance_id:
#         print("❌ Missing instanceId in event")
#         return {"statusCode": 400, "body": "Missing instanceId"}

#     print(f"📥 Received instanceId: {instance_id}")

#     ec2 = boto3.client("ec2")
#     cloudtrail = boto3.client("cloudtrail")
#     iam = boto3.client("iam")

#     # Step 1: Describe instance to get launch time
#     try:
#         response = ec2.describe_instances(InstanceIds=[instance_id])
#         reservations = response.get("Reservations", [])
#         if not reservations:
#             raise Exception("Instance not found")
#         instance = reservations[0]["Instances"][0]
#         launch_time = instance["LaunchTime"]
#         print(f"🚀 Instance launch time: {launch_time}")
#     except Exception as e:
#         print(f"❗ Error describing instance: {str(e)}")
#         return {"statusCode": 500, "body": str(e)}

#     # Step 2: Lookup CloudTrail event
#     try:
#         events = cloudtrail.lookup_events(
#             LookupAttributes=[
#                 {"AttributeKey": "ResourceName", "AttributeValue": instance_id}
#             ],
#             StartTime=launch_time,
#             EndTime=launch_time
#         )
#         for event in events["Events"]:
#             if "RunInstances" in event["EventName"]:
#                 user_identity = event["CloudTrailEvent"]
#                 break
#         else:
#             raise Exception("RunInstances event not found")
#     except Exception as e:
#         print(f"❗ Error fetching CloudTrail event: {str(e)}")
#         return {"statusCode": 500, "body": str(e)}

#     # Step 3: Parse user identity
#     import json
#     try:
#         event_detail = json.loads(user_identity)
#         user_arn = event_detail["userIdentity"]["arn"]
#         print(f"👤 Instance created by: {user_arn}")
#     except Exception as e:
#         print(f"❗ Error parsing user identity: {str(e)}")
#         return {"statusCode": 500, "body": str(e)}

#     # Step 4: Get env tag from user
#     env_value = "dev"  # default
#     try:
#         if ":user/" in user_arn:
#             user_name = user_arn.split("/")[-1]
#             user_tags = iam.list_user_tags(UserName=user_name)["Tags"]
#         elif ":role/" in user_arn:
#             role_name = user_arn.split("/")[-1]
#             user_tags = iam.list_role_tags(RoleName=role_name)["Tags"]
#         else:
#             raise Exception("Unsupported identity type")

#         for tag in user_tags:
#             if tag["Key"].lower() == "env":
#                 env_value = tag["Value"]
#                 break
#         print(f"🏷️ Retrieved env tag from creator: {env_value}")
#     except Exception as e:
#         print(f"⚠️ Could not retrieve env tag from creator, using default: {env_value}")
#         print(f"❗ IAM tag fetch error: {str(e)}")

#     # Step 5: Apply env tag to instance
#     try:
#         ec2.create_tags(
#             Resources=[instance_id],
#             Tags=[{"Key": "env", "Value": env_value}]
#         )
#         print(f"✅ Applied env tag to instance {instance_id}: {env_value}")
#         return {"statusCode": 200, "body": f"env tag set to {env_value}"}
#     except Exception as e:
#         print(f"❌ Failed to apply env tag: {str(e)}")
#         return {"statusCode": 500, "body": str(e)}

import boto3
import json
from datetime import timedelta

def lambda_handler(event, context):
    instance_id = event.get("instanceId")
    if not instance_id:
        print("❌ Missing instanceId in event")
        return {"statusCode": 400, "body": "Missing instanceId"}

    print(f"📥 Received instanceId: {instance_id}")

    ec2 = boto3.client("ec2")
    cloudtrail = boto3.client("cloudtrail")
    iam = boto3.client("iam")
    config = boto3.client("config")

    # Step 1: Describe EC2 instance
    try:
        response = ec2.describe_instances(InstanceIds=[instance_id])
        instance = response["Reservations"][0]["Instances"][0]
        launch_time = instance["LaunchTime"]
        tags = instance.get("Tags", [])
        print(f"🚀 Launch time: {launch_time}")
        print(f"🏷️ Current tags: {tags}")
    except Exception as e:
        print(f"❗ Error describing instance: {str(e)}")
        return {"statusCode": 500, "body": str(e)}

    # Step 2: Lookup CloudTrail RunInstances event
    try:
        events = cloudtrail.lookup_events(
            StartTime=launch_time - timedelta(minutes=10),
            EndTime=launch_time + timedelta(minutes=30),
            MaxResults=50
        )

        user_identity = None
        for event in events["Events"]:
            try:
                raw_event = event.get("CloudTrailEvent")
                if not raw_event:
                    print("⚠️ CloudTrailEvent is missing or empty")
                    continue

                event_detail = json.loads(raw_event)
                if not isinstance(event_detail, dict):
                    print("⚠️ CloudTrailEvent is not a valid JSON object")
                    continue

                response_elements = event_detail.get("responseElements", {})
                instances_set = response_elements.get("instancesSet")

                if isinstance(instances_set, dict):
                    instances = instances_set.get("items", [])
                    for item in instances:
                        if item.get("instanceId") == instance_id:
                            user_identity = event_detail.get("userIdentity")
                            print("✅ Found matching CloudTrail event")
                            break
                else:
                    print("⚠️ instancesSet missing or not a dict")
            except Exception as parse_error:
                print(f"⚠️ Error parsing CloudTrail event: {str(parse_error)}")

            if user_identity:
                break

        if not user_identity:
            print("⚠️ No matching CloudTrail event found; using default env tag")
            user_arn = "unknown"
        else:
            user_arn = user_identity.get("arn", "unknown")
            print(f"👤 Instance created by: {user_arn}")
    except Exception as e:
        print(f"❗ Error fetching CloudTrail event: {str(e)}")
        return {"statusCode": 500, "body": str(e)}

    # Step 3: Get env tag from creator
    env_value = "dev"  # fallback default
    try:
        if ":user/" in user_arn:
            user_name = user_arn.split("/")[-1]
            user_tags = iam.list_user_tags(UserName=user_name)["Tags"]
        elif ":role/" in user_arn:
            role_name = user_arn.split("/")[-1]
            user_tags = iam.list_role_tags(RoleName=role_name)["Tags"]
        else:
            raise Exception("Unsupported identity type")

        for tag in user_tags:
            if tag["Key"].lower() == "env":
                env_value = tag["Value"]
                break
        print(f"🏷️ Creator's env tag: {env_value}")
    except Exception as e:
        print(f"⚠️ Could not retrieve creator's env tag, using default: {env_value}")
        print(f"❗ IAM tag fetch error: {str(e)}")

    # Step 4: Compare and update env tag if needed
    current_env = None
    for tag in tags:
        if tag.get("Key", "").lower() == "env":
            current_env = tag.get("Value")
            break

    if current_env != env_value:
        print(f"🔁 Updating env tag from '{current_env}' to '{env_value}'")
        try:
            ec2.create_tags(
                Resources=[instance_id],
                Tags=[{"Key": "env", "Value": env_value}]
            )
            print(f"✅ env tag updated to '{env_value}'")
        except Exception as e:
            print(f"❌ Failed to apply env tag: {str(e)}")
            return {"statusCode": 500, "body": str(e)}
    else:
        print(f"✅ env tag already correct: '{current_env}'")

    # Step 5: Trigger AWS Config rule re-evaluation
    try:
        rule_name = "ec2-env-tag-check"  # ⬅️ 替换为你的实际 Config 规则名
        config.start_config_rules_evaluation(ConfigRuleNames=[rule_name])
        print(f"🔄 Triggered config rule re-evaluation: {rule_name}")
    except Exception as e:
        print(f"⚠️ Failed to trigger re-evaluation: {str(e)}")

    return {
        "statusCode": 200,
        "body": f"env tag set to '{env_value}' and config rule re-evaluation triggered"
    }
