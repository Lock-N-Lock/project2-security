import requests


def verify_http(url: str, timeout: int = 5) -> bool:
    try:
        response = requests.get(url, timeout=timeout)
        return response.ok

    except Exception:
        return False
