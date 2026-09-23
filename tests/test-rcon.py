#!/usr/bin/env python3
"""Protocol-level regression cases for split Source RCON responses."""
import os
import socket
import struct
import subprocess
import threading
import unittest
from pathlib import Path

CLIENT = Path(__file__).resolve().parents[1] / "scripts/cs2-rcon.py"


def receive(sock):
    size = struct.unpack("<i", sock.recv(4))[0]
    data = bytearray()
    while len(data) < size:
        data.extend(sock.recv(size - len(data)))
    return struct.unpack("<ii", data[:8]) + (bytes(data[8:-2]),)


def send(sock, request_id, kind, body=b""):
    payload = struct.pack("<ii", request_id, kind) + body + b"\0\0"
    sock.sendall(struct.pack("<i", len(payload)) + payload)


class RconTests(unittest.TestCase):
    def run_client(self, fail_auth=False, unknown=False):
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        port = listener.getsockname()[1]
        errors = []

        def server():
            try:
                conn, _ = listener.accept()
                with conn:
                    self.assertEqual(receive(conn), (10, 3, b"secret"))
                    if fail_auth:
                        send(conn, -1, 2)
                        return
                    send(conn, 10, 0)
                    send(conn, 10, 2)
                    self.assertEqual(receive(conn), (20, 2, b"find weapon"))
                    self.assertEqual(receive(conn), (21, 0, b""))
                    if unknown:
                        send(conn, 20, 0, b"Unknown command 'find weapon'!")
                    else:
                        send(conn, 20, 0, b"a" * 3500)
                        send(conn, 20, 0, b"b" * 3500)
                    send(conn, 21, 0)
            except Exception as exc:
                errors.append(exc)
            finally:
                listener.close()

        worker = threading.Thread(target=server)
        worker.start()
        env = os.environ.copy()
        env["RCON_PASS"] = "secret"
        result = subprocess.run(
            ["python3", str(CLIENT), "-H", "127.0.0.1", "-P", str(port), "find weapon"],
            env=env, capture_output=True, text=True, timeout=5,
        )
        worker.join(timeout=5)
        self.assertFalse(errors, errors)
        return result

    def test_split_response(self):
        result = self.run_client()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "a" * 3500 + "b" * 3500 + "\n")

    def test_auth_failure(self):
        self.assertNotEqual(self.run_client(fail_auth=True).returncode, 0)

    def test_unknown_command(self):
        self.assertNotEqual(self.run_client(unknown=True).returncode, 0)


if __name__ == "__main__":
    unittest.main()
