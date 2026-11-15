#!/usr/bin/env python3
"""Talk to a QEMU unix socket.

  qemu-sock.py <socket> "<command>"   send one monitor command, print the reply
  qemu-sock.py <socket>               attach interactively (serial console); Ctrl-C leaves
"""
import select
import socket
import sys
import time


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    sock = socket.socket(socket.AF_UNIX)
    sock.connect(sys.argv[1])
    if len(sys.argv) > 2:
        time.sleep(0.2)
        sock.sendall(sys.argv[2].encode() + b"\n")
        time.sleep(0.5)
        sock.setblocking(False)
        try:
            sys.stdout.write(sock.recv(65536).decode(errors="replace"))
        except BlockingIOError:
            pass
        return
    try:
        while True:
            ready, _, _ = select.select([sock, sys.stdin], [], [])
            if sock in ready:
                data = sock.recv(4096)
                if not data:
                    break
                sys.stdout.write(data.decode(errors="replace"))
                sys.stdout.flush()
            if sys.stdin in ready:
                line = sys.stdin.readline()
                if not line:
                    break
                sock.sendall(line.replace("\n", "\r").encode())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
