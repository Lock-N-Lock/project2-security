import subprocess
import shlex

from utils.logger import write_critical_log, write_recovery_log


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

        stdout = (result.stdout or "").strip()
        stderr = (result.stderr or "").strip()

        if stdout:
            for line in stdout.splitlines():
                write_recovery_log(f"action stdout: {line}")

        if stderr:
            for line in stderr.splitlines():
                write_recovery_log(f"action stderr: {line}")

        if result.returncode != 0:
            write_critical_log(
                f"command failed: {command}, stderr={stderr}"
            )

        return result.returncode == 0

    except subprocess.TimeoutExpired:
        write_critical_log(
            f"command timeout: {command}"
        )
        return False

    except Exception as e:
        write_critical_log(
            f"command exception: {command}, error={e}"
        )
        return False