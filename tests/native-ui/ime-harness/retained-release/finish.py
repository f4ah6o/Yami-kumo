"""Bounded process-group shutdown and evidence finalization.

The /proc writer scan is observational and cannot exclude inaccessible or
escaped processes. Digests are marked unverified when visibility is incomplete.
"""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

out = Path(sys.argv[1]).resolve()
status, phase = int(sys.argv[2]), sys.argv[3]
groups = [int(v) for v in sys.argv[4:]]

def group_exists(group):
    # killpg(0) also sees dead, unreaped shell children. Those have no open
    # descriptors and do not make the logs mutable.
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            stat = (proc / 'stat').read_text()
            fields = stat[stat.rfind(')') + 2:].split()
            if int(fields[2]) == group and fields[0] != 'Z':
                return True
        except (OSError, IndexError, ValueError):
            continue
    return False

for group in groups:
    try:
        os.killpg(group, signal.SIGTERM)
    except ProcessLookupError:
        pass
for _ in range(30):
    if not any(map(group_exists, groups)):
        break
    time.sleep(.1)
for group in groups:
    if group_exists(group):
        try:
            os.killpg(group, signal.SIGKILL)
        except ProcessLookupError:
            pass
for _ in range(30):
    if not any(map(group_exists, groups)):
        break
    time.sleep(.1)
remaining = [group for group in groups if group_exists(group)]
writers = []
inaccessible = 0
for proc in Path('/proc').iterdir():
    if not proc.name.isdigit() or int(proc.name) == os.getpid():
        continue
    try:
        fds = list((proc / 'fd').iterdir())
    except (FileNotFoundError, ProcessLookupError):
        continue
    except PermissionError:
        inaccessible += 1
        continue
    for fd in fds:
        try:
            path = Path(os.readlink(fd))
            if not path.is_absolute() or not path.is_relative_to(out):
                continue
            info = (proc / 'fdinfo' / fd.name).read_text()
            flags = next(int(line.split()[1], 8) for line in info.splitlines() if line.startswith('flags:'))
            if flags & os.O_ACCMODE in (os.O_WRONLY, os.O_RDWR):
                writers.append({'pid': int(proc.name), 'fd': int(fd.name), 'path': str(path)})
        except (OSError, StopIteration, ValueError):
            continue
path = out / 'result.json'
if path.exists():
    result = json.loads(path.read_text())
else:
    result = {'full_live_acceptance': 'NOT_RUN', 'run_url': None,
              'error': 'session exited before driver wrote result'}
result['session_exit_code'] = status
result['session_exit_phase'] = phase
result['log_shutdown'] = {'tracked_groups_remaining': remaining,
                          'visible_open_writers': writers,
                          'inaccessible_processes': inaccessible,
                          'scope': 'local /proc observation, not proof against escaped or inaccessible writers'}
result['artifact_stability'] = ('UNVERIFIED_WRITERS_OR_GROUPS' if remaining or writers or inaccessible
                                else 'NO_VISIBLE_WRITERS_AFTER_GROUP_SHUTDOWN')
path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
subprocess.run([sys.executable, str(Path(__file__).with_name('finalize.py')), str(out)], check=True)
