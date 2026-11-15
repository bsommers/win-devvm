#!/usr/bin/env python3
"""Answer the OpenBSD installer over a QEMU serial socket.

The installer's questions are matched against RULES in order; a question with a
default that matches no rule gets Enter. At the end the script drops to the
installer shell, adds the SSH key and doas rule to the new system, and halts.
Exit status: 0 = installed and halted, 1 = timeout or unexpected end.
"""
import argparse
import re
import socket
import sys
import time

ap = argparse.ArgumentParser()
ap.add_argument("--socket", required=True)
ap.add_argument("--log", required=True)
ap.add_argument("--hostname", required=True)
ap.add_argument("--user", required=True)
ap.add_argument("--password-file", required=True)
ap.add_argument("--pubkey", required=True)
ap.add_argument("--arch", required=True)
ap.add_argument("--sets", required=True, help="path of the sets on the install image, e.g. 8.0/arm64")
ap.add_argument("--timeout", type=int, default=1800)
a = ap.parse_args()

password = open(a.password_file).read().strip()
pubkey = open(a.pubkey).read().strip()

# (regex on the current prompt line, answer). First match wins.
RULES = [
    (r"\(I\)nstall, \(U\)pgrade, \(A\)utoinstall or \(S\)hell\?", "i"),
    (r"System hostname\?", a.hostname),
    (r"Password for root account\?", password),
    (r"Password for root account\? \(again\)", password),
    (r"Do you expect to run the X Window System\?", "no"),
    (r"Change the default console to com0\?", "yes"),
    (r"Setup a user\?", a.user),
    (r"Password for user .*\?", password),
    (r"Allow root ssh login\?", "no"),
    (r"Which disk is the root disk\?", "sd0"),
    (r"Use \(W\)hole disk", "w"),
    (r"Location of sets\? \(.*\) \[done\]", "done"),
    (r"Location of sets\?", "disk"),
    (r"Is the disk partition already mounted\?", "no"),
    (r"Which disk contains the install media\?", "sd1"),
    (r"Pathname to the sets\?", a.sets),
    (r"Set name\(s\)\?", "done"),
    (r"Continue without verification\?", "yes"),
    (r"Exit to \(S\)hell, \(H\)alt or \(R\)eboot\?", "s"),
]
# Installer questions end in "? " or "] "; password prompts in "(will not echo) " / "(again) ".
PROMPT = re.compile(r"(\?.*|\]|\(will not echo\)|\(again\)) $")   # "\?.*": "hostname? (short form, e.g. 'foo') "
SHELL = re.compile(r"^[\w.-]*# $")          # installer shell prompt

sock = socket.socket(socket.AF_UNIX)
deadline = time.time() + a.timeout
while True:                                  # QEMU creates the socket a moment after starting
    try:
        sock.connect(a.socket)
        break
    except OSError:
        if time.time() > deadline:
            sys.exit("no serial socket")
        time.sleep(0.5)
sock.settimeout(2.0)
log = open(a.log, "w")


def send(text):
    sock.sendall(text.encode() + b"\r")


def finish():
    """In the installer shell: install the key and doas rule, then power off."""
    home = f"/mnt/home/{a.user}"
    for cmd in (
        f"mkdir -p {home}/.ssh && echo '{pubkey}' > {home}/.ssh/authorized_keys",
        f"chmod 700 {home}/.ssh && chmod 600 {home}/.ssh/authorized_keys && chown -R 1000:1000 {home}/.ssh",
        "echo 'permit nopass keepenv :wheel' > /mnt/etc/doas.conf",
        "sync; halt -p",
    ):
        send(cmd)
        time.sleep(1.5)


buf = ""
answered_at = -1          # offset of the last prompt answered, so each is answered once
sent_shell = False
sent_tty = False
while time.time() < deadline:
    try:
        data = sock.recv(4096)
        if not data:
            break
        text = data.decode(errors="replace")
        log.write(text)
        log.flush()
        buf += text
        continue                              # keep reading until the line goes quiet
    except socket.timeout:
        pass
    line = buf.rsplit("\n", 1)[-1].replace("\r", "")
    if len(buf) == answered_at:
        continue
    if sent_shell and SHELL.search(line):
        finish()
        log.write("\n[installer halted by openbsd-install.py]\n")
        sys.exit(0)
    if a.arch == "amd64" and line.endswith("boot> ") and not sent_tty:
        sent_tty = True                       # put the kernel console on the serial port
        send("set tty com0")
        time.sleep(1)
        send("boot")
        answered_at = len(buf)
        continue
    if not PROMPT.search(line):
        continue
    answered_at = len(buf)
    for pattern, answer in RULES:
        if re.search(pattern, line):
            if answer == "s":
                sent_shell = True
            send(answer)
            break
    else:
        if line.endswith("] "):
            send("")                          # accept the default
        else:
            log.write(f"\n[no rule for prompt: {line!r}]\n")
            sys.exit(1)
    answered_at = len(buf)

sys.exit(1)
