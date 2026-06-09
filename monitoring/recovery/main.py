import time
import json
import threading
from pathlib import Path
from fastapi import FastAPI, BackgroundTasks, Response
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST

from actions.runner import run_command
from policy.loader import get_policy
from utils.logger import write_recovery_log, write_critical_log
from verify.http import verify_http

STATE_FILE = Path("/app/logs/recovery_state.json")


def load_state():
    if not STATE_FILE.exists():
        return {}

    try:
        with STATE_FILE.open("r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def save_state(state):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp_file = STATE_FILE.with_suffix(".tmp")

    with tmp_file.open("w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)

    tmp_file.replace(STATE_FILE)


app = FastAPI()

recovery_attempt_total = Counter(
    "recovery_attempt_total",
    "Total number of recovery attempts",
    ["alertname", "target"]
)

recovery_success_total = Counter(
    "recovery_success_total",
    "Total number of successful recoveries",
    ["alertname", "target"]
)

active_recoveries = set()
last_recovery_at = load_state()
state_lock = threading.Lock()


def update_and_save_state(lock_key, timestamp):
    with state_lock:
        last_recovery_at[lock_key] = timestamp
        save_state(last_recovery_at)


def run_recovery_task(lock_key, alertname, target, command, verify):
    recovery_attempt_total.labels(
        alertname=alertname,
        target=target
    ).inc()
    try:
        action_success = run_command(command)

        if not action_success:
            write_critical_log(f"action failed: {alertname}")
            update_and_save_state(lock_key, time.time())
            return

        write_recovery_log(f"action success: {alertname}")
        time.sleep(2)

        if verify.get("type") == "http":
            verify_url = verify.get("url")
            verify_timeout = verify.get("timeout", 5)

            verify_success = verify_http(
                verify_url,
                timeout=verify_timeout
            )

            if verify_success:
                recovery_success_total.labels(
                    alertname=alertname,
                    target=target
                ).inc()
                write_recovery_log(f"verify success: {alertname}")
                update_and_save_state(lock_key, time.time())
                return

            write_critical_log(f"verify failed: {alertname}")
            update_and_save_state(lock_key, time.time())
            return

        write_recovery_log(f"verify skipped: {alertname}")
        update_and_save_state(lock_key, time.time())

    except Exception as e:
        write_critical_log(f"recovery task exception: {alertname}, error={e}")
        update_and_save_state(lock_key, time.time())

    finally:
        with state_lock:
            active_recoveries.discard(lock_key)


@app.get("/")
def root():
    return {"message": "Recovery Controller Running"}


@app.get("/metrics")
def metrics():
    return Response(
        generate_latest(),
        media_type=CONTENT_TYPE_LATEST
    )

@app.post("/webhook")
def webhook(payload: dict, background_tasks: BackgroundTasks):
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
    verify = policy.get("verify", {})
    now = time.time()

    with state_lock:
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

    background_tasks.add_task(
        run_recovery_task,
        lock_key,
        alertname,
        target,
        command,
        verify
    )

    return {
        "status": "started",
        "alertname": alertname,
        "target": target,
        "message": "recovery task started in background"
    }
