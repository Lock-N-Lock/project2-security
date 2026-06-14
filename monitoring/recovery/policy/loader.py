import os
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
            raw_policy = f.read()

        policies = yaml.safe_load(raw_policy) or {}

        # 재귀적으로 dict 내부 치환
        def expand(obj):
            if isinstance(obj, dict):
                return {k: expand(v) for k, v in obj.items()}
            if isinstance(obj, list):
                return [expand(i) for i in obj]
            if isinstance(obj, str):
                return os.path.expandvars(obj)
            return obj

        policies = expand(policies)

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


def get_policy(alertname: str, force_reload: bool = False):
    policies = load_policies(force_reload=force_reload)
    return policies.get(alertname)