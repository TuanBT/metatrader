"""
SSH helper — run commands on the remote MT5 Windows server.
"""
import subprocess
import shlex

from config import SSH_HOST, SSH_USER, SSH_PASS


def ssh_cmd(cmd: str, timeout: int = 30) -> str:
    """Execute a command on the remote server via SSH.
    Returns stdout as string. Raises on failure."""
    full = (
        f'sshpass -p {shlex.quote(SSH_PASS)} '
        f'ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 '
        f'{SSH_USER}@{SSH_HOST} {shlex.quote(cmd)}'
    )
    r = subprocess.run(
        full, shell=True, capture_output=True, text=True, timeout=timeout
    )
    if r.returncode != 0 and r.stderr and "WARNING" not in r.stderr:
        raise RuntimeError(f"SSH failed: {r.stderr.strip()}")
    return r.stdout.strip()


def ssh_powershell(ps_cmd: str, timeout: int = 30) -> str:
    """Execute a PowerShell command on the remote server."""
    cmd = f'powershell -Command "{ps_cmd}"'
    return ssh_cmd(cmd, timeout=timeout)


def read_remote_log(log_path: str, tail: int = 100, encoding: str = "Unicode") -> str:
    """Read tail of a remote UTF-16 log file using PowerShell."""
    ps = (
        f"Get-Content '{log_path}' -Encoding {encoding} -Tail {tail}"
    )
    return ssh_powershell(ps, timeout=30)
