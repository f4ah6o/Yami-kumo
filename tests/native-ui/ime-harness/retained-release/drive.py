from __future__ import annotations

import hashlib
import json
import os
import platform
import re
import signal
import subprocess
import time
from pathlib import Path

out = Path(os.environ['YAMI_RELEASE_OUT'])
app = Path(os.environ['YAMI_RELEASE_BINARY'])
expected_binary = os.environ['YAMI_RELEASE_BINARY_SHA256']
app_tree = Path(os.environ['YAMI_RELEASE_APP_TREE'])
framework_tree = Path(os.environ['YAMI_RELEASE_FRAMEWORK_TREE'])
harness_tree = Path(__file__).resolve().parents[4]
control = app_tree / 'scripts/settings_retained_control.py'

def git(tree: Path, *args: str) -> str:
    return subprocess.check_output(['git', '-C', str(tree), *args], text=True).strip()

app_sha = git(app_tree, 'rev-parse', 'HEAD')
framework_sha = git(framework_tree, 'rev-parse', 'HEAD')
harness_sha = git(harness_tree, 'rev-parse', 'HEAD')
if git(app_tree, 'status', '--porcelain') or git(framework_tree, 'status', '--porcelain') or git(harness_tree, 'status', '--porcelain'):
    raise SystemExit('refusing uncommitted source or harness changes')
actual_binary = hashlib.sha256(app.read_bytes()).hexdigest()
if actual_binary != expected_binary:
    raise SystemExit('binary digest differs from the independently captured build digest')
if app_sha != 'f6c4b40abbecd74b76a1fb459c360a104fd132dd' or framework_sha != 'b28cff9a8a92a155e67421a397a1030dedac9301':
    raise SystemExit('source revisions differ from the reviewed candidate pair')

result = {
    'profile': 'local nested Xvfb/Weston x11 + IBus/Mozc; exploratory bounded control',
    'OS_arch': platform.platform() + ' / ' + platform.machine(),
    'framework_sha': framework_sha, 'consumer_sha': app_sha,
    'app_source_sha': app_sha, 'harness_sha': harness_sha,
    'app_binary_sha256': actual_binary,
    'dependency_pin_native': (app_tree / 'tests/native-ui/gpui-revision.txt').read_text().strip(),
    'dependency_pin_shared': (app_tree / 'tests/shared-ui/gpui-revision.txt').read_text().strip(),
    'dependency_lock': {'kind': 'source-override; no package lockfile',
                        'native_moon_mod_sha256': hashlib.sha256((app_tree / 'native/moon.mod').read_bytes()).hexdigest(),
                        'root_moon_mod_sha256': hashlib.sha256((app_tree / 'moon.mod').read_bytes()).hexdigest()},
    'toolchain': subprocess.run(['moon', 'version', '--all'], capture_output=True, text=True).stdout,
    'command': 'dbus-run-session -- xvfb-run -a <harness>/session.sh',
    'run_url': None, 'full_live_acceptance': 'NOT_RUN',
    'release_policy': 'NOT_RUN', 'consumer_commit': 'NOT_RUN',
    'forced_process_termination': False, 'steps': [],
}
log = (out / 'app.log').open('w', encoding='utf-8')
proc = subprocess.Popen(['stdbuf', '-oL', '-eL', str(app), '--settings-retained-control'],
                        stdout=log, stderr=subprocess.STDOUT, env=dict(os.environ, WAYLAND_DEBUG='client'))
(out / 'pid').write_text(str(proc.pid) + '\n')

def app_data() -> str:
    return (out / 'app.log').read_text(errors='replace')

def send_command(socket_path: str, command: str, seq: int | None = None) -> dict:
    args = ['python3', str(control), socket_path, command]
    if seq is not None:
        args.extend(['--sequence', str(seq)])
    reply = subprocess.run(args, capture_output=True, text=True, timeout=5)
    event = {'command': command, 'sequence': seq, 'rc': reply.returncode,
             'stdout': reply.stdout, 'stderr': reply.stderr}
    result['steps'].append(event)
    return event

def value(reply: dict, name: str) -> int | None:
    found = re.search(re.escape(name) + r': (\d+)', reply['stdout'])
    return int(found.group(1)) if found else None

try:
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline and proc.poll() is None:
        if '"stage":"entered_ack"' in app_data():
            break
        time.sleep(.1)
    if '"stage":"entered_ack"' not in app_data():
        raise RuntimeError('native entered ACK not observed')
    wayland = (out / 'ibus-ui-wayland.log')
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline and '.grab_keyboard(' not in wayland.read_text(errors='replace'):
        time.sleep(.1)
    if '.grab_keyboard(' not in wayland.read_text(errors='replace'):
        raise RuntimeError('IBus keyboard grab not observed')
    subprocess.run(['xdotool', 'key', '--clearmodifiers', 'n'], check=True)
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline and proc.poll() is None:
        text = app_data()
        if '"state":"active"' in text and '"kind":"unhandled_forwarded_release"' in text:
            break
        time.sleep(.1)
    text = app_data()
    match = re.search(r'YAMI_SETTINGS_CONTROL \{"path":"([^"]+)"', text)
    if not match or '"state":"active"' not in text:
        raise RuntimeError('owner did not reach controlled suspension')
    socket_path = match.group(1)
    result['initial_status'] = send_command(socket_path, 'status')
    result['initial_prefix'] = send_command(socket_path, 'prefix')
    initial_receipt = send_command(socket_path, 'receipt')
    seq = value(initial_receipt, 'native receipt sequence')
    if seq is None:
        raise RuntimeError('original unsupported receipt was not observable')
    result['initial_receipt_sequence'] = seq
    result['initial_resolve'] = send_command(socket_path, 'resolve-release', seq)
    if result['initial_resolve']['rc'] != 0:
        result['release_policy'] = 'FAIL'
        raise RuntimeError('native release policy refused or failed; receipt stays owned')
    result['initial_ack_stage'] = send_command(socket_path, 'stage', seq)
    if 'native adapter acknowledged' not in result['initial_ack_stage']['stdout']:
        raise RuntimeError('successful ACK was not independently observed in owner ledger')
    result['release_policy'] = 'PASS_SCOPED'
    for key in ('i', 'h', 'o', 'n', 'n', 'space', 'Return'):
        subprocess.run(['xdotool', 'key', '--clearmodifiers', key], check=True)
        time.sleep(.10)
    # Each call is bounded and uses the currently reported generation. Native
    # policy rejects unexpected/unknown input itself; no arbitrary ACK is made.
    deadline = time.monotonic() + 45
    for _ in range(160):
        if time.monotonic() >= deadline or proc.poll() is not None:
            break
        if re.search(r'YAMI_NATIVE_UI_SETTINGS .*"phase":"commit".*"text":"日本"', app_data()):
            result['consumer_commit'] = 'OBSERVED_LOG_ONLY'
            break
        generation = value(send_command(socket_path, 'generation'), 'continuation generation')
        if generation is not None:
            send_command(socket_path, 'advance', generation)
            continue
        pending = value(send_command(socket_path, 'receipt'), 'native receipt sequence')
        if pending is None:
            break
        attempt = send_command(socket_path, 'resolve-release', pending)
        if attempt['rc'] != 0:
            break
    result['preedit_markers'] = re.findall(r'^YAMI_NATIVE_UI_SETTINGS .*"phase":"preedit".*$', app_data(), re.M)
    result['commit_markers'] = re.findall(r'^YAMI_NATIVE_UI_SETTINGS .*"phase":"commit".*$', app_data(), re.M)
    result['final_status'] = send_command(socket_path, 'status')
    result['final_receipt'] = send_command(socket_path, 'receipt')
    result['final_stop'] = send_command(socket_path, 'stop')
except Exception as exc:
    result['error'] = repr(exc)
finally:
    if proc.poll() is None:
        result['forced_process_termination'] = True
        # This exploratory teardown loses any in-memory owner/receipt. It is
        # not host.stop or safe cleanup and must never be scored as a PASS.
        result['cleanup_result'] = 'FAIL_FORCED_TERMINATION_OWNER_NOT_PERSISTED'
        proc.send_signal(signal.SIGTERM)
    try:
        result['app_exit_code'] = proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        result['app_exit_code'] = proc.wait(timeout=5)
        result['forced_sigkill'] = True
    log.close()
    text = app_data()
    match = re.search(r'YAMI_SETTINGS_CONTROL \{"path":"(/tmp/yami-settings-[^"/]+/control.sock)"', text)
    if match:
        path = Path(match.group(1))
        try:
            path.unlink(missing_ok=True)
            path.parent.rmdir()
            result['test_socket_cleanup'] = 'removed after process exit'
        except OSError as exc:
            result['test_socket_cleanup'] = repr(exc)
    (out / 'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))
