"""Full-driver timeout regression with fake subprocesses; no GUI or IME."""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
APP_SHA = 'e9fe5fe06111dce33be20f3f93d8be819194486f'
FRAMEWORK_SHA = '35b9041dfb3642b43ca37c604834942614eb50fb'

class DriverTimeoutTest(unittest.TestCase):
    def run_case(self, timeout_command, partial, *, geometry_failure=False, missing_receipt=False):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            out, app_tree, framework = root / 'out', root / 'app', root / 'framework'
            out.mkdir()
            (app_tree / 'native').mkdir(parents=True)
            (app_tree / 'tests/native-ui').mkdir(parents=True)
            (app_tree / 'tests/shared-ui').mkdir(parents=True)
            for path in ('native/moon.mod', 'moon.mod', 'tests/native-ui/gpui-revision.txt', 'tests/shared-ui/gpui-revision.txt'):
                (app_tree / path).write_text('controlled fixture\n')
            framework.mkdir()
            binary = root / 'app.bin'
            binary.write_bytes(b'fake binary')
            (out / 'ibus-ui-wayland.log').write_text('.grab_keyboard(')
            env = {'YAMI_RELEASE_OUT': str(out), 'YAMI_RELEASE_BINARY': str(binary),
                   'YAMI_RELEASE_BINARY_SHA256': hashlib.sha256(binary.read_bytes()).hexdigest(),
                   'YAMI_RELEASE_APP_TREE': str(app_tree), 'YAMI_RELEASE_FRAMEWORK_TREE': str(framework)}
            calls = []
            state = {'stopped': False}
            class FakeProc:
                pid = 12345
                def __init__(self, args, **kwargs):
                    kwargs['stdout'].write('YAMI_SETTINGS_CONTROL {"path":"/fake/control.sock","state":"active","stage":"entered_ack","kind":"unhandled_forwarded_release"}\nYAMI_NATIVE_UI_SETTINGS {"phase":"preedit","text":"ｎ"}\nYAMI_SETTINGS_GEOMETRY_GUARD {"frame":true}\n')
                    kwargs['stdout'].flush()
                def poll(self):
                    return 0 if state['stopped'] else None
                def wait(self, **kwargs):
                    return -15
            def git(args, **kwargs):
                if 'status' in args:
                    return ''
                return (APP_SHA if args[2] == str(app_tree) else FRAMEWORK_SHA if args[2] == str(framework) else 'harness-test-only') + '\n'
            def run(args, **kwargs):
                if args[0] == 'moon':
                    return subprocess.CompletedProcess(args, 0, 'test toolchain', '')
                if args[0] == 'xdotool':
                    return subprocess.CompletedProcess(args, 0, '', '')
                command = args[3]
                calls.append(command)
                if command == timeout_command:
                    raise subprocess.TimeoutExpired(args, 5, output=partial, stderr=b'partial error')
                if command == 'advance':
                    with (out / 'app.log').open('a') as log:
                        log.write('YAMI_NATIVE_UI_SETTINGS {"phase":"preedit","text":"に"}\n')
                if command == 'inspect-native':
                    with (out / 'app.log').open('a') as log:
                        log.write('YAMI_SETTINGS_RETAINED_HEAD {"present":true,"kind":"forwarded_released","sequence":11}\n')
                stdout = {'receipt': 'native receipt sequence: 1\n',
                          'stage': 'native adapter acknowledged\n',
                          'generation': 'continuation generation: 19\n'}.get(command, '')
                if command == 'receipt' and missing_receipt:
                    stdout = 'native receipt sequence: none or non-text prefix\n'
                rc = 2 if command == 'geometry-submit' and geometry_failure else 0
                return subprocess.CompletedProcess(args, rc, stdout, '')
            def terminate(*args):
                state['stopped'] = True
            real_read = Path.read_bytes
            def read_bytes(path):
                if str(path).endswith('/usr/lib/mozc/mozc_server'):
                    return b'fake mozc'
                return real_read(path)
            with patch.dict(os.environ, env), patch('subprocess.check_output', git), patch('subprocess.run', run), patch('subprocess.Popen', FakeProc), patch('os.killpg', terminate), patch('shutil.which', return_value=None), patch.object(Path, 'read_bytes', read_bytes), patch('platform.platform', return_value='fixture'), patch('time.sleep', lambda _: None), contextlib.redirect_stdout(io.StringIO()):
                runpy.run_path(str(HERE / 'drive.py'), run_name='__main__')
            result = json.loads((out / 'result.json').read_text())
            return calls, result

    def test_partial_timeout_stops_before_any_following_command(self):
        cases = [('status', b''), ('receipt', b'native receipt sequence: 1\n'),
                 ('stage', b'native adapter acknowledged\n'),
                 ('resolve-release', b'accepted'), ('generation', b'continuation generation: 19\n'),
                 ('advance', b'advanced'), ('geometry-submit', b'submitted'),
                 ('geometry-handoff', b'handed off'), ('stop', b'stopped')]
        for command, partial in cases:
            with self.subTest(command=command):
                calls, result = self.run_case(command, partial, geometry_failure=command == 'geometry-handoff')
                self.assertEqual(calls[-1], command)
                timed = result['steps'][-1]
                self.assertEqual(result['geometry_guard_markers'], [{'frame': True}])
                self.assertEqual(timed['status'], 'TIMEOUT_OUTCOME_UNKNOWN')
                self.assertEqual(timed['stdout'], partial.decode())
                self.assertEqual(result['cleanup_result'], 'FAIL_FORCED_TERMINATION_OWNER_NOT_PERSISTED')
                if command != 'stop':
                    self.assertEqual(result['final_stop']['result'], 'NOT_RUN_COMMAND_OUTCOME_UNKNOWN')
                if command in ('generation', 'advance'):
                    self.assertEqual(result['geometry_race'], 'NOT_RUN_CONSUMER_PREEDIT_NOT_OBSERVED')
                    self.assertEqual(result['preedit_probe']['result'], 'BLOCKED_' + command.upper() + '_TIMEOUT_OUTCOME_UNKNOWN')

    def test_missing_runner_receipt_inspects_native_head_once_without_advance(self):
        calls, result = self.run_case(None, b'', missing_receipt=True)
        self.assertEqual(calls, ['status', 'prefix', 'receipt', 'inspect-native'])
        self.assertEqual(result['native_head_markers'], [{'present': True, 'kind': 'forwarded_released', 'sequence': 11}])
        self.assertEqual(result['release_policy'], 'NOT_RUN')
        self.assertEqual(result['geometry_race'], 'NOT_RUN')
        self.assertEqual(result['cleanup_result'], 'FAIL_FORCED_TERMINATION_OWNER_NOT_PERSISTED')

    def test_native_head_inspection_timeout_stops_without_guess_or_retry(self):
        calls, result = self.run_case('inspect-native', b'observed native head sequence: 11', missing_receipt=True)
        self.assertEqual(calls, ['status', 'prefix', 'receipt', 'inspect-native'])
        self.assertEqual(result['steps'][-1]['status'], 'TIMEOUT_OUTCOME_UNKNOWN')
        self.assertEqual(result['final_stop']['result'], 'NOT_RUN_COMMAND_OUTCOME_UNKNOWN')
        self.assertEqual(result['release_policy'], 'NOT_RUN')

if __name__ == '__main__':
    unittest.main()
