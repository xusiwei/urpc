#!/usr/bin/env python3
"""Interop driver (spec 001 US5 / T037): runs the two interop quadrants.

  A) official client (this script, grpcio) → urpc echo server
  B) urpc echo client → official server (peer_server.py)

Exit code 0 = both quadrants passed. Skips (exit 77) when grpcio is missing
so environments without Python deps don't fail the build.
"""

import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))


def find_bin(name):
    for d in ("build/release", "build/debug"):
        p = os.path.join(ROOT, d, "examples", "echo", name)
        if os.path.exists(p):
            return os.path.abspath(p)
    return None


def wait_port_ok(addr, timeout=10.0):
    import socket
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            s = socket.create_connection(addr.split(":"), timeout=0.5)
            s.close()
            return True
        except OSError:
            time.sleep(0.1)
    return False


def main():
    try:
        import grpc  # noqa: F401
    except ImportError:
        print("interop: SKIP (grpcio not installed)")
        return 77

    server_bin = find_bin("urpc_echo_server")
    client_bin = find_bin("urpc_echo_client")
    if not server_bin or not client_bin:
        print("interop: SKIP (example binaries not built)")
        return 77

    failures = 0

    # ---- A) official python client → urpc server -------------------------
    # NOTE: the urpc example server prefixes echoes with nothing; the peer
    # client asserts exact round-trip of "hello from urpc".
    port_a = "51081"
    proc_s = subprocess.Popen([server_bin, "127.0.0.1:" + port_a])
    try:
        if not wait_port_ok("127.0.0.1:" + port_a):
            print("interop: urpc server did not come up")
            failures += 1
        else:
            rc = subprocess.call(
                [sys.executable, os.path.join(HERE, "peer_client.py"),
                 "127.0.0.1:" + port_a])
            if rc != 0:
                print("interop: quadrant A (official→urpc) FAILED")
                failures += 1
            else:
                print("interop: quadrant A (official→urpc) ok")
    finally:
        proc_s.terminate()
        proc_s.wait()

    # ---- B) urpc client → official python server -------------------------
    port_b = "51082"
    proc_p = subprocess.Popen(
        [sys.executable, os.path.join(HERE, "peer_server.py"), port_b])
    try:
        if not wait_port_ok("127.0.0.1:" + port_b):
            print("interop: python server did not come up")
            failures += 1
        else:
            rc = subprocess.call([client_bin, "127.0.0.1:" + port_b])
            if rc != 0:
                print("interop: quadrant B success path FAILED")
                failures += 1
            else:
                print("interop: quadrant B success path ok")
            rc = subprocess.call(
                [client_bin, "127.0.0.1:" + port_b, "--expect-error"])
            if rc != 0:
                print("interop: quadrant B error path FAILED")
                failures += 1
            else:
                print("interop: quadrant B error path ok")
    finally:
        proc_p.terminate()
        proc_p.wait()

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
