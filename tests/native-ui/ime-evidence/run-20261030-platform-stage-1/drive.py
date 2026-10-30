from __future__ import annotations
import hashlib, json, os, re, signal, subprocess, time
from pathlib import Path

out = Path('/workspace/evidence/yami-platform-live-1')
app = Path('/workspace/yami-platform-observe-build/native/debug/build/f4ah6o/yami_kumo_native/examples/ubuntu/ubuntu.exe')
result = {
    'profile': 'local nested Xvfb/Weston x11 + IBus/Mozc; exploratory callback only',
    'framework_sha': 'f67cb002731b62ae47bdb5368ebf83a3c395a2cf',
    'consumer_sha': '0a614b49bcdd53c291b50bbb60759a02d151be46',
    'app_source_sha': '0a614b49bcdd53c291b50bbb60759a02d151be46',
    'app_binary_sha256': hashlib.sha256(app.read_bytes()).hexdigest(),
    'entered_peek_ack': 'NOT_RUN', 'full_live_acceptance': 'NOT_RUN',
    'forced_process_termination': False,
}
log = (out / 'app.log').open('w', encoding='utf-8')
proc = subprocess.Popen(['stdbuf', '-oL', '-eL', str(app), '--settings-retained-control'], stdout=log,
                        stderr=subprocess.STDOUT, env=dict(os.environ, WAYLAND_DEBUG='client'))
(out / 'pid').write_text(str(proc.pid) + '\n')
try:
    started = time.monotonic()
    while time.monotonic() - started < 18 and proc.poll() is None:
        data = (out / 'app.log').read_text(errors='replace')
        if '"stage":"entered_ack"' in data or '"state":"active"' in data:
            break
        subprocess.run(['xdotool', 'search', '--name', 'Weston'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(.1)
    weston_log = (out / 'weston.log').read_text(errors='replace')
    window = re.search(r'x11 output .* window id (\d+)', weston_log)
    if window:
        window_id = window.group(1)
        result['x11_window_id'] = window_id
        focus = subprocess.run(['xdotool', 'getwindowfocus'], capture_output=True, text=True)
        result['x11_window_focus_id'] = focus.stdout.strip()
        result['x11_window_focus_rc'] = focus.returncode
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            wayland = (out / 'ibus-ui-wayland.log').read_text(errors='replace')
            dbus = (out / 'ibus-ui-dbus.log').read_text(errors='replace')
            if '.grab_keyboard(' in wayland and "member -> 'RegisterProperties'" in dbus:
                result['ime_keyboard_grab'] = True
                break
            time.sleep(.1)
        time.sleep(.5)
        for key in ('n','i','h','o','n','n'):
            subprocess.run(['xdotool', 'key', '--clearmodifiers', key], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(.08)
        time.sleep(.5)
        for key in ('space', 'Return'):
            subprocess.run(['xdotool', 'key', '--clearmodifiers', key], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(.25)
        time.sleep(1.0)
        time.sleep(10.0)  # Separate observer may inspect this isolated process.
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
    if proc.poll() is None:
        for name in ('wchan', 'syscall', 'status'):
            try:
                value = Path(f'/proc/{proc.pid}/{name}').read_text()
                if name == 'status':
                    value = '\n'.join(line for line in value.splitlines() if line.startswith(('State:', 'Threads:', 'VmRSS:')))
                result[f'process_{name}'] = value.strip()
            except OSError as exc:
                result[f'process_{name}'] = repr(exc)
        ps = subprocess.run(['ps', '-L', '-p', str(proc.pid), '-o', 'pid,tid,stat,wchan:32,comm'], capture_output=True, text=True)
        result['thread_snapshot'] = ps.stdout
    path_match = re.search(r'YAMI_SETTINGS_CONTROL \{"path":"([^"]+)"', data)
    if path_match:
        for command in ('status', 'receipt', 'generation'):
            reply = subprocess.run(['python3', '/workspace/yami-physical-platform/scripts/settings_retained_control.py', path_match.group(1), command], capture_output=True, text=True, timeout=5)
            result[f'control_{command}'] = {'rc': reply.returncode, 'stdout': reply.stdout, 'stderr': reply.stderr}
        pending = re.search(r'native receipt sequence: (\d+)', result['control_receipt']['stdout'])
        if pending:
            reply = subprocess.run(['python3', '/workspace/yami-physical-platform/scripts/settings_retained_control.py', path_match.group(1), 'stage', '--sequence', pending.group(1)], capture_output=True, text=True, timeout=5)
            result['control_pending_stage'] = {'sequence': int(pending.group(1)), 'rc': reply.returncode, 'stdout': reply.stdout, 'stderr': reply.stderr}
        ack_sequences = re.findall(r'"stage":"record_ack"[^\n]*"native_sequence":(\d+)', data)
        if ack_sequences:
            reply = subprocess.run(['python3', '/workspace/yami-physical-platform/scripts/settings_retained_control.py', path_match.group(1), 'stage', '--sequence', ack_sequences[-1]], capture_output=True, text=True, timeout=5)
            result['control_last_ack_stage'] = {'sequence': int(ack_sequences[-1]), 'rc': reply.returncode, 'stdout': reply.stdout, 'stderr': reply.stderr}
    result['all_ack_stages'] = {}
    for seq in sorted(set(int(value) for value in re.findall(r'"stage":"(?:record_ack|entered_ack)"[^\n]*"native_sequence":(\d+)', data))) if path_match else []:
        reply = subprocess.run(['python3', '/workspace/yami-physical-platform/scripts/settings_retained_control.py', path_match.group(1), 'stage', '--sequence', str(seq)], capture_output=True, text=True, timeout=5)
        result['all_ack_stages'][str(seq)] = {'rc': reply.returncode, 'stdout': reply.stdout, 'stderr': reply.stderr}
    result['physical_evidence'] = re.findall(r'^YAMI_SETTINGS_IME .*\"stage\":\"physical_evidence\".*$', data, re.M)
    result['receipt_trace'] = re.findall(r'^YAMI_SETTINGS_IME .*$', data, re.M)
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
