from datetime import datetime
from pathlib import Path


LOG_DIR = Path(__file__).resolve().parent.parent / "logs"
RECOVERY_LOG = LOG_DIR / "recovery.log"
CRITICAL_LOG = LOG_DIR / "critical.log"


def _write_log(path: Path, message: str) -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    with open(path, "a", encoding="utf-8") as f:
        f.write(f"[{timestamp}] {message}\n")


def write_recovery_log(message: str) -> None:
    _write_log(RECOVERY_LOG, message)


def write_critical_log(message: str) -> None:
    _write_log(CRITICAL_LOG, message)