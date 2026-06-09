import requests

from utils.logger import write_critical_log


def verify_http(url: str, timeout: int = 5) -> bool:
    try:
        response = requests.get(url, timeout=timeout)

        if not response.ok:
            write_critical_log(
                f"http verify failed: {url}, status={response.status_code}"
            )

        return response.ok

    except requests.Timeout:
        write_critical_log(
            f"http verify timeout: {url}"
        )
        return False

    except Exception as e:
        write_critical_log(
            f"http verify exception: {url}, error={e}"
        )
        return False