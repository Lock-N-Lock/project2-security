import subprocess


def run_command(command: str, timeout: int = 10) -> bool:
    try:
        result = subprocess.run(
            command,
            shell=True,
            timeout=timeout,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True
        )

        return result.returncode == 0

    except Exception:
        return False