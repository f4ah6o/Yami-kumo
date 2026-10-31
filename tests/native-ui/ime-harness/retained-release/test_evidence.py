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

if __name__ == '__main__':
    unittest.main()
