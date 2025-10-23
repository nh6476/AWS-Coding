import smtplib
import json
import os
import boto3
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

# 从环境变量读取非敏感配置
smtp_server = os.environ.get('SMTP_SERVER', 'smtp.163.com')
smtp_port = int(os.environ.get('SMTP_PORT', 465))
sender_email = os.environ.get('SENDER_EMAIL')
recipient_email = os.environ.get('RECIPIENT_EMAIL')

def get_auth_code():
    ssm = boto3.client("ssm")
    response = ssm.get_parameter(
        Name="/lambda/mail/smtp_auth_code",  # 你在 SSM 里保存的参数名
        WithDecryption=True
    )
    return response["Parameter"]["Value"]

def lambda_handler(event, context):
    event_body = json.dumps(event, indent=2)
    auth_code = get_auth_code()

    message = MIMEMultipart()
    message['From'] = sender_email
    message['To'] = recipient_email
    message['Subject'] = 'Lambda Event Notification'
    message.attach(MIMEText(event_body, 'plain'))

    try:
        with smtplib.SMTP_SSL(smtp_server, smtp_port) as server:
            server.login(sender_email, auth_code)
            server.sendmail(sender_email, recipient_email, message.as_string())
        return {'statusCode': 200, 'body': '邮件发送成功'}
    except Exception as e:
        return {'statusCode': 500, 'body': f'邮件发送失败: {str(e)}'}
