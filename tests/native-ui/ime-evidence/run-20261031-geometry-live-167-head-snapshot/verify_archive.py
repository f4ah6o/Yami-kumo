"""Verify archived bytes, original raw manifest and gzip binary provenance."""
import gzip
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
def digest(data):
    return hashlib.sha256(data).hexdigest()
def file_digest(path):
    return digest(path.read_bytes())
def contained(relative):
    path = root / relative
    if not path.resolve().is_relative_to(root):
        raise SystemExit('archive path escapes root: ' + relative)
    return path

archive_path = root / 'archive-manifest.json'
archive = json.loads(archive_path.read_text())
for item in archive['files']:
    if file_digest(contained(item['path'])) != item['sha256']:
        raise SystemExit('archive mismatch: ' + item['path'])
raw_path = root / 'artifact-manifest.json'
raw = json.loads(raw_path.read_text())
result = json.loads((root / 'result.json').read_text())
build = json.loads((root / 'build.json').read_text())
if result['artifact_digest'] != 'sha256:' + file_digest(raw_path):
    raise SystemExit('original raw manifest digest mismatch')
binary_digest = digest(gzip.decompress((root / 'app.exe.gz').read_bytes()))
for item in raw['files']:
    actual = binary_digest if item['path'] == 'app.exe' else file_digest(contained(item['path']))
    if actual != item['sha256']:
        raise SystemExit('original raw mismatch: ' + item['path'])
if binary_digest != build['binary_sha256'] or binary_digest != result['app_binary_sha256']:
    raise SystemExit('built/executed/archived binary digest mismatch')
expected = {
    'app_sha': 'e9fe5fe06111dce33be20f3f93d8be819194486f',
    'framework_sha': '35b9041dfb3642b43ca37c604834942614eb50fb',
    'harness_sha': 'aa7c81288b81617a5e8a346347fe355e38d5b834',
}
for name, value in expected.items():
    if build[name] != value:
        raise SystemExit('source revision mismatch: ' + name)
copies = json.loads((root / 'source-copy-map.json').read_text())
for item in copies['files']:
    if file_digest(contained(item['archive_path'])) != item['archive_sha256']:
        raise SystemExit('copy representation mismatch: ' + item['archive_path'])
    if item['representation'] == 'byte-identical' and item['archive_sha256'] != item['original_sha256']:
        raise SystemExit('copy differs from recorded original: ' + item['archive_path'])
print(json.dumps({
    'committed_file_hashes': 'MATCH', 'committed_files': len(archive['files']),
    'original_raw_hashes': 'MATCH', 'original_raw_files': len(raw['files']),
    'fresh_built_executed_archived_binary': 'MATCH',
    'binary_sha256': binary_digest, 'source_triplet': expected,
    'cleanup_result': result['cleanup_result'],
    'artifact_stability': result['artifact_stability'],
    'early_error': result.get('error'),
    'geometry_guard_markers': result.get('geometry_guard_markers'),
    'native_head_inspection': result.get('native_head_inspection'),
    'native_head_markers': result.get('native_head_markers'),
    'control_commands': [step['command'] for step in result['steps']],
    'stop_request_sent': any(step['command'] == 'stop' for step in result['steps']),
    'run_location': 'local', 'run_url': result['run_url'],
    'full_live_acceptance': result['full_live_acceptance'],
}, indent=2))
