"""Read-only artifact check after the exact harness session has exited."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
out = root / 'live'
result = json.loads((out / 'result.json').read_text())
build = json.loads((out / 'build.json').read_text())
manifest_path = out / 'artifact-manifest.json'
manifest = json.loads(manifest_path.read_text())
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
if result['artifact_digest'] != 'sha256:' + sha(manifest_path):
    raise SystemExit('result manifest digest mismatch')
for entry in manifest['files']:
    path = out / entry['path']
    if not path.resolve().is_relative_to(out.resolve()) or sha(path) != entry['sha256']:
        raise SystemExit('raw artifact mismatch: ' + entry['path'])
expected = {'app_sha': '1a59626cf67910917c4d660dd6db8bedae55a722',
            'framework_sha': '35b9041dfb3642b43ca37c604834942614eb50fb',
            'harness_sha': 'acd14b8788e7ece8ce5100348bfd6703186d2e75'}
for name, revision in expected.items():
    if build.get(name) != revision:
        raise SystemExit('build source mismatch: ' + name)
if build.get('result') != 'PASS' or sha(out / 'app.exe') != build['binary_sha256']:
    raise SystemExit('fresh live binary or build result mismatch')
if sha(out / 'app.exe') != result.get('app_binary_sha256'):
    raise SystemExit('executed binary digest mismatch')
print(json.dumps({'raw_artifact_hashes': 'MATCH', 'fresh_binary_provenance': 'MATCH',
                  'build': build['result'],
                  'preedit_probe': result.get('preedit_probe'),
                  'geometry_race': result.get('geometry_race'),
                  'cleanup_result': result.get('cleanup_result'),
                  'artifact_stability': result.get('artifact_stability'),
                  'full_live_acceptance': result.get('full_live_acceptance')}, indent=2))
