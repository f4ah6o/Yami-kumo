#!/usr/bin/env python3
"""Send one command to the opt-in Ubuntu Settings recovery controller."""
from __future__ import annotations

import argparse
import socket
import struct
import sys

COMMANDS = {"status": b"s", "receipt": b"t", "poll": b"p", "apply": b"a", "retry-ack": b"r", "cutoff": b"c", "stop": b"q"}
REPLIES = {
    b"S": "suspended; owner and host retained",
    b"N": "no suspended owner; inspect the application's reason log",
    b"B": "one record retained in the local buffer",
    b"I": "no record returned; this is not a cutoff or quiescence proof",
    b"M": "one commit reflected in the model; scene and caret not published",
    b"F": "one observation applied to the original field; scene and caret not published",
    b"A": "receipt acknowledged; application and shutdown are not implied",
    b"C": "text cutoff completed; host shutdown is not yet authorized",
    b"D": "proved-complete host stopped",
    b"R": "stop refused; owner and host remain retained",
    b"E": "step refused or failed; owner and host remain retained",
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", help="private socket path printed by the Settings process")
    parser.add_argument("command", choices=COMMANDS)
    parser.add_argument("--sequence", type=int, help="positive text or native sequence; required for apply and retry-ack")
    args = parser.parse_args()
    if args.command in ("apply", "retry-ack") and (args.sequence is None or not 0 < args.sequence < 2**63):
        parser.error("apply and retry-ack require --sequence with the current positive sequence")
    if args.command not in ("apply", "retry-ack") and args.sequence is not None:
        parser.error("--sequence is only valid with apply or retry-ack")
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as peer:
            peer.settimeout(3.0)
            peer.connect(args.path)
            payload = COMMANDS[args.command]
            if args.command in ("apply", "retry-ack"):
                payload += struct.pack("!q", args.sequence)
            peer.sendall(payload)
            result = peer.recv(1)
            sequence = None
            if args.command in ("status", "receipt") and result in (b"S", b"N"):
                data = b""
                while len(data) < 8:
                    chunk = peer.recv(8 - len(data))
                    if not chunk:
                        raise OSError("truncated status response")
                    data += chunk
                sequence = struct.unpack("!q", data)[0]
    except OSError as error:
        print(f"control request failed: {error}; outcome may be unknown, inspect status before retry", file=sys.stderr)
        return 2
    message = REPLIES.get(result)
    if message is None:
        print("control endpoint returned an unknown or empty response", file=sys.stderr)
        return 2
    print(message)
    if sequence is not None:
        label = "native receipt sequence" if args.command == "receipt" else "next text sequence"
        print(f"{label}: {sequence or 'none or non-text prefix'}")
    return 2 if result in (b"E", b"R") else 0


if __name__ == "__main__":
    raise SystemExit(main())
