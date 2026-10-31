"""Bounded consumer-observed preedit probe; no scene or IME proof implied."""
import json
import re
import subprocess
import time

PREFIX = 'YAMI_NATIVE_UI_SETTINGS '

def run_control_command(args, steps, command, sequence, runner=None):
    # Record the attempt before starting the bounded subprocess. A timeout
    # cannot establish whether the owner received or executed the command.
    event = {'command': command, 'sequence': sequence, 'status': 'STARTED',
             'rc': None, 'stdout': '', 'stderr': ''}
    steps.append(event)
    if runner is None:
        runner = subprocess.run
    try:
        reply = runner(args, capture_output=True, text=True, timeout=5)
    except subprocess.TimeoutExpired as exc:
        def as_text(value):
            return value.decode('utf-8', errors='replace') if isinstance(value, bytes) else (value or '')
        event.update(status='TIMEOUT_OUTCOME_UNKNOWN', stdout=as_text(exc.stdout),
                     stderr=as_text(exc.stderr), timeout_seconds=exc.timeout)
        return event
    except Exception as exc:
        event.update(status='ERROR', error=repr(exc))
        raise
    event.update(status='RETURNED', rc=reply.returncode,
                 stdout=reply.stdout, stderr=reply.stderr)
    return event

def preedit_markers(log):
    markers = []
    for line in log.splitlines():
        if not line.startswith(PREFIX):
            continue
        try:
            event = json.loads(line[len(PREFIX):])
        except json.JSONDecodeError:
            continue
        if event.get('phase') == 'preedit':
            markers.append(event)
    return markers

def advance_until_preedit(read_log, command, baseline_count, expected, limit=8, pause=time.sleep):
    if limit < 0 or limit > 8 or baseline_count < 0:
        raise ValueError('invalid bounded preedit probe')
    attempts = []
    for _ in range(limit + 1):
        markers = preedit_markers(read_log())
        if any(value.get('text') == expected for value in markers[baseline_count:]):
            return {'result': 'OBSERVED_CONSUMER_PREEDIT', 'expected': expected,
                    'attempts': attempts, 'markers': markers[baseline_count:]}
        if len(attempts) == limit:
            break
        generation = command('generation')
        match = re.search(r'continuation generation: (\d+)', generation.get('stdout', ''))
        if generation.get('rc') != 0 or match is None or int(match.group(1)) <= 0:
            reason = 'BLOCKED_GENERATION_TIMEOUT_OUTCOME_UNKNOWN' if generation.get('status') == 'TIMEOUT_OUTCOME_UNKNOWN' else 'BLOCKED_GENERATION_UNAVAILABLE'
            return {'result': reason, 'expected': expected,
                    'attempts': attempts, 'generation': generation}
        sequence = int(match.group(1))
        step = command('advance', sequence)
        attempts.append({'generation': generation, 'advance': step})
        if step.get('rc') != 0:
            reason = 'BLOCKED_ADVANCE_TIMEOUT_OUTCOME_UNKNOWN' if step.get('status') == 'TIMEOUT_OUTCOME_UNKNOWN' else 'BLOCKED_ADVANCE_ERROR'
            return {'result': reason, 'expected': expected,
                    'attempts': attempts}
        pause(.1)
    return {'result': 'NOT_OBSERVED_WITHIN_LIMIT', 'expected': expected,
            'attempts': attempts, 'markers': preedit_markers(read_log())[baseline_count:]}
