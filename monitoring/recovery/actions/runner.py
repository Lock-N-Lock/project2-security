import subprocess
import shlex


def run_command(command: str, timeout: int = 10) -> bool:
    try:
        cmd_args = shlex.split(command)
        result = subprocess.run(
            cmd_args,
            shell=False,
            timeout=timeout,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True
        )

        return result.returncode == 0

    except Exception:
        return False