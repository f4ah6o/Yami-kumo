from __future__ import annotations
import hashlib, json, os, re, signal, subprocess, time
from pathlib import Path

out = Path('/workspace/evidence/yami-retained-callback-724')
app = Path('/workspace/yami-entry-retained-build/native/debug/build/f4ah6o/yami_kumo_native/examples/ubuntu/ubuntu.exe')
result = {
    'profile': 'local nested Xvfb/Weston x11 + IBus/Mozc; exploratory callback only',
    'framework_sha': '5cd2f231c6cbf529396cae633f6e5a0d6c9bea41',
    'consumer_sha': os.environ.get('YAMI_TEST_SOURCE_SHA', 'UNKNOWN'),
    'app_source_sha': os.environ.get('YAMI_TEST_SOURCE_SHA', 'UNKNOWN'),
    'app_binary_sha256': hashlib.sha256(app.read_bytes()).hexdigest(),
    'entered_peek_ack': 'NOT_RUN', 'full_live_acceptance': 'NOT_RUN',
    'forced_process_termination': False,
}
log = (out / 'app.log').open('w', encoding='utf-8')
proc = subprocess.Popen([str(app), '--settings-retained-control'], stdout=log,
                        stderr=subprocess.STDOUT, env=dict(os.environ, WAYLAND_DEBUG='client'))
try:
    started = time.monotonic()
    while time.monotonic() - started < 18 and proc.poll() is None:
        data = (out / 'app.log').read_text(errors='replace')
        if '"stage":"entered_ack"' in data or '"state":"active"' in data:
            break
        subprocess.run(['xdotool', 'search', '--onlyvisible', '--name', 'Weston'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(.1)
    window = subprocess.run(['xdotool', 'search', '--onlyvisible', '--name', 'Weston'], capture_output=True, text=True)
    if window.returncode == 0 and window.stdout.strip():
        window_id = window.stdout.splitlines()[0]
        focus = subprocess.run(['xdotool', 'windowfocus', '--sync', window_id], capture_output=True, text=True)
        result['x11_window_focus_rc'] = focus.returncode
        for key in ('n','i','h','o','n','n'):
            subprocess.run(['xdotool', 'key', '--clearmodifiers', key], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(.08)
        time.sleep(1.0)
    data = (out / 'app.log').read_text(errors='replace')
    peeks = re.findall(r'YAMI_SETTINGS_IME (\{"stage":"entered_peek"[^\n]*\})', data)
    acks = re.findall(r'YAMI_SETTINGS_IME (\{"stage":"entered_ack"[^\n]*\})', data)
    result['entered_peek_records'] = [json.loads(value) for value in peeks]
    result['entered_ack_records'] = [json.loads(value) for value in acks]
    if peeks and acks and any(p['native_sequence'] == a['native_sequence'] for p in result['entered_peek_records'] for a in result['entered_ack_records']):
        result['entered_peek_ack'] = 'PASS'
    else:
        result['entered_peek_ack'] = 'FAIL'
    result['preedit_markers'] = re.findall(r'^YAMI_NATIVE_UI_SETTINGS .*"phase":"preedit".*$', data, re.M)
    result['commit_markers'] = re.findall(r'^YAMI_NATIVE_UI_SETTINGS .*"phase":"commit".*$', data, re.M)
    result['control_active'] = '"state":"active"' in data
    result['app_exited_before_cleanup'] = proc.poll() is not None
    if result['control_active']:
        path_match = re.search(r'YAMI_SETTINGS_CONTROL \{"path":"([^"]+)"', data)
        if path_match:
            reply = subprocess.run(['python3', '/workspace/yami-suspended/scripts/settings_retained_control.py', path_match.group(1), 'status'], capture_output=True, text=True, timeout=5)
            result['control_status'] = {'rc': reply.returncode, 'stdout': reply.stdout, 'stderr': reply.stderr}
except Exception as exc:
    result['error'] = repr(exc)
finally:
    if proc.poll() is None:
        result['forced_process_termination'] = True
        proc.send_signal(signal.SIGTERM)
    try:
        result['app_exit_code'] = proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        result['app_exit_code'] = proc.wait(timeout=5)
        result['forced_sigkill'] = True
    log.close()
    # Forced fixture cleanup is not host.stop or owner recovery.
    text = (out / 'app.log').read_text(errors='replace')
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
