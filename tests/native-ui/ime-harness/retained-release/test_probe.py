"""Synthetic bounded-probe tests; not live IME acceptance."""
import unittest
import subprocess
from probe import advance_until_preedit, preedit_markers, run_control_command

class ProbeTest(unittest.TestCase):
    def test_frame_then_new_preedit_is_observed_after_second_step(self):
        log = ['YAMI_NATIVE_UI_SETTINGS {"phase":"preedit","text":"ｎ"}\n']
        calls = []
        def send(command, sequence=None):
            calls.append((command, sequence))
            if command == 'generation':
                return {'rc': 0, 'stdout': f'continuation generation: {1 + len(calls)//2}\n'}
            if len([c for c in calls if c[0] == 'advance']) == 2:
                log[0] += 'YAMI_NATIVE_UI_SETTINGS {"phase":"preedit","text":"に"}\n'
            return {'rc': 0, 'stdout': ''}
        result = advance_until_preedit(lambda: log[0], send, 1, 'に', pause=lambda _: None)
        self.assertEqual(result['result'], 'OBSERVED_CONSUMER_PREEDIT')
        self.assertEqual(len(result['attempts']), 2)
        self.assertEqual(calls, [('generation', None), ('advance', 1), ('generation', None), ('advance', 2)])

    def test_old_matching_marker_does_not_satisfy_probe(self):
        log = 'YAMI_NATIVE_UI_SETTINGS {"phase":"preedit","text":"に"}\n'
        def send(command, sequence=None):
            return {'rc': 0, 'stdout': 'continuation generation: 1\n' if command == 'generation' else ''}
        result = advance_until_preedit(lambda: log, send, 1, 'に', limit=2, pause=lambda _: None)
        self.assertEqual(result['result'], 'NOT_OBSERVED_WITHIN_LIMIT')
        self.assertEqual(len(result['attempts']), 2)

    def test_generation_unavailable_stays_blocked(self):
        result = advance_until_preedit(lambda: '', lambda *_: {'rc': 0, 'stdout': 'none'}, 0, 'に', pause=lambda _: None)
        self.assertEqual(result['result'], 'BLOCKED_GENERATION_UNAVAILABLE')
        self.assertEqual(result['attempts'], [])

    def test_advance_error_does_not_continue(self):
        def send(command, sequence=None):
            return {'rc': 0, 'stdout': 'continuation generation: 1'} if command == 'generation' else {'rc': 2, 'stdout': ''}
        result = advance_until_preedit(lambda: '', send, 0, 'に', pause=lambda _: None)
        self.assertEqual(result['result'], 'BLOCKED_ADVANCE_ERROR')
        self.assertEqual(len(result['attempts']), 1)

    def test_generation_timeout_records_attempt_and_stays_unknown(self):
        steps = []
        def timed_out(args, **kwargs):
            raise subprocess.TimeoutExpired(args, kwargs['timeout'], output=b'partial')
        def send(command, sequence=None):
            return run_control_command(['control', command], steps, command, sequence, timed_out)
        result = advance_until_preedit(lambda: '', send, 0, 'に', pause=lambda _: None)
        self.assertEqual(result['result'], 'BLOCKED_GENERATION_TIMEOUT_OUTCOME_UNKNOWN')
        self.assertEqual(steps[0]['command'], 'generation')
        self.assertEqual(steps[0]['stdout'], 'partial')
        self.assertEqual(steps[0]['status'], 'TIMEOUT_OUTCOME_UNKNOWN')
        self.assertEqual(len(steps), 1)

    def test_advance_timeout_records_generation_and_sequence_without_retry(self):
        steps = []
        def run(args, **kwargs):
            if args[-1] == 'generation':
                return subprocess.CompletedProcess(args, 0, 'continuation generation: 19', '')
            raise subprocess.TimeoutExpired(args, kwargs['timeout'])
        def send(command, sequence=None):
            return run_control_command(['control', command], steps, command, sequence, run)
        result = advance_until_preedit(lambda: '', send, 0, 'に', pause=lambda _: None)
        self.assertEqual(result['result'], 'BLOCKED_ADVANCE_TIMEOUT_OUTCOME_UNKNOWN')
        self.assertEqual(steps[1]['sequence'], 19)
        self.assertEqual(steps[1]['status'], 'TIMEOUT_OUTCOME_UNKNOWN')
        self.assertEqual(len(result['attempts']), 1)
        self.assertEqual(len(steps), 2)

    def test_untrusted_bounds_rejected_and_malformed_lines_ignored(self):
        self.assertEqual(preedit_markers('YAMI_NATIVE_UI_SETTINGS nope\n'), [])
        with self.assertRaises(ValueError):
            advance_until_preedit(lambda: '', lambda *_: {}, 0, 'に', limit=9)

if __name__ == '__main__':
    unittest.main()
