import logging
from pathlib import Path


LOG_DIR = Path(__file__).resolve().parent.parent / "logs"
RECOVERY_LOG = LOG_DIR / "recovery.log"
CRITICAL_LOG = LOG_DIR / "critical.log"

LOG_FORMAT = "[%(asctime)s] [%(levelname)s] %(message)s"
DATE_FORMAT = "%Y-%m-%d %H:%M:%S"


def _create_file_logger(name: str, path: Path) -> logging.Logger:
    LOG_DIR.mkdir(parents=True, exist_ok=True)

    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)
    logger.propagate = False

    if not logger.handlers:
        handler = logging.FileHandler(path, encoding="utf-8")
        handler.setFormatter(logging.Formatter(LOG_FORMAT, DATE_FORMAT))
        logger.addHandler(handler)

    return logger


recovery_logger = _create_file_logger("recovery", RECOVERY_LOG)
critical_logger = _create_file_logger("critical", CRITICAL_LOG)


def write_recovery_log(message: str, level: str = "info") -> None:
    log_func = getattr(recovery_logger, level, recovery_logger.info)
    log_func(message)


def write_critical_log(message: str, level: str = "error") -> None:
    log_func = getattr(critical_logger, level, critical_logger.error)
    log_func(message)