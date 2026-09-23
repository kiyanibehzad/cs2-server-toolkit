#!/usr/bin/env python3
"""Small Source RCON client that drains every packet of a command response.

The password is read from the environment so it is absent from the process
command line. See Valve's Source RCON Protocol, including its multi-packet
response terminator convention.
"""

import argparse
import os
import socket
import struct
import sys

MAX_PACKET = 1024 * 1024
MAX_RESPONSE = 4 * 1024 * 1024


def read_exact(sock, count):
    data = bytearray()
    while len(data) < count:
        part = sock.recv(count - len(data))
        if not part:
            raise ConnectionError("RCON connection closed before response completed")
        data.extend(part)
    return bytes(data)


def read_packet(sock):
    size = struct.unpack("<i", read_exact(sock, 4))[0]
    if not 10 <= size <= MAX_PACKET:
        raise ValueError(f"invalid RCON packet size: {size}")
    raw = read_exact(sock, size)
    request_id, kind = struct.unpack("<ii", raw[:8])
    if not raw.endswith(b"\x00\x00"):
        raise ValueError("invalid RCON packet terminator")
    return request_id, kind, raw[8:-2]


def send_packet(sock, request_id, kind, body):
    payload = struct.pack("<ii", request_id, kind) + body + b"\x00\x00"
    sock.sendall(struct.pack("<i", len(payload)) + payload)


def query(host, port, password, command, timeout):
    with socket.create_connection((host, port), timeout=timeout) as sock:
        sock.settimeout(timeout)
        send_packet(sock, 10, 3, password.encode("utf-8"))
        while True:
            request_id, kind, _ = read_packet(sock)
            if request_id == -1:
                raise PermissionError("RCON authentication failed")
            if request_id == 10 and kind == 2:
                break
        send_packet(sock, 20, 2, command.encode("utf-8"))
        # Valve's multi-packet convention requests a terminator by sending
        # an empty RESPONSE_VALUE after EXECCOMMAND. A distinct ID makes the
        # terminator unambiguous even for empty command output.
        send_packet(sock, 21, 0, b"")
        output = bytearray()
        while True:
            request_id, _, body = read_packet(sock)
            if request_id == 21 or body == b"\x00\x01\x00\x00":
                break
            if request_id != 20:
                raise ValueError(f"unexpected RCON response ID: {request_id}")
            output.extend(body)
            if len(output) > MAX_RESPONSE:
                raise ValueError("RCON response exceeds 4 MiB limit")
        return output.decode("utf-8", errors="replace")


def main():
    parser = argparse.ArgumentParser(description="CS2 Source RCON client")
    parser.add_argument("-H", "--host", default="127.0.0.1")
    parser.add_argument("-P", "--port", type=int, default=27015)
    parser.add_argument("--timeout", type=float, default=5)
    parser.add_argument("command", nargs="+")
    args = parser.parse_args()
    password = os.environ.get("RCON_PASS", "")
    if not password:
        parser.error("RCON_PASS is missing")
    try:
        result = query(args.host, args.port, password, " ".join(args.command), args.timeout)
    except (OSError, ValueError, PermissionError) as exc:
        print(f"RCON error: {exc}", file=sys.stderr)
        return 1
    print(result, end="" if result.endswith("\n") else "\n")
    if "Unknown command" in result or "Unknown variable" in result:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
