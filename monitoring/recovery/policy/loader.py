import yaml
from pathlib import Path

from utils.logger import write_critical_log, write_recovery_log


POLICY_PATH = Path(__file__).resolve().parent.parent / "config" / "recovery_map.yaml"

_policy_cache = None


def load_policies(force_reload: bool = False):
    global _policy_cache

    if _policy_cache is not None and not force_reload:
        return _policy_cache

    try:
        with open(POLICY_PATH, "r", encoding="utf-8") as f:
            policies = yaml.safe_load(f) or {}

        if not isinstance(policies, dict):
            write_critical_log(
                f"invalid policy format: expected dict, got {type(policies).__name__}"
            )
            _policy_cache = {}
            return _policy_cache

        _policy_cache = policies
        write_recovery_log("recovery policy loaded")
        return _policy_cache

    except FileNotFoundError:
        write_critical_log(f"policy file not found: {POLICY_PATH}")

    except yaml.YAMLError as e:
        write_critical_log(f"invalid policy yaml: {e}")

    except OSError as e:
        write_critical_log(f"failed to read policy file: {e}")

    _policy_cache = {}
    return _policy_cache


def get_policy(alertname: str):
    policies = load_policies()
    return policies.get(alertname)