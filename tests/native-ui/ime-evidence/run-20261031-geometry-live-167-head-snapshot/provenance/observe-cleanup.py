"""Read-only independent postflight observation; never terminates processes."""
import datetime
import json
import os
from pathlib import Path
import re

root = Path(__file__).resolve().parent
out = root / 'live'
result = json.loads((out / 'result.json').read_text())
app_log = (out / 'app.log').read_text()
weston_log = (out / 'weston.log').read_text()
runtime_match = re.search(r'--config=(/tmp/yami-retained-fixture-[^/ ]+)/weston.ini', weston_log)
control_match = re.search(r'"path":"(/tmp/yami-settings-[^"/]+/control.sock)"', app_log)
runtime = Path(runtime_match.group(1)) if runtime_match else None
control = Path(control_match.group(1)) if control_match else None
app_pid = int((out / 'pid').read_text())
ancestors = {os.getpid()}
pid = os.getppid()
while pid > 0 and pid not in ancestors:
    ancestors.add(pid)
    try:
        stat = Path('/proc', str(pid), 'stat').read_text()
        pid = int(stat[stat.rfind(')') + 2:].split()[1])
    except (OSError, ValueError, IndexError):
        break
matches = []
denied = 0
for proc in Path('/proc').iterdir():
    if not proc.name.isdigit() or int(proc.name) in ancestors:
        continue
    try:
        command = (proc / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
        if str(root) in command or (runtime and str(runtime) in command):
            matches.append({'pid': int(proc.name), 'command': command})
    except PermissionError:
        denied += 1
    except (FileNotFoundError, ProcessLookupError):
        pass
record = {
    'checked_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'app_pid': app_pid, 'app_proc_path_exists': Path('/proc', str(app_pid)).exists(),
    'runtime_path': str(runtime) if runtime else None,
    'runtime_exists': runtime.exists() if runtime else None,
    'control_socket_path': str(control) if control else None,
    'control_socket_exists': control.exists() if control else None,
    'visible_run_processes': matches, 'cmdline_scan_permission_denied': denied,
    'exact_harness_log_shutdown': result['log_shutdown'],
    'cleanup_result': result['cleanup_result'],
    'artifact_stability': result['artifact_stability'],
    'raw_manifest_digest': result['artifact_digest'],
    'raw_files_modified_by_reviewer': False,
    'session_exit_code': result['session_exit_code'],
    'session_exit_code_is_not_acceptance': True,
}
(root / 'postflight-cleanup-observation.json').write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps(record, indent=2))
