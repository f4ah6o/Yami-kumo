#!/usr/bin/env python3
"""Supervise one fresh Node/Chrome process group and retain its raw evidence."""

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import sys
import time
import uuid

REPORT_CAPACITY = 512 * 1024
LOG_CAPACITY = 1024 * 1024
WRITE_CHUNK = 64 * 1024
OWNED_DEADLINE_SECONDS = 105


def now():
    return datetime.now(timezone.utc).isoformat()


def write_all(fd, raw, offset):
    written = 0
    while written < len(raw):
        count = os.pwrite(fd, raw[written:], offset + written)
        if count <= 0:
            raise OSError("evidence write made no progress")
        written += count


def read_exact(fd, length, offset=0):
    chunks = []
    read = 0
    while read < length:
        part = os.pread(fd, length - read, offset + read)
        if not part:
            raise OSError("evidence readback was short")
        chunks.append(part)
        read += len(part)
    return b"".join(chunks)


def reserve_file(path, capacity, fill):
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o600)
    block = bytes([fill]) * min(WRITE_CHUNK, capacity)
    try:
        offset = 0
        while offset < capacity:
            part = block[: min(len(block), capacity - offset)]
            write_all(fd, part, offset)
            offset += len(part)
        os.fsync(fd)
        if os.fstat(fd).st_size != capacity:
            raise OSError("evidence reservation size differs")
        return fd
    except BaseException:
        os.close(fd)
        raise


def write_json_slot(fd, capacity, value):
    payload = (json.dumps(value, indent=2) + "\n").encode("utf-8")
    if len(payload) > capacity:
        raise OSError("outer execution receipt exceeds reserved capacity")
    padded = payload + (b" " * (capacity - len(payload)))
    write_all(fd, padded, 0)
    os.fsync(fd)
    observed = read_exact(fd, capacity)
    if observed != padded or json.loads(observed) != value:
        raise OSError("outer execution receipt readback differs")


class ReceiptStore:
    """Double-buffered, physically reserved outer supervisor receipt."""

    def __init__(self, output, initial):
        self.paths = [output / "execution.json", output / "execution-checkpoint.json"]
        self.fds = []
        self.next = 1
        try:
            for path in self.paths:
                fd = reserve_file(path, REPORT_CAPACITY, 0x20)
                self.fds.append(fd)
                write_json_slot(fd, REPORT_CAPACITY, initial)
        except BaseException:
            self.close()
            raise

    def checkpoint(self, value):
        index = self.next
        write_json_slot(self.fds[index], REPORT_CAPACITY, value)
        self.next = 1 - index

    def finish(self, value):
        self.checkpoint(value)
        write_json_slot(self.fds[0], REPORT_CAPACITY, value)

    def close(self):
        first = None
        while self.fds:
            try:
                os.close(self.fds.pop())
            except OSError as error:
                first = first or error
        if first:
            raise first


class RawCapture:
    def __init__(self, fd, capacity=LOG_CAPACITY):
        self.fd = fd
        self.capacity = capacity
        self.length = 0
        self.retained = 0
        self.full_hash = hashlib.sha256()
        self.retained_hash = hashlib.sha256()
        self.truncated = False

    def append(self, raw):
        self.length += len(raw)
        self.full_hash.update(raw)
        keep = raw[: max(0, self.capacity - self.retained)]
        if keep:
            write_all(self.fd, keep, self.retained)
            self.retained_hash.update(keep)
            self.retained += len(keep)
        if len(keep) != len(raw):
            self.truncated = True

    def finalize(self):
        os.fsync(self.fd)
        os.ftruncate(self.fd, self.retained)
        os.fsync(self.fd)
        readback = read_exact(self.fd, self.retained)
        digest = hashlib.sha256(readback).hexdigest()
        if digest != self.retained_hash.hexdigest():
            raise OSError("outer raw log readback hash differs")
        return {
            "observed_length": self.length,
            "retained_length": self.retained,
            "sha256": self.full_hash.hexdigest(),
            "retained_sha256": digest,
            "truncated": self.truncated,
            "verified": not self.truncated,
        }


def group_exists(group_id):
    try:
        os.killpg(group_id, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def signal_owned_group(group_id, sig):
    if not isinstance(group_id, int) or group_id <= 1:
        return False
    try:
        os.killpg(group_id, sig)
        return True
    except ProcessLookupError:
        return False


def stop_and_reap(proc, group_id, result):
    """Terminate/reap only the new session and process group from this Popen."""
    if proc is None or group_id is None:
        return (proc.poll() if proc is not None else None), True
    if proc.poll() is None or group_exists(group_id):
        result["group_cleanup_signal_sent"] = signal_owned_group(group_id, signal.SIGTERM)
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass
    if group_exists(group_id):
        result["group_kill_signal_sent"] = signal_owned_group(group_id, signal.SIGKILL)
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
    until = time.monotonic() + 1.0
    while group_exists(group_id) and time.monotonic() < until:
        time.sleep(0.025)
    return proc.poll(), not group_exists(group_id)


def launch_and_record(command, cwd, env, record, receipts, popen_factory=subprocess.Popen, captures=None):
    """Ensure any failure after Popen still cleans only that call's new group."""
    proc = popen_factory(command, cwd=cwd, env=env, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, bufsize=0, start_new_session=True)
    group_id = proc.pid
    accepted = False
    try:
        record.update(pid=proc.pid, expected_process_group=group_id, node_started_at=now(),
                      process_group_verified=False)
        actual_group = os.getpgid(proc.pid)
        if actual_group != group_id:
            raise RuntimeError("Node process is not leader of its fresh process group")
        record.update(process_group=actual_group, process_group_verified=True)
        receipts.checkpoint(record)
        accepted = True
        return proc, group_id
    finally:
        if not accepted:
            try:
                returncode, group_gone = stop_and_reap(proc, group_id, record)
            except BaseException as error:
                returncode, group_gone = None, False
                record["group_cleanup_error"] = str(error)
            if captures is not None:
                try:
                    drain_pipes(proc, captures)
                except BaseException as error:
                    record["pipe_drain_error"] = str(error)
                    group_gone = False
            record.update(returncode=returncode, node_returncode=returncode,
                          node_finished_at=now(), owned_group_gone=group_gone, status="unverified")


def drain_pipes(proc, captures, timeout=1.0):
    if proc is None or proc.stdout is None or proc.stderr is None:
        return
    selector = selectors.DefaultSelector()
    streams = {proc.stdout: captures[0], proc.stderr: captures[1]}
    try:
        for stream in streams:
            try:
                os.set_blocking(stream.fileno(), False)
                selector.register(stream, selectors.EVENT_READ)
            except (OSError, ValueError):
                pass
        end = time.monotonic() + timeout
        while selector.get_map() and time.monotonic() < end:
            for key, _ in selector.select(timeout=0.05):
                try:
                    chunk = os.read(key.fileobj.fileno(), 64 * 1024)
                except BlockingIOError:
                    continue
                if chunk:
                    streams[key.fileobj].append(chunk)
                else:
                    selector.unregister(key.fileobj)
                    key.fileobj.close()
    finally:
        selector.close()


def monitor_owned(proc, captures, cancelled, deadline):
    selector = selectors.DefaultSelector()
    streams = {proc.stdout: captures[0], proc.stderr: captures[1]}
    try:
        for stream in streams:
            os.set_blocking(stream.fileno(), False)
            selector.register(stream, selectors.EVENT_READ)
        while selector.get_map() or proc.poll() is None:
            if cancelled():
                raise InterruptedError(cancelled())
            if time.monotonic() >= deadline:
                raise TimeoutError("Owned Node/Chrome deadline expired")
            for key, _ in selector.select(timeout=0.1):
                chunk = os.read(key.fileobj.fileno(), 64 * 1024)
                if chunk:
                    streams[key.fileobj].append(chunk)
                else:
                    selector.unregister(key.fileobj)
                    key.fileobj.close()
        return proc.wait(timeout=2)
    finally:
        selector.close()


def report_is_observed(report, token):
    if not isinstance(report, dict) or report.get("status") != "observed":
        return False
    if report.get("run_token") != token or report.get("measurement_complete") is not True:
        return False
    cases = report.get("cases")
    if (not isinstance(cases, list) or len(cases) != 7
            or any(not isinstance(case, dict) or case.get("status") != "observed" for case in cases)):
        return False
    browser = report.get("browser") or {}
    if (browser.get("returncode") != 0 or browser.get("signal") is not None
            or browser.get("closed_returncode") != 0 or browser.get("closed_signal") is not None):
        return False
    for name in ("stdout", "stderr"):
        log = (browser.get("logs") or {}).get(name) or {}
        if log.get("verified") is not True or log.get("truncated") is not False:
            return False
        if log.get("observed_length") != log.get("retained_length"):
            return False
    return True


def parse_node_summary(raw):
    """Read the runner's small final JSON line without decoding log chunks."""
    for line in reversed(raw.splitlines()):
        if not line or len(line) > 4096:
            continue
        try:
            value = json.loads(line)
        except (UnicodeDecodeError, ValueError):
            continue
        if isinstance(value, dict) and value.get("status") in ("observed", "unverified"):
            return value
    return None


def main(argv=None, *, popen_factory=subprocess.Popen, receipts_factory=ReceiptStore):
    if os.name != "posix":
        raise RuntimeError("owned browser group requires a POSIX host")
    if argv is None:
        argv = sys.argv[1:]
    if len(argv) != 1:
        raise RuntimeError("usage: measure_button_phases.py NEW_OUTPUT")
    root = Path(__file__).resolve().parents[1]
    output = Path(argv[0]).resolve()
    output.mkdir(parents=True, exist_ok=False)
    measurement = output / "measurement"
    token = str(uuid.uuid4())
    node = shutil.which("node")
    command = [node, str(root / "scripts/measure-button-phases.mjs"), str(measurement)] if node else []
    result = {
        "schema_version": 1, "kind": "owned-kumo-phase-supervisor", "status": "unverified",
        "run_token": token, "started_at": now(), "command": command, "cwd": str(root),
        "pid": None, "process_group": None, "measurement_directory": str(measurement),
    }
    receipts = None
    log_fds = []
    proc = None
    group_id = None
    stdout_capture = stderr_capture = None
    returncode = None
    group_gone = True
    timed_out = False
    cancelled_reason = None
    retention_error = None
    signal_event = {"value": None}
    old_handlers = {}

    def handler(signum, _frame):
        signal_event["value"] = "Supervisor received " + signal.Signals(signum).name

    for sig in (signal.SIGINT, signal.SIGTERM):
        old_handlers[sig] = signal.signal(sig, handler)
    try:
        # The runner writes no child process until all outer evidence capacity exists.
        receipts = receipts_factory(output, result)
        for filename in ("node.stdout", "node.stderr"):
            log_fds.append(reserve_file(output / filename, LOG_CAPACITY, 0xA5))
        stdout_capture, stderr_capture = (RawCapture(fd) for fd in log_fds)
        result["outer_reservations"] = {"receipt_bytes_each": REPORT_CAPACITY, "raw_log_bytes_each": LOG_CAPACITY}
        receipts.checkpoint(result)
        if not command:
            raise RuntimeError("Node executable was not found")
        env = os.environ.copy()
        env.update(KUMO_PHASE_SUPERVISOR_PID=str(os.getpid()), KUMO_PHASE_RUN_TOKEN=token,
                   KUMO_PHASE_MEASUREMENT_DIR=str(measurement))
        started = time.monotonic()
        try:
            proc, group_id = launch_and_record(command, root, env, result, receipts, popen_factory,
                                               (stdout_capture, stderr_capture))
            returncode = monitor_owned(proc, (stdout_capture, stderr_capture),
                                       lambda: signal_event["value"], started + OWNED_DEADLINE_SECONDS)
        except TimeoutError:
            timed_out = True
            raise
        except InterruptedError as error:
            cancelled_reason = str(error)
            raise
    except BaseException as error:
        result["reason"] = str(error)
        result["failure_type"] = type(error).__name__
        if signal_event["value"]:
            cancelled_reason = signal_event["value"]
    finally:
        try:
            if proc is not None:
                returncode, group_gone = stop_and_reap(proc, group_id, result)
                drain_pipes(proc, (stdout_capture, stderr_capture))
                finished = now()
                result.update(returncode=returncode, node_returncode=returncode,
                              node_finished_at=finished, timed_out=timed_out, cancelled=cancelled_reason,
                              finished_at=finished, owned_group_gone=group_gone)
            elif "owned_group_gone" in result:
                # launch_and_record cleaned up when its post-Popen receipt write
                # failed before ownership could be returned to this scope.
                returncode = result.get("returncode")
                group_gone = bool(result["owned_group_gone"])
            if stdout_capture is not None and stderr_capture is not None:
                try:
                    result["raw_logs"] = {"stdout": stdout_capture.finalize(), "stderr": stderr_capture.finalize()}
                except BaseException as error:
                    retention_error = {"code": getattr(error, "errno", None) or "ERR_RETENTION",
                                       "stage": "outer_log_finalize", "run_token": token}
                    result["retention_error"] = retention_error
            result["node_artifacts"] = {}
            for filename in ("node.stdout", "node.stderr"):
                path = output / filename
                if path.is_file():
                    result["node_artifacts"][filename] = hashlib.sha256(path.read_bytes()).hexdigest()
            stdout_path = output / "node.stdout"
            if stdout_path.is_file():
                result["node_summary"] = parse_node_summary(stdout_path.read_bytes())
                if isinstance(result["node_summary"], dict) and result["node_summary"].get("retention_error"):
                    result["node_retention_error"] = result["node_summary"]["retention_error"]
            report_path = measurement / "report.json"
            inner = None
            try:
                inner = json.loads(report_path.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                pass
            result["measurement_report"] = {
                "exists": report_path.is_file(),
                "sha256": hashlib.sha256(report_path.read_bytes()).hexdigest() if report_path.is_file() else None,
                "status": inner.get("status") if isinstance(inner, dict) else None,
                "run_token": inner.get("run_token") if isinstance(inner, dict) else None,
                "case_count": len(inner.get("cases", [])) if isinstance(inner, dict) and isinstance(inner.get("cases"), list) else None,
                "reason": inner.get("reason") if isinstance(inner, dict) else None,
                "retention_error": inner.get("retention_error") if isinstance(inner, dict) else None,
            }
            if proc is not None and not group_gone:
                result["reason"] = result.get("reason") or "Owned process group remains after bounded cleanup"
            profile = measurement / "browser-profile"
            if group_gone and profile.is_dir() and not profile.is_symlink():
                shutil.rmtree(profile)
                result["disposable_profile_removed"] = True
            else:
                result["disposable_profile_removed"] = False
            if (returncode == 0 and not timed_out and cancelled_reason is None and group_gone
                    and stdout_capture is not None and stderr_capture is not None
                    and not stdout_capture.truncated and not stderr_capture.truncated
                    and report_is_observed(inner, token) and retention_error is None):
                result["status"] = "observed"
            else:
                result["status"] = "unverified"
            if receipts is not None:
                try:
                    receipts.finish(result)
                except BaseException as error:
                    retention_error = {"code": getattr(error, "errno", None) or "ERR_RETENTION",
                                       "stage": "outer_receipt_finalize", "run_token": token}
                    result["retention_error"] = retention_error
                    result["status"] = "unverified"
                    try:
                        receipts.checkpoint(result)
                    except BaseException:
                        pass
        except BaseException as error:
            result["status"] = "unverified"
            result["retention_error"] = {"code": getattr(error, "errno", None) or "ERR_RETENTION",
                                          "stage": "supervisor_finally", "run_token": token}
        finally:
            if receipts is not None:
                try:
                    receipts.close()
                except BaseException as error:
                    result["status"] = "unverified"
                    result["retention_error"] = {"code": getattr(error, "errno", None) or "ERR_RETENTION",
                                                  "stage": "outer_receipt_close", "run_token": token}
            for fd in log_fds:
                try:
                    os.close(fd)
                except OSError:
                    pass
            for sig, old in old_handlers.items():
                signal.signal(sig, old)

    summary = {"status": result.get("status", "unverified"), "returncode": returncode,
               "timed_out": timed_out, "owned_group_gone": group_gone,
               "retention_error": result.get("retention_error") or result.get("node_retention_error"),
               "run_token": token}
    print(json.dumps(summary, separators=(",", ":")), flush=True)
    return 0 if summary["status"] == "observed" else 2


if __name__ == "__main__":
    try:
        exit_code = main()
    except Exception as error:
        print(json.dumps({"status": "unverified", "reason": str(error),
                          "retention_error": {"code": getattr(error, "errno", None) or "ERR_RETENTION",
                                              "stage": "preflight", "run_token": None}}, separators=(",", ":")), flush=True)
        raise SystemExit(2)
    raise SystemExit(exit_code)
