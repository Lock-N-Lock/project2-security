import time
from fastapi import FastAPI

from actions.runner import run_command
from policy.loader import get_policy
from utils.logger import write_recovery_log, write_critical_log
from verify.http import verify_http


app = FastAPI()

active_recoveries = set()
last_recovery_at = {}


@app.get("/")
def root():
    return {"message": "Recovery Controller Running"}


@app.post("/webhook")
def webhook(payload: dict):
    alertname = (
        payload.get("alertname")
        or payload.get("commonLabels", {}).get("alertname")
    )

    if not alertname:
        alerts = payload.get("alerts", [])
        if alerts:
            alertname = alerts[0].get("labels", {}).get("alertname")

    if not alertname:
        write_critical_log("alertname not found")
        return {
            "status": "error",
            "message": "alertname not found"
        }

    policy = get_policy(alertname)

    if not policy:
        write_critical_log(f"policy not found: {alertname}")
        return {
            "status": "error",
            "message": f"policy not found: {alertname}"
        }

    write_recovery_log(f"policy loaded: {alertname}")

    command = policy.get("command")

    if not command:
        write_recovery_log(f"skipped: no command defined: {alertname}")
        return {
            "status": "skipped",
            "alertname": alertname,
            "message": "no command defined"
        }

    target = policy.get("target", "unknown")
    lock_key = f"{alertname}:{target}"
    cooldown = int(policy.get("cooldown", 0))
    now = time.time()

    if lock_key in active_recoveries:
        write_recovery_log(f"locked: recovery already running: {lock_key}")
        return {
            "status": "locked",
            "alertname": alertname,
            "target": target,
            "message": "recovery already running"
        }

    last_run = last_recovery_at.get(lock_key)

    if last_run and cooldown > 0 and now - last_run < cooldown:
        remaining = round(cooldown - (now - last_run), 2)
        write_recovery_log(
            f"cooldown: recovery skipped: {lock_key}, remaining={remaining}s"
        )
        return {
            "status": "cooldown",
            "alertname": alertname,
            "target": target,
            "remaining": remaining
        }

    active_recoveries.add(lock_key)

    try:
        action_success = run_command(command)

        if not action_success:
            write_critical_log(f"action failed: {alertname}")
            last_recovery_at[lock_key] = time.time()
            return {
                "status": "failed",
                "alertname": alertname,
                "target": target,
                "stage": "action",
                "command": command
            }

        write_recovery_log(f"action success: {alertname}")
        time.sleep(2)

        verify = policy.get("verify", {})

        if verify.get("type") == "http":
            verify_url = verify.get("url")
            verify_timeout = verify.get("timeout", 5)

            verify_success = verify_http(
                verify_url,
                timeout=verify_timeout
            )

            if verify_success:
                write_recovery_log(f"verify success: {alertname}")
                last_recovery_at[lock_key] = time.time()
                return {
                    "status": "success",
                    "alertname": alertname,
                    "target": target,
                    "command": command,
                    "verify": "success"
                }

            write_critical_log(f"verify failed: {alertname}")
            last_recovery_at[lock_key] = time.time()
            return {
                "status": "failed",
                "alertname": alertname,
                "target": target,
                "stage": "verify",
                "command": command,
                "verify": "failed"
            }

        write_recovery_log(f"verify skipped: {alertname}")
        last_recovery_at[lock_key] = time.time()
        return {
            "status": "success",
            "alertname": alertname,
            "target": target,
            "command": command,
            "verify": "skipped"
        }

    finally:
        active_recoveries.discard(lock_key)