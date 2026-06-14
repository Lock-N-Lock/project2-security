import logging
import os
from typing import Any

import requests
from fastapi import BackgroundTasks, FastAPI, HTTPException, Request


app = FastAPI(title="LockBank Telegram Notifier")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/alert")
async def alert(
    request: Request,
    background_tasks: BackgroundTasks,
) -> dict[str, Any]:
    payload = await request.json()

    logger.info("Alertmanager payload: %s", payload)

    status = payload.get("status", "").upper()

    if status == "RESOLVED":
        alerts = payload.get("alerts", [])

        for alert in alerts:
            alertname = alert.get("labels", {}).get("alertname")

            if alertname in ["BankAppDown", "PostgresDown"]:
                return {
                    "status": "skipped",
                    "reason": "resolved notification disabled",
                }

    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        raise HTTPException(
            status_code=500,
            detail="Telegram configuration is missing",
        )

    message = build_message(payload)
    background_tasks.add_task(send_telegram_message, message)

    return {
        "status": "accepted",
        "alerts": len(payload.get("alerts", [])),
    }

@app.post("/recovery-failed")
async def recovery_failed(
    request: Request,
    background_tasks: BackgroundTasks,
) -> dict[str, Any]:
    payload = await request.json()

    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        raise HTTPException(
            status_code=500,
            detail="Telegram configuration is missing",
        )

    message = build_recovery_failed_message(payload)
    background_tasks.add_task(send_telegram_message, message)

    return {
        "status": "accepted",
        "alertname": payload.get("alertname", "UnknownAlert"),
    }

@app.post("/recovery-success")
async def recovery_success(
    request: Request,
    background_tasks: BackgroundTasks,
) -> dict[str, Any]:
    payload = await request.json()

    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        raise HTTPException(
            status_code=500,
            detail="Telegram configuration is missing",
        )

    message = build_recovery_success_message(payload)
    background_tasks.add_task(send_telegram_message, message)

    return {
        "status": "accepted",
        "alertname": payload.get("alertname", "UnknownAlert"),
    }


def build_message(payload: dict[str, Any]) -> str:
    status = payload.get("status", "unknown").upper()
    alerts = payload.get("alerts", [])
    grouped_alerts = len(alerts)

    icon = "✅" if status == "RESOLVED" else "🚨"

    lines = [
        f"{icon} LockBank Alert",
        "",
        f"Status: {status}",
        f"Grouped Alerts: {grouped_alerts}",
    ]

    for index, alert in enumerate(alerts, start=1):
        labels = alert.get("labels", {}) if isinstance(alert, dict) else {}
        annotations = alert.get("annotations", {}) if isinstance(alert, dict) else {}

        alertname = labels.get("alertname", "UnknownAlert")
        severity = labels.get("severity", "unknown")
        service = labels.get("service") or labels.get("job") or "unknown"
        instance = labels.get("instance", "unknown")
        summary = (
            annotations.get("summary")
            or annotations.get("description")
            or "No summary"
        )

        lines.extend(
            [
                "",
                f"[{index}] {alertname}",
                f"- Severity: {severity}",
                f"- Service: {service}",
                f"- Instance: {instance}",
                f"- Summary: {summary}",
            ]
        )

    return "\n".join(lines)


def build_recovery_failed_message(payload: dict[str, Any]) -> str:
    alertname = payload.get("alertname", "UnknownAlert")
    target = payload.get("target", "unknown")
    retry = payload.get("retry", "unknown")
    reason = payload.get("reason", "Recovery failed after retries")

    return "\n".join(
        [
            "🚨 LockBank 복구 실패 알림",
            "",
            f"Alert: {alertname}",
            f"Target: {target}",
            f"Retry: {retry}",
            f"Reason: {reason}",
        ]
    )

def build_recovery_success_message(payload: dict[str, Any]) -> str:
    alertname = payload.get("alertname", "UnknownAlert")
    target = payload.get("target", "unknown")
    verify_url = payload.get("verify_url", "unknown")

    return "\n".join(
        [
            "✅ LockBank 복구 완료 알림",
            "",
            f"Alert: {alertname}",
            f"Target: {target}",
            f"Verify: {verify_url}",
            "Result: Success",
        ]
    )


def send_telegram_message(message: str) -> None:
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"

    try:
        response = requests.post(
            url,
            json={
                "chat_id": TELEGRAM_CHAT_ID,
                "text": message,
            },
            timeout=10,
        )
        response.raise_for_status()
    except requests.RequestException as exc:
        logger.exception("Failed to send Telegram message: %s", exc)
