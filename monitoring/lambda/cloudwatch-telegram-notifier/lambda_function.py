import json
import os
import urllib.parse
import urllib.request


BOT_TOKEN = os.environ["TELEGRAM_BOT_TOKEN"]
CHAT_ID = os.environ["TELEGRAM_CHAT_ID"]


def send_telegram(text: str) -> None:
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    data = urllib.parse.urlencode({
        "chat_id": CHAT_ID,
        "text": text,
    }).encode("utf-8")

    req = urllib.request.Request(url, data=data, method="POST")
    with urllib.request.urlopen(req, timeout=10) as response:
        response.read()


def lambda_handler(event, context):
    for record in event.get("Records", []):
        sns = record.get("Sns", {})
        subject = sns.get("Subject", "CloudWatch Alarm")
        message = sns.get("Message", "")

        try:
            parsed = json.loads(message)
            alarm_name = parsed.get("AlarmName", "UnknownAlarm")
            new_state = parsed.get("NewStateValue", "UNKNOWN")
            reason = parsed.get("NewStateReason", "")
            region = parsed.get("Region", "ap-northeast-2")

            text = (
                "[AWS CloudWatch Alarm]\n"
                f"Alarm: {alarm_name}\n"
                f"State: {new_state}\n"
                f"Region: {region}\n"
                f"Reason: {reason}"
            )
        except Exception:
            text = (
                "[AWS SNS Message]\n"
                f"Subject: {subject}\n"
                f"Message: {message}"
            )

        send_telegram(text)

    return {"statusCode": 200, "body": "ok"}
