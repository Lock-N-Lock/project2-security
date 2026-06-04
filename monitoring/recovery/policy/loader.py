import yaml
from pathlib import Path


POLICY_PATH = Path(__file__).resolve().parent.parent / "config" / "recovery_map.yml"


def load_policies():
    with open(POLICY_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def get_policy(alertname: str):
    policies = load_policies()
    return policies.get(alertname)