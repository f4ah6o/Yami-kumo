#!/usr/bin/env python3
"""Send one command to the opt-in Ubuntu Settings recovery controller."""
from __future__ import annotations

import argparse
import socket
import struct
import sys

COMMANDS = {"status": b"s", "receipt": b"t", "inspect-native": b"z", "prefix": b"b", "stage": b"j", "owned": b"o", "reconcile": b"d", "watermark": b"w", "retire": b"e", "generation": b"n", "advance": b"g", "poll": b"p", "apply": b"a", "retry-ack": b"r", "resolve-release": b"k", "resume": b"u", "cutoff": b"c", "stop": b"q", "geometry-submit": b"v", "geometry-handoff": b"h"}
GEOMETRY_REPLIES = {
    "geometry-submit": (b"G", "native geometry receipt checked for this step; scene, record application and shutdown are not implied"),
    "geometry-handoff": (b"H", "original text receipt retained by the route and owner; application, scene and shutdown are not implied"),
}
REPLIES = {
    b"S": "suspended; owner and host retained",
    b"N": "no suspended owner; inspect the application's reason log",
    b"B": "one record retained in the local buffer",
    b"I": "no record returned; this is not a cutoff or quiescence proof",
    b"M": "one commit reflected in the model; scene and caret not published",
    b"F": "one observation applied to the original field; scene and caret not published",
    b"A": "receipt acknowledged; application and shutdown are not implied",
    b"U": "one receipt dispatched; scene and shutdown are not implied",
    b"V": "one bounded step completed; scene and shutdown are not implied",
    b"K": "host acknowledged the receipt; owner application is not implied",
    b"J": "text session applied; model and geometry are not implied",
    b"Y": "entered target recorded and acknowledged; scene and shutdown are not implied",
    b"P": "non-input platform event handled locally; geometry and shutdown are not implied",
    b"H": "pointer move passed local dispatch without a pending action; scene and geometry are not implied",
    b"G": "native adapter acknowledged an unsupported record under its own policy; scene and shutdown are not implied",
    b"O": "completed local frame prefix compacted; native cutoff and shutdown are not implied",
    b"Z": "owned text observation applied without a model action; geometry is not implied",
    b"X": "local retained prefix resolved; this is not native proof or permission to ACK",
    b"Q": "local retained prefix unresolved or unavailable; owner remains retained",
    b"L": "terminal field applied; its model action remains required",
    b"T": "destroyed event validated for the original owner; shutdown is not implied",
    b"W": "owned text reconciled; scene and shutdown are not implied",
    b"C": "text cutoff completed; host shutdown is not yet authorized",
    b"D": "proved-complete host stopped",
    b"R": "stop refused; owner and host remain retained",
    b"E": "step refused or failed; owner and host remain retained",
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", help="private socket path printed by the Settings process")
    parser.add_argument("command", choices=COMMANDS)
    parser.add_argument("--sequence", type=int, help="positive record sequence or continuation generation")
    args = parser.parse_args()
    if args.command in ("apply", "retry-ack", "resolve-release", "retire", "resume", "advance", "stage", "reconcile") and (args.sequence is None or not 0 < args.sequence < 2**63):
        parser.error("apply, retry-ack, resolve-release, retire, resume, advance, stage and reconcile require a positive --sequence")
    if args.command not in ("apply", "retry-ack", "resolve-release", "retire", "resume", "advance", "stage", "reconcile") and args.sequence is not None:
        parser.error("--sequence is not valid for this command")
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as peer:
            peer.settimeout(3.0)
            peer.connect(args.path)
            payload = COMMANDS[args.command]
            if args.command in ("apply", "retry-ack", "resolve-release", "retire", "resume", "advance", "stage", "reconcile"):
                payload += struct.pack("!q", args.sequence)
            peer.sendall(payload)
            result = peer.recv(1)
            sequence = None
            if args.command in ("status", "receipt", "inspect-native", "generation", "owned", "watermark") and result in (b"S", b"N"):
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
    if args.command in GEOMETRY_REPLIES and result not in (GEOMETRY_REPLIES[args.command][0], b"E"):
        print("geometry control returned an unexpected response; owner and host remain unresolved", file=sys.stderr)
        return 2
    if args.command == "inspect-native" and result not in (b"S", b"E"):
        print("native inspection returned an unexpected response; owner and host remain unresolved", file=sys.stderr)
        return 2
    message = (GEOMETRY_REPLIES[args.command][1]
               if args.command in GEOMETRY_REPLIES and result == GEOMETRY_REPLIES[args.command][0]
               else REPLIES.get(result))
    if message is None:
        print("control endpoint returned an unknown or empty response", file=sys.stderr)
        return 2
    print(message)
    if sequence is not None:
        label = {"receipt": "native receipt sequence", "inspect-native": "observed native head sequence", "owned": "owned delivery sequence", "generation": "continuation generation", "watermark": "completed frame candidate watermark"}.get(args.command, "next text sequence")
        missing = 'none observed; not a quiescence proof' if args.command == 'inspect-native' else 'none or non-text prefix'
        print(f"{label}: {sequence or missing}")
    return 2 if result in (b"E", b"R") else 0


if __name__ == "__main__":
    raise SystemExit(main())
