"""Build the pinned app in a new workspace and retain build provenance."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

out = Path(os.environ['YAMI_RELEASE_OUT']).resolve()
app_tree = Path(os.environ['YAMI_RELEASE_APP_TREE']).resolve()
framework_tree = Path(os.environ['YAMI_RELEASE_FRAMEWORK_TREE']).resolve()
harness_tree = Path(__file__).resolve().parents[4]
record = {'result': 'FAIL', 'source_override': True}

def git(tree, *args):
    return subprocess.check_output(['git', '-C', str(tree), *args], text=True).strip()

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

try:
    for label, tree, expected in [
        ('app', app_tree, 'cfa87adb6214f7ba50fa3a91075ca6e4eafddb9d'),
        ('framework', framework_tree, '35b9041dfb3642b43ca37c604834942614eb50fb'),
        ('harness', harness_tree, None),
    ]:
        revision = git(tree, 'rev-parse', 'HEAD')
        record[label + '_sha'] = revision
        if git(tree, 'status', '--porcelain'):
            raise RuntimeError(label + ' tree has uncommitted changes')
        if expected is not None and revision != expected:
            raise RuntimeError(label + ' source revision differs from candidate')
    for path in ('tests/native-ui/gpui-revision.txt', 'tests/shared-ui/gpui-revision.txt'):
        if (app_tree / path).read_text().strip() != record['framework_sha']:
            raise RuntimeError('dependency pin differs: ' + path)
    record['manifests'] = {name: sha(app_tree / name) for name in (
        'moon.mod', 'native/moon.mod', 'tests/native-ui/gpui-revision.txt',
        'tests/shared-ui/gpui-revision.txt')}
    record['toolchain'] = subprocess.check_output(['moon', 'version', '--all'], text=True)
    with tempfile.TemporaryDirectory(prefix='yami-live-build-') as build:
        command = ['sh', str(app_tree / 'scripts/native_ui_workspace.sh'), 'sh', '-c',
                   'cd "$YAMI_NATIVE_WORKSPACE_ROOT" && moon build "$YAMI_RELEASE_APP_TREE/native/examples/ubuntu" --target native --target-dir "$YAMI_NATIVE_WORKSPACE_ROOT/_build"']
        env = dict(os.environ, GPUI_SOURCE=str(framework_tree),
                   YAMI_NATIVE_WORKSPACE_ROOT=build, YAMI_RELEASE_APP_TREE=str(app_tree))
        record['command'] = command
        with (out / 'build.log').open('wb') as log:
            run = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT)
        record['exit_code'] = run.returncode
        if run.returncode:
            raise RuntimeError('build failed; see build.log')
        binary = Path(build) / '_build/native/debug/build/f4ah6o/yami_kumo_native/examples/ubuntu/ubuntu.exe'
        if not binary.is_file():
            raise RuntimeError('build succeeded without expected executable')
        for label, tree in [('app', app_tree), ('framework', framework_tree), ('harness', harness_tree)]:
            if git(tree, 'rev-parse', 'HEAD') != record[label + '_sha'] or git(tree, 'status', '--porcelain'):
                raise RuntimeError(label + ' source changed during build')
        shutil.copy2(binary, out / 'app.exe')
        record['binary_sha256'] = sha(out / 'app.exe')
        record['build_log_sha256'] = sha(out / 'build.log')
        record['result'] = 'PASS'
except Exception as exc:
    record['error'] = repr(exc)
finally:
    (out / 'build.json').write_text(json.dumps(record, indent=2) + '\n')
if record['result'] != 'PASS':
    raise SystemExit(1)
