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
from probe import preedit_markers, advance_until_preedit, run_control_command

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
if app_sha != 'cfa87adb6214f7ba50fa3a91075ca6e4eafddb9d' or framework_sha != '35b9041dfb3642b43ca37c604834942614eb50fb':
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
    'preedit_probe': {'result': 'NOT_RUN'}, 'geometry_race': 'NOT_RUN',
    'scene_and_caret': 'NOT_RUN', 'retained_record_model_application': 'NOT_RUN',
    'forced_process_termination': False, 'steps': [],
}
log = (out / 'app.log').open('w', encoding='utf-8')
proc = subprocess.Popen(['stdbuf', '-oL', '-eL', str(app), '--settings-retained-control'],
                        stdout=log, stderr=subprocess.STDOUT, env=dict(os.environ, WAYLAND_DEBUG='client'), start_new_session=True)
(out / 'pid').write_text(str(proc.pid) + '\n')

def app_data() -> str:
    return (out / 'app.log').read_text(errors='replace')

class ControlOutcomeUnknown(Exception):
    def __init__(self, event: dict):
        self.event = event
        super().__init__('control timeout: ' + event['command'])

def send_command(socket_path: str, command: str, seq: int | None = None) -> dict:
    args = ['python3', str(control), socket_path, command]
    if seq is not None:
        args.extend(['--sequence', str(seq)])
    event = run_control_command(args, result['steps'], command, seq)
    # The probe needs to record its partial bounded attempts before stopping;
    # every other caller must stop before interpreting even partial stdout.
    if event['status'] == 'TIMEOUT_OUTCOME_UNKNOWN' and command not in ('generation', 'advance'):
        raise ControlOutcomeUnknown(event)
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
        result['release_policy'] = ('NOT_ESTABLISHED_TIMEOUT_OUTCOME_UNKNOWN'
                                    if result['initial_resolve']['status'] == 'TIMEOUT_OUTCOME_UNKNOWN' else 'FAIL')
        raise RuntimeError('native release policy refused or failed; receipt stays owned')
    result['initial_ack_stage'] = send_command(socket_path, 'stage', seq)
    if 'native adapter acknowledged' not in result['initial_ack_stage']['stdout']:
        raise RuntimeError('successful ACK was not independently observed in owner ledger')
    result['release_policy'] = 'PASS_SCOPED'
    # Do not infer a dirty scene from the first bounded continuation: it may
    # complete a prior frame while the next preedit remains queued.
    baseline_count = len(preedit_markers(app_data()))
    subprocess.run(['xdotool', 'key', '--clearmodifiers', 'i'], check=True)
    time.sleep(.10)
    result['preedit_probe'] = advance_until_preedit(
        app_data, lambda command, sequence=None: send_command(socket_path, command, sequence),
        baseline_count, 'に', limit=8)
    result['geometry_race'] = 'NOT_RUN_CONSUMER_PREEDIT_NOT_OBSERVED'
    if result['preedit_probe']['result'] in ('BLOCKED_GENERATION_TIMEOUT_OUTCOME_UNKNOWN',
                                              'BLOCKED_ADVANCE_TIMEOUT_OUTCOME_UNKNOWN'):
        raise ControlOutcomeUnknown(result['steps'][-1])
    if result['preedit_probe']['result'] == 'OBSERVED_CONSUMER_PREEDIT':
        result['geometry_initial'] = send_command(socket_path, 'geometry-submit')
        result['geometry_race'] = 'NOT_ESTABLISHED'
        if result['geometry_initial']['rc'] != 0:
            result['handoff'] = send_command(socket_path, 'geometry-handoff')
            if result['handoff']['rc'] == 0:
                result['geometry_retry'] = send_command(socket_path, 'geometry-submit')
                if result['geometry_retry']['rc'] == 0:
                    result['geometry_race'] = 'OBSERVED_HANDOFF_AND_RETRY_RESPONSES_CAUSE_UNVERIFIED'
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
    if any(step['status'] == 'TIMEOUT_OUTCOME_UNKNOWN' for step in result['steps']):
        result['final_stop'] = {'result': 'NOT_RUN_COMMAND_OUTCOME_UNKNOWN'}
    else:
        result['final_stop'] = send_command(socket_path, 'stop')
except ControlOutcomeUnknown as exc:
    result['error'] = repr(exc)
    if exc.event['command'] == 'resolve-release':
        result['release_policy'] = 'NOT_ESTABLISHED_TIMEOUT_OUTCOME_UNKNOWN'
    if exc.event['command'] in ('geometry-submit', 'geometry-handoff'):
        result['geometry_race'] = 'BLOCKED_COMMAND_TIMEOUT_OUTCOME_UNKNOWN'
    if exc.event['command'] != 'stop':
        result['final_stop'] = {'result': 'NOT_RUN_COMMAND_OUTCOME_UNKNOWN'}
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
    # Guard flags are observations from this diagnostic app, not a stage or
    # host acceptance. Keep malformed markers in the raw log only.
    result['geometry_guard_markers'] = []
    for line in text.splitlines():
        if line.startswith('YAMI_SETTINGS_GEOMETRY_GUARD '):
            try:
                result['geometry_guard_markers'].append(json.loads(line.split(' ', 1)[1]))
            except json.JSONDecodeError:
                pass
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
