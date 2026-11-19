#!/usr/bin/env python3
"""Helper for build-image.sh: signify verification + serial-console driver for the OpenBSD installer (stdlib + cryptography)."""
import argparse, base64, hashlib, os, re, secrets, socket, subprocess, sys, time


def die(msg):
    print(f"[openbsd] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def log(msg):
    print(f"[openbsd] {msg}", file=sys.stderr, flush=True)


def _b64_line(text, idx=1):
    return base64.b64decode(text.split("\n")[idx])


def verify(pubkey, sumsfile, sigfile, target, name):
    """signify -V -m SHA256 -p pubkey -x SHA256.sig, then check target's sha256 against the signed list."""
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    from cryptography.exceptions import InvalidSignature
    pk = _b64_line(open(pubkey).read())
    sigtxt = open(sigfile, "rb").read().decode("latin-1")
    sig = _b64_line(sigtxt)
    # signify "embedded" format: 2 header lines, then the signed message (here: the SHA256 file)
    msg = sigtxt.split("\n", 2)[2].encode("latin-1")
    if pk[:2] != b"Ed" or sig[:2] != b"Ed" or pk[2:10] != sig[2:10]:
        die("signify algorithm/keynum mismatch between pubkey and signature")
    try:
        Ed25519PublicKey.from_public_bytes(pk[10:42]).verify(sig[10:74], msg)
    except InvalidSignature:
        die("SHA256.sig signature INVALID")
    if msg != open(sumsfile, "rb").read():
        die("SHA256 file does not match the signed message")
    log("SHA256.sig: signify signature OK")
    want = None
    for line in msg.decode().splitlines():
        m = re.match(r"SHA256 \((.+)\) = ([0-9a-f]{64})$", line)
        if m and m.group(1) == name:
            want = m.group(2)
    if not want:
        die(f"{name} not in signed SHA256 list")
    h = hashlib.sha256()
    with open(target, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    if h.hexdigest() != want:
        os.remove(target)
        die(f"{name} sha256 mismatch (want {want}, got {h.hexdigest()}); removed")
    log(f"{name}: sha256 OK ({want[:16]}...)")


class Console:
    """Minimal expect over a qemu chardev unix socket."""

    def __init__(self, work, tag, args, logf):
        self.sock_path = f"{work}/{tag}-serial.sock"
        self.mon_path = f"{work}/{tag}-mon.sock"
        for p in (self.sock_path, self.mon_path):
            if os.path.exists(p):
                os.remove(p)
        self.proc = subprocess.Popen(
            ["qemu-system-x86_64", "-enable-kvm", "-cpu", "host", "-m", "2048", "-smp", "4",
             "-display", "none", "-vga", "std",
             "-chardev", f"socket,id=s0,path={self.sock_path},server=on,wait=off", "-serial", "chardev:s0",
             "-monitor", f"unix:{self.mon_path},server=on,wait=off"] + args,
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.buf = ""
        self.log = logf
        self.s = None
        for _ in range(100):
            if os.path.exists(self.sock_path):
                try:
                    self.s = socket.socket(socket.AF_UNIX)
                    self.s.connect(self.sock_path)
                    break
                except OSError:
                    self.s.close()
            time.sleep(0.1)
        if not self.s:
            die("cannot connect to qemu serial socket: " + (self.proc.stderr.read().decode() if self.proc.poll() else ""))
        self.s.setblocking(False)

    def monitor(self, cmd):
        m = socket.socket(socket.AF_UNIX)
        m.connect(self.mon_path)
        time.sleep(0.2)
        m.sendall(cmd.encode() + b"\n")
        time.sleep(0.2)
        m.close()

    def type_keys(self, text):
        keymap = {" ": "spc", "\n": "ret"}
        for ch in text:
            self.monitor("sendkey " + keymap.get(ch, ch))

    def pump(self, timeout=0.5):
        end = time.time() + timeout
        while time.time() < end:
            try:
                d = self.s.recv(65536)
            except BlockingIOError:
                time.sleep(0.05)
                continue
            if not d:
                return False
            t = d.decode("latin-1")
            self.buf += t
            self.log.write(t)
            self.log.flush()
        return True

    def send(self, text):
        self.s.sendall(text.encode())

    def expect(self, pattern, timeout=120):
        end = time.time() + timeout
        rx = re.compile(pattern)
        while time.time() < end:
            m = rx.search(self.buf)
            if m:
                self.buf = self.buf[m.end():]
                return m
            if self.proc.poll() is not None:
                self.pump(0.2)
                m = rx.search(self.buf)
                if m:
                    self.buf = self.buf[m.end():]
                    return m
                die(f"qemu exited while waiting for /{pattern}/")
            self.pump(0.5)
        die(f"timeout waiting for /{pattern}/ ; tail: {self.buf[-300:]!r}")

    def run(self, cmd, timeout=120):
        self.send(cmd + "; echo __RC=$?__\n")
        m = self.expect(r"__RC=(\d+)__\r?\n", timeout)
        return int(m.group(1))

    def close(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(10)
            except subprocess.TimeoutExpired:
                self.proc.kill()


def install(a):
    rootpw = secrets.token_urlsafe(18)
    userpw = secrets.token_urlsafe(18)
    pubkey = open(a.pubkey).read().strip()
    logf = open(f"{a.work}/serial.log", "w")
    net = ["-netdev", f"user,id=n0,hostfwd=tcp:127.0.0.1:{a.ssh_port}-:22", "-device", "virtio-net-pci,netdev=n0"]
    target = ["-drive", f"file={a.disk},if=none,id=hd0,format=qcow2", "-device", "virtio-blk-pci,drive=hd0"]
    # Phase 1: miniroot (IDE, boot disk) + target (virtio -> sd0). The boot> prompt is on VGA: type via the monitor.
    c = Console(a.work, "inst", ["-drive", f"file={a.miniroot},if=ide,format=raw"] + target + net, logf)
    try:
        log("phase 1: installer (this downloads sets from the mirror; a few minutes)")
        # The BOOT loader starts on VGA: type "set tty com0" through the monitor, then continue the boot on serial.
        time.sleep(1.5)
        c.type_keys("set tty com0\n")
        c.expect(r"boot> ", 60)
        c.send("boot\n")
        counts = {}
        # (regex, answer, max_uses); answer may be a list consumed in order (last element repeats)
        rules = [
            (r"\(I\)nstall, \(U\)pgrade, \(A\)utoinstall or \(S\)hell\? ", "i", 1),
            (r"Terminal type\? \[[^\]]*\] ", "", 1),
            (r"System hostname\? \([^)]*\) ", a.hostname, 1),
            (r"Network interface to configure\? \([^)]*\) \[\w+\]", "", 3),
            (r"IPv4 address for \w+\? \([^)]*\)[^\n]*", "autoconf", 1),
            (r"IPv6 address for \w+\? \([^)]*\)[^\n]*", "none", 1),
            (r"DNS domain name\? [^\n]*\] ", "", 1),
            (r"DNS nameservers\? [^\n]*\] ", "", 1),
            (r"Password for root account\? \((will not echo|again)\)", rootpw, 2),
            (r"Start sshd\(8\) by default\? \[\w+\] ", "yes", 1),
            (r"Do you expect to run the X Window System\? \[\w+\] ", "no", 1),
            (r"Do you want the X Window System to be started by xenodm\(1\)\? \[\w+\] ", "no", 1),
            (r"Change the default console to com0\? \[\w+\] ", "yes", 1),
            (r"Which speed should com0 use\? [^\n]*\] ", "", 1),
            (r"Setup a user\? \(enter a lower-case loginname, or 'no'\)[^\n]*\] ", a.user, 1),
            (r"Full name for user \w+\? \[[^\n]*\] ", "", 1),
            (r"Password for user \w+\? \((will not echo|again)\)", userpw, 2),
            (r"Public ssh key for root account\? \[none\] ", "", 1),
            (r"Allow root ssh login\? [^\n]*\] ", "no", 1),
            (r"What timezone are you in\? [^\n]*\] ", "UTC", 1),
            (r"Which disk is the root disk\? [^\n]*\] ", "sd0", 1),
            (r"Encrypt the root disk[^\n]*\] ", "no", 1),
            (r"Use \(W\)hole disk[^\n]*\? [^\n]*\] ", "w", 1),
            (r"Use \(A\)uto layout, \(E\)dit auto layout, or create \(C\)ustom layout\? [^\n]*\] ", "a", 1),
            (r"Which disk do you wish to initialize\? [^\n]*\] ", "done", 3),
            (r"Location of sets\? [^\n]*\] ", ["http", "done"], 2),
            (r"HTTP proxy URL\? [^\n]*\] ", "none", 1),
            (r"HTTP Server\? \([^)]*\) (\[[^\]]*\] )?", a.mirror_host.split("/")[0], 1),
            (r"Server directory\? (\[[^\]]*\] )?", "", 1),
            (r"Set name\(s\)\? [^\n]*\] ", ["-game* -xserv* -xfont*", "done"], 4),
        ]
        last_change, last_len = time.time(), 0
        end = time.time() + 3600
        done = False
        while time.time() < end and not done:
            c.pump(0.5)
            if len(c.buf) != last_len:
                last_change, last_len = time.time(), len(c.buf)
            elif time.time() - last_change > 300:
                die("installer stalled on an unknown prompt; tail: " + c.buf[-400:])
            for i, (rx, ans, mx) in enumerate(rules):
                m = re.search(rx, c.buf)
                if m and counts.get(i, 0) < mx:
                    n = counts.get(i, 0)
                    counts[i] = n + 1
                    a_ = ans[min(n, len(ans) - 1)] if isinstance(ans, list) else ans
                    c.buf = c.buf[m.end():]
                    time.sleep(0.6)
                    c.send(a_ + "\n")
                    break
            else:
                m = re.search(r"Exit to \(S\)hell, \(H\)alt or \(R\)eboot\? \[\w+\] ", c.buf)
                if m:
                    c.buf = c.buf[m.end():]
                    c.send("h\n")
                    c.expect(r"has halted|press any key|Please press any key", 60)
                    done = True
                elif re.search(r"(?i)continue without verification|signature .*(bad|invalid)|Cannot determine prefetch", c.buf):
                    die("installer reported a verification/prefetch problem: " + c.buf[-300:])
        if not done:
            die("installer did not finish within 1h; tail: " + c.buf[-300:])
        log("installer finished")
    finally:
        c.close()

    # Phase 2: boot the installed disk, finish configuration as root on the serial console.
    c = Console(a.work, "post", target + net, logf)
    try:
        log("phase 2: first boot of installed system")
        c.expect(r"login: ", 300)
        c.send("root\n")
        c.expect(r"Password:", 30)
        c.send(rootpw + "\n")
        c.expect(r"# ", 60)
        c.send("\n")
        c.expect(r"# ", 30)
        steps = [
            ("authorized_keys", "mkdir -p /home/{u}/.ssh && printf '%s\\n' '{k}' > /home/{u}/.ssh/authorized_keys && chown -R {u}:{u} /home/{u}/.ssh && chmod 700 /home/{u}/.ssh && chmod 600 /home/{u}/.ssh/authorized_keys".format(u=a.user, k=pubkey), 30),
            ("sshd keys-only", "{ printf 'PasswordAuthentication no\\nKbdInteractiveAuthentication no\\nPermitRootLogin no\\n'; cat /etc/ssh/sshd_config; } > /root/sshd_config.new && cat /root/sshd_config.new > /etc/ssh/sshd_config && rm /root/sshd_config.new && sshd -t && rcctl restart sshd", 60),
            ("doas nopass for wheel", "echo 'permit nopass keepenv :wheel' >> /etc/doas.conf", 30),
            ("network up", "ftp -o /dev/null -V https://cdn.openbsd.org/ 2>&1 | tail -1; cat /etc/installurl", 60),
        ]
        for name, cmd, to in steps:
            log(name)
            rc = c.run(cmd, to)
            if rc != 0 and name != "network up":
                die(f"step '{name}' failed rc={rc}")
        for pkg in a.packages.split():
            log(f"pkg_add {pkg} (can take a long time)")
            rc = c.run(f"pkg_add -I {pkg}", 3600)
            if rc != 0:
                log(f"WARNING: pkg_add {pkg} failed rc={rc}")
        log("ncurses: base libcurses is ncurses-derived; trying optional pkg")
        c.run("pkg_add -I ncurses", 600)
        # verify from the host over ssh, before locking down console logins
        log("verifying ssh from host")
        key = a.pubkey[:-4] if a.pubkey.endswith(".pub") else a.pubkey
        r = None
        for _ in range(20):
            r = subprocess.run(["ssh", "-i", key, "-p", str(a.ssh_port), "-o", "BatchMode=yes", "-o", "PasswordAuthentication=no",
                                "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "LogLevel=ERROR",
                                f"{a.user}@127.0.0.1", "uname -a; doas id -un; for t in git rustc cargo qemu-system-x86_64; do command -v $t || echo missing:$t; done"],
                               capture_output=True, text=True, timeout=60)
            if r.returncode == 0:
                break
            time.sleep(3)
        if r.returncode != 0:
            die("ssh as %s failed: %s" % (a.user, r.stderr))
        log("ssh OK:\n" + r.stdout)
        c.run("usermod -p '*' root; usermod -p '*' %s; rm -f /root/.history; sync" % a.user, 30)
        c.send("halt -p\n")
        c.proc.wait(120)
    finally:
        c.close()
    log("done")


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    v = sub.add_parser("verify")
    for n in ("pubkey", "sums", "sig", "target", "name"):
        v.add_argument(n)
    i = sub.add_parser("install")
    for n in ("work", "miniroot", "disk", "rel", "mirror-host", "user", "pubkey", "packages"):
        i.add_argument("--" + n, required=True)
    i.add_argument("--hostname", default="openbsd")
    i.add_argument("--ssh-port", type=int, default=2299)
    a = p.parse_args()
    if a.cmd == "verify":
        verify(a.pubkey, a.sums, a.sig, a.target, a.name)
    else:
        a.mirror_host = a.mirror_host
        install(a)


if __name__ == "__main__":
    main()
