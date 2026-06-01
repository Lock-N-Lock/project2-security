import requests


def verify_http(url: str, timeout: int = 5) -> bool:
    try:
        response = requests.get(url, timeout=timeout)

        if response.status_code == 200:
            return True

        return False

    except Exception:
        return False