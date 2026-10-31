"""Bounded consumer-observed preedit probe; no scene or IME proof implied."""
import json
import re
import time

PREFIX = 'YAMI_NATIVE_UI_SETTINGS '

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
            return {'result': 'BLOCKED_GENERATION_UNAVAILABLE', 'expected': expected,
                    'attempts': attempts, 'generation': generation}
        sequence = int(match.group(1))
        step = command('advance', sequence)
        attempts.append({'generation': generation, 'advance': step})
        if step.get('rc') != 0:
            return {'result': 'BLOCKED_ADVANCE_ERROR', 'expected': expected,
                    'attempts': attempts}
        pause(.1)
    return {'result': 'NOT_OBSERVED_WITHIN_LIMIT', 'expected': expected,
            'attempts': attempts, 'markers': preedit_markers(read_log())[baseline_count:]}
