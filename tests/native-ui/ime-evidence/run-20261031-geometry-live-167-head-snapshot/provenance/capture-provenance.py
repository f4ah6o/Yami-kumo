"""Preparation metadata only; does not start any live service or app."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

root = Path(__file__).resolve().parent
framework = root / 'framework'
def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def run(args):
    reply = subprocess.run(args, capture_output=True, text=True, timeout=10)
    return {'command': args, 'rc': reply.returncode,
            'stdout': reply.stdout.strip(), 'stderr': reply.stderr.strip()}

record = {
    'prepared_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'purpose': 'Diagnostic observation, possibly native FIFO head only; no ACK/dispatch/recovery or acceptance claim. #166 does not include #154 P1 fix.',
    'live_started': False,
    'reviews': {
        'parent_reported': 'both exact scoped independent reviews posted',
        'app': 'https://github.com/f4ah6o/Yami-kumo/pull/166#pullrequestreview-5721110038',
        'harness': 'https://github.com/f4ah6o/Yami-kumo/pull/167#pullrequestreview-5721097939',
    },
    'ci_at_preparation': 'Parent reports exact app #166 CI 7/7 SUCCESS, harness #167 6/7 SUCCESS with last Ubuntu in progress. Live launch is not authorized until final exact CI confirmation.',
    'profile': platform.platform(), 'sources': {}, 'protocol_generation': {},
    'tools': {}, 'static_files': {},
    'environment': {key: os.environ.get(key) for key in [
        'PATH', 'MOON_HOME', 'PKG_CONFIG_SYSROOT_DIR', 'PKG_CONFIG_LIBDIR',
        'WAYLAND_PROTOCOLS_DIR', 'LD_LIBRARY_PATH', 'XKB_CONFIG_ROOT',
        'LIBGL_DRIVERS_PATH', 'WESTON_MODULE_MAP', 'TMPDIR',
        'YAMI_RELEASE_APP_TREE', 'YAMI_RELEASE_FRAMEWORK_TREE']},
}
for name in ['app', 'framework', 'harness']:
    tree = root / name
    record['sources'][name] = {
        'path': str(tree),
        'head': run(['git', '-C', str(tree), 'rev-parse', 'HEAD'])['stdout'],
        'tree': run(['git', '-C', str(tree), 'rev-parse', 'HEAD^{tree}'])['stdout'],
        'status': run(['git', '-C', str(tree), 'status', '--porcelain'])['stdout'],
    }
protocol = Path(os.environ['WAYLAND_PROTOCOLS_DIR'])
inputs = [framework / 'scripts/prepare_ubuntu.sh',
          protocol / 'stable/xdg-shell/xdg-shell.xml',
          protocol / 'unstable/text-input/text-input-unstable-v1.xml']
outputs = [framework / 'ubuntu' / name for name in [
    'xdg-shell-client-protocol.h', 'xdg-shell-protocol.c',
    'text-input-v1-client-protocol.h', 'text-input-v1-protocol.c']]
record['protocol_generation'] = {
    'command': ['sh', str(framework / 'scripts/prepare_ubuntu.sh')],
    'inputs': {str(path): sha(path) for path in inputs},
    'outputs': {str(path): sha(path) for path in outputs},
    'scanner': run(['wayland-scanner', '--version']),
}
for name, args in [('moon', ['version', '--all']), ('wayland-scanner', ['--version']),
                   ('weston', ['--version']), ('ibus', ['version']),
                   ('xdotool', ['--version']), ('Xvfb', []), ('xvfb-run', []),
                   ('dbus-run-session', ['--version']), ('glib-compile-schemas', ['--version']),
                   ('cc', ['--version']), ('pkg-config', ['--version']),
                   ('python3', ['--version']), ('xauth', [])]:
    found = shutil.which(name)
    entry = {'path': found, 'sha256': sha(Path(found).resolve()) if found else None}
    if found and args:
        entry['version'] = run([found] + args)
    if found and name in ['Xvfb', 'weston', 'ibus', 'xdotool']:
        entry['ldd'] = run(['ldd', found])
    record['tools'][name] = entry
for text in [
    '/workspace/gpui-locked-profile/prefix/usr/lib/mozc/mozc_server',
    '/workspace/gpui-locked-profile/prefix/usr/libexec/ibus-ui-gtk3',
    '/workspace/gpui-locked-profile/prefix/usr/libexec/ibus-dconf',
    '/workspace/mozc-client-build/artifacts/mozc.xml',
    '/workspace/mozc-client-build/artifacts/ibus-engine-mozc',
    '/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/weston/desktop-shell.so',
    '/workspace/gpui-locked-profile/prefix/usr/lib/x86_64-linux-gnu/libweston-14/x11-backend.so',
]:
    path = Path(text)
    entry = {'exists': path.exists(), 'sha256': sha(path) if path.is_file() else None}
    if path.suffix != '.xml' and path.is_file():
        entry['ldd'] = run(['ldd', text])
    record['static_files'][text] = entry
inaccessible = 0
accessible = 0
for proc in Path('/proc').iterdir():
    if not proc.name.isdigit():
        continue
    try:
        list((proc / 'fd').iterdir())
        accessible += 1
    except PermissionError:
        inaccessible += 1
    except (ProcessLookupError, FileNotFoundError):
        pass
record['proc_visibility_preflight'] = {
    'accessible_process_fd_dirs': accessible,
    'inaccessible_process_fd_dirs': inaccessible,
    'implication': 'If visibility is incomplete at teardown, writer cessation/artifact stability stays UNVERIFIED.',
}
record['prepared_files_sha256'] = {
    name: sha(root / name) for name in [
        'env.sh', 'launch-after-confirmation.sh', 'verify-preparation.py',
        'verify-live-artifacts.py', 'capture-provenance.py',
    ]
}
(root / 'preparation-provenance.json').write_text(json.dumps(record, indent=2) + '\n')
missing = [name for name, value in record['tools'].items() if not value['path']]
unresolved = [name for group in ['tools', 'static_files']
              for name, value in record[group].items()
              if 'not found' in value.get('ldd', {}).get('stdout', '')]
print(json.dumps({'missing_tools': missing, 'unresolved_dynamic_libraries': unresolved,
                  'source_heads': {key: value['head'] for key, value in record['sources'].items()},
                  'live_started': False, 'proc_visibility': record['proc_visibility_preflight']}, indent=2))
if missing or unresolved or any(value['status'] for value in record['sources'].values()):
    raise SystemExit(1)
