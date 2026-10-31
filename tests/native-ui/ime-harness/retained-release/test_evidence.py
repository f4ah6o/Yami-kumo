"""Non-GUI checks for preflight failure evidence and bounded teardown."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

HERE = Path(__file__).resolve().parent

class EvidenceTest(unittest.TestCase):
    def test_preflight_failure_writes_result_and_manifest(self):
        with tempfile.TemporaryDirectory() as name:
            env = dict(os.environ, YAMI_RELEASE_OUT=name,
                       YAMI_RELEASE_APP_TREE='/dev/null',
                       YAMI_RELEASE_FRAMEWORK_TREE='/dev/null')
            run = subprocess.run(['bash', str(HERE / 'session.sh')], env=env,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
            self.assertNotEqual(run.returncode, 0)
            out = Path(name)
            result = json.loads((out / 'result.json').read_text())
            self.assertEqual(result['session_exit_phase'], 'build')
            self.assertEqual(result['full_live_acceptance'], 'NOT_RUN')
            self.assertTrue(result['artifact_digest'].startswith('sha256:'))
            self.assertEqual(json.loads((out / 'build.json').read_text())['result'], 'FAIL')
            self.assertTrue((out / 'artifact-manifest.json').exists())

    def test_early_runtime_setup_failure_still_writes_evidence(self):
        with tempfile.TemporaryDirectory() as name, tempfile.TemporaryDirectory() as tools:
            fake = Path(tools) / 'mktemp'
            fake.write_text('#!/bin/sh\nexit 1\n')
            fake.chmod(0o755)
            env = dict(os.environ, YAMI_RELEASE_OUT=name,
                       PATH=tools + os.pathsep + os.environ['PATH'])
            run = subprocess.run(['bash', str(HERE / 'session.sh')], env=env,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
            self.assertNotEqual(run.returncode, 0)
            out = Path(name)
            result = json.loads((out / 'result.json').read_text())
            self.assertEqual(result['session_exit_phase'], 'environment_preflight')
            self.assertEqual(result['full_live_acceptance'], 'NOT_RUN')
            self.assertTrue(result['artifact_digest'].startswith('sha256:'))

    def test_group_and_child_writer_terminated_before_hash(self):
        with tempfile.TemporaryDirectory() as name:
            out = Path(name)
            with (out / 'child.log').open('w') as log:
                proc = subprocess.Popen(['sh', '-c', 'sleep 60 & wait'],
                                        stdout=log, stderr=log, start_new_session=True)
            try:
                time.sleep(.2)
                subprocess.run(['python3', str(HERE / 'finish.py'), name, '1', 'test',
                                str(proc.pid)], check=True, timeout=15)
                proc.wait(timeout=5)
                result = json.loads((out / 'result.json').read_text())
                self.assertEqual(result['log_shutdown']['tracked_groups_remaining'], [])
                self.assertEqual(result['log_shutdown']['visible_open_writers'], [])
                self.assertTrue(result['artifact_digest'].startswith('sha256:'))
            finally:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait(timeout=5)

    def test_ignored_term_is_killed_with_bounded_shutdown(self):
        with tempfile.TemporaryDirectory() as name:
            out = Path(name)
            with (out / 'ignore-term.log').open('w') as log:
                proc = subprocess.Popen(['sh', '-c', "trap '' TERM; sleep 60 & wait"],
                                        stdout=log, stderr=log, start_new_session=True)
            try:
                time.sleep(.2)
                start = time.monotonic()
                subprocess.run(['python3', str(HERE / 'finish.py'), name, '1', 'test',
                                str(proc.pid)], check=True, timeout=12)
                self.assertLess(time.monotonic() - start, 9)
                proc.wait(timeout=5)
                result = json.loads((out / 'result.json').read_text())
                self.assertEqual(result['log_shutdown']['tracked_groups_remaining'], [])
                self.assertEqual(result['log_shutdown']['visible_open_writers'], [])
            finally:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait(timeout=5)

    def test_escaped_writer_is_not_claimed_stable(self):
        with tempfile.TemporaryDirectory() as name:
            out = Path(name)
            with (out / 'escaped.log').open('w') as log:
                proc = subprocess.Popen(['sleep', '60'], stdout=log, stderr=log,
                                        start_new_session=True)
            try:
                subprocess.run(['python3', str(HERE / 'finish.py'), name, '1', 'test'],
                               check=True, timeout=12)
                result = json.loads((out / 'result.json').read_text())
                self.assertEqual(result['artifact_stability'], 'UNVERIFIED_WRITERS_OR_GROUPS')
                self.assertTrue(any(w['pid'] == proc.pid
                                    for w in result['log_shutdown']['visible_open_writers']))
            finally:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=5)

    def test_denied_descriptor_visibility_is_unverified(self):
        with tempfile.TemporaryDirectory() as name, tempfile.TemporaryDirectory() as hooks:
            out = Path(name)
            (Path(hooks) / 'sitecustomize.py').write_text("""
import os
from pathlib import Path
original_link = os.readlink
original_read = Path.read_text
pid = os.environ['DENY_PID']
mode = os.environ['DENY_MODE']
def readlink(path, *args, **kwargs):
    if mode == 'link' and str(path).startswith('/proc/' + pid + '/fd/'):
        raise PermissionError('controlled readlink denial')
    return original_link(path, *args, **kwargs)
def read_text(self, *args, **kwargs):
    if mode == 'info' and str(self).startswith('/proc/' + pid + '/fdinfo/'):
        raise PermissionError('controlled fdinfo denial')
    return original_read(self, *args, **kwargs)
os.readlink = readlink
Path.read_text = read_text
""")
            with (out / 'hidden-writer.log').open('w') as log:
                proc = subprocess.Popen(['sleep', '60'], stdout=log, stderr=log,
                                        start_new_session=True)
            try:
                for mode in ('link', 'info'):
                    env = dict(os.environ, PYTHONPATH=hooks, DENY_PID=str(proc.pid), DENY_MODE=mode)
                    subprocess.run(['python3', str(HERE / 'finish.py'), name, '1', 'test'],
                                   env=env, check=True, timeout=12)
                    result = json.loads((out / 'result.json').read_text())
                    self.assertGreater(result['log_shutdown']['uninspectable_fds'], 0, mode)
                    self.assertEqual(result['artifact_stability'], 'UNVERIFIED_WRITERS_OR_GROUPS', mode)
            finally:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=5)

if __name__ == '__main__':
    unittest.main()
