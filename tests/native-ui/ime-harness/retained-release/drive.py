from __future__ import annotations

import hashlib
import json
import os
import platform
import re
import signal
import shutil
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

def tool_info(name: str, *arguments: str) -> dict:
    path = shutil.which(name)
    if not path:
        return {'path': None, 'version': None, 'sha256': None}
    resolved = Path(path).resolve()
    try:
        version = subprocess.run([path, *arguments], capture_output=True, text=True, timeout=5)
        output = (version.stdout + version.stderr).strip()
    except (OSError, subprocess.TimeoutExpired) as exc:
        output = repr(exc)
    return {'path': str(resolved), 'version': output,
            'sha256': hashlib.sha256(resolved.read_bytes()).hexdigest()}

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
if app_sha != '1a59626cf67910917c4d660dd6db8bedae55a722' or framework_sha != '35b9041dfb3642b43ca37c604834942614eb50fb':
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
    'host_tools': {'weston': tool_info('weston', '--version'),
                   'ibus': tool_info('ibus', 'version'),
                   'xdotool': tool_info('xdotool', '--version'),
                   'mozc_server_sha256': hashlib.sha256(Path('/workspace/gpui-locked-profile/prefix/usr/lib/mozc/mozc_server').read_bytes()).hexdigest()},
    'command': 'dbus-run-session -- xvfb-run -a <harness>/session.sh',
    'run_url': None, 'full_live_acceptance': 'NOT_RUN',
    'release_policy': 'NOT_RUN', 'consumer_commit': 'NOT_RUN',
    'model_reflection': 'NOT_RUN', 'candidate_table_oracle': 'NOT_RUN',
    'dialog_and_focus': 'NOT_RUN', 'resize_blur_close_races': 'NOT_RUN',
    'forced_process_termination': False, 'steps': [],
}
log = (out / 'app.log').open('w', encoding='utf-8')
proc = subprocess.Popen(['stdbuf', '-oL', '-eL', str(app), '--settings-retained-control'],
                        stdout=log, stderr=subprocess.STDOUT, env=dict(os.environ, WAYLAND_DEBUG='client'), start_new_session=True)
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
    # Probe only one candidate race. The previously applied preedit makes the
    # scene dirty; native queue contents and result remain explicitly observed.
    subprocess.run(['xdotool', 'key', '--clearmodifiers', 'i'], check=True)
    time.sleep(.10)
    generation = value(send_command(socket_path, 'generation'), 'continuation generation')
    if generation is not None:
        result['probe_advance'] = send_command(socket_path, 'advance', generation)
    result['geometry_initial'] = send_command(socket_path, 'geometry-submit')
    result['geometry_race'] = 'NOT_ESTABLISHED'
    if result['geometry_initial']['rc'] != 0:
        result['handoff'] = send_command(socket_path, 'geometry-handoff')
        if result['handoff']['rc'] == 0:
            result['geometry_retry'] = send_command(socket_path, 'geometry-submit')
            if result['geometry_retry']['rc'] == 0:
                result['geometry_race'] = 'PASS_SCOPED_HOST_RECEIPT_AND_HELD_RECORD'
            else:
                result['geometry_race'] = 'FAIL_RETRY_RETAINED'
        else:
            result['geometry_race'] = 'BLOCKED_INITIAL_OR_HANDOFF_ERROR'
    else:
        result['geometry_race'] = 'NOT_RUN_NO_BUSY_OBSERVED'
    result['preedit_markers'] = re.findall(r'^YAMI_NATIVE_UI_SETTINGS .*"phase":"preedit".*$', app_data(), re.M)
    result['commit_markers'] = re.findall(r'^YAMI_NATIVE_UI_SETTINGS .*"phase":"commit".*$', app_data(), re.M)
    result['scene_and_caret'] = 'NOT_RUN'
    result['retained_record_model_application'] = 'NOT_RUN'
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
        os.killpg(proc.pid, signal.SIGTERM)
    try:
        result['app_exit_code'] = proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
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
