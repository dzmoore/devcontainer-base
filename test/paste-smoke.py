#!/usr/bin/env python3
"""PTY paste regression test for the devcontainer shell.

Spawns `devcontainer exec --container-id <id> bash` under a real PTY and
verifies that multi-line paste (raw and bracketed), a heredoc, TERM fallback,
`stty -ixon`, and bracketed paste all work.

Usage: python3 test/paste-smoke.py --container-id <id> [--term TERM ...]
"""

import argparse
import os
import pty
import select
import shutil
import sys
import time


def drain(fd, seconds):
    out = b""
    end = time.time() + seconds
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], 0.1)
        if not ready:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        out += chunk
    return out


def read_until(fd, needle, timeout):
    out = b""
    end = time.time() + timeout
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], 0.1)
        if not ready:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        out += chunk
        if needle in out:
            return out, True
    return out, False


def run_scenario(container_id, term):
    cmd = ["devcontainer", "exec", "--container-id", container_id, "bash"]
    pid, fd = pty.fork()
    if pid == 0:
        env = os.environ.copy()
        env["TERM"] = term
        env["COLUMNS"] = "120"
        env["LINES"] = "40"
        os.execvpe(cmd[0], cmd, env)

    out = drain(fd, 2.0)
    os.write(fd, b"printf 'READY_%s\\n' OK\n")
    chunk, ready = read_until(fd, b"READY_OK", 4.0)
    out += chunk

    # Raw multi-line paste. The markers are generated with printf so the
    # shell's command echo cannot satisfy the assertion by itself.
    os.write(
        fd,
        b"printf 'PASTE_%s\\n' ONE\nprintf 'PASTE_%s\\n' TWO\n",
    )
    out += drain(fd, 2.0)

    # Bracketed paste, as Ghostty/iTerm2 send it.
    os.write(
        fd,
        b"\x1b[200~printf 'PASTE_BRACKET_%s\\n' ONE\n"
        b"printf 'PASTE_BRACKET_%s\\n' TWO\n\x1b[201~",
    )
    out += drain(fd, 2.0)

    # Multi-line heredoc. The command substitution keeps the literal marker
    # out of the echoed command while producing it in the file/output.
    os.write(
        fd,
        b"cat <<EOF >/tmp/paste-smoke-heredoc\nHEREDOC_$(printf OK)\nEOF\n"
        b"cat /tmp/paste-smoke-heredoc\n",
    )
    out += drain(fd, 2.0)

    # Verify the terminal hardening took effect.
    os.write(
        fd,
        b"printf 'TERM_%s=%s\\n' VALUE \"$TERM\"; "
        b"stty -a | tr ';' '\\n' | grep -q -- '-ixon' && printf 'IXON_%s\\n' OFF; "
        b"bind -v | grep -q 'enable-bracketed-paste on' && printf 'BP_%s\\n' ON\n",
    )
    out += drain(fd, 2.0)

    os.write(fd, b"exit\n")
    out += drain(fd, 1.0)
    try:
        os.close(fd)
    except OSError:
        pass
    for _ in range(30):
        try:
            waited, _ = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            waited = pid
        if waited:
            break
        time.sleep(0.1)
    else:
        try:
            os.kill(pid, 9)
        except OSError:
            pass
        try:
            os.waitpid(pid, 0)
        except ChildProcessError:
            pass

    text = out.decode("utf-8", "replace")
    checks = {
        "ready": ready,
        "raw paste": "PASTE_ONE" in text and "PASTE_TWO" in text,
        "bracketed paste": "PASTE_BRACKET_ONE" in text
        and "PASTE_BRACKET_TWO" in text,
        "heredoc": "HEREDOC_OK" in text,
        "TERM fallback": "TERM_VALUE=xterm-256color" in text,
        "stty -ixon": "IXON_OFF" in text,
        "bracketed paste enabled": "BP_ON" in text,
    }
    return checks, text


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--container-id", required=True)
    parser.add_argument(
        "--term",
        action="append",
        default=None,
        help="TERM value to test (repeatable); defaults to ghostty, dumb, xterm-256color",
    )
    args = parser.parse_args()

    if not shutil.which("devcontainer"):
        print("FAIL: devcontainer CLI not found", file=sys.stderr)
        return 1

    terms = args.term or ["xterm-ghostty", "dumb", "xterm-256color"]
    failures = 0
    for term in terms:
        checks, text = run_scenario(args.container_id, term)
        bad = [name for name, ok in checks.items() if not ok]
        if bad:
            failures += 1
            print(f"FAIL [{term}]: {', '.join(bad)}")
            print("--- tail ---")
            print(text[-1200:])
        else:
            print(f"PASS [{term}]: {', '.join(checks)}")

    if failures:
        print(f"PASTE SMOKE FAILED ({failures} scenario(s))")
        return 1
    print("PASTE SMOKE PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
