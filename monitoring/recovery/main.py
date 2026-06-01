import time
from fastapi import FastAPI

from actions.runner import run_command
from policy.loader import get_policy
from utils.logger import write_recovery_log, write_critical_log
from verify.http import verify_http


app = FastAPI()


@app.get("/")
def root():
    return {"message": "Recovery Controller Running"}


@app.post("/webhook")
def webhook(payload: dict):
    alertname = payload.get("alertname")

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

    action_success = run_command(command)

    if not action_success:
        write_critical_log(f"action failed: {alertname}")
        return {
            "status": "failed",
            "alertname": alertname,
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
            return {
                "status": "success",
                "alertname": alertname,
                "command": command,
                "verify": "success"
            }

        write_critical_log(f"verify failed: {alertname}")
        return {
            "status": "failed",
            "alertname": alertname,
            "stage": "verify",
            "command": command,
            "verify": "failed"
        }

    write_recovery_log(f"verify skipped: {alertname}")
    return {
        "status": "success",
        "alertname": alertname,
        "command": command,
        "verify": "skipped"
    }