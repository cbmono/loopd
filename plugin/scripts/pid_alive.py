# pid_alive.py — is a pid a live PROCESS? The registry keeps listing a session `working` or
# `blocked` after its process died, so only a pid answers. EPERM means the process EXISTS;
# only ESRCH reads dead. Imported by agent-sessions.sh, its -classify.py and session-handoff.sh.
#   python3 pid_alive.py <pid|->   (`-`: the pid of the `claude agents` row JSON on stdin)
# Exit 0 alive · 1 not, a non-pid or an unreadable row. Shell callers: `agent-sessions.sh alive`.
import json, os, sys


def alive(pid):
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except PermissionError:
        return True
    except OSError:
        return False
    return True


if __name__ == "__main__":
    try:
        sys.exit(0 if alive(json.load(sys.stdin).get("pid") if sys.argv[1] == "-" else int(sys.argv[1])) else 1)
    except Exception:
        sys.exit(1)
