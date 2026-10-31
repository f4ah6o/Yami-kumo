"""Read-only verification before the separately authorized live launch."""
import hashlib
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent
record = json.loads((root / 'preparation-provenance.json').read_text())
for name, source in record['sources'].items():
    tree = source['path']
    head = subprocess.check_output(['git', '-C', tree, 'rev-parse', 'HEAD'], text=True).strip()
    status = subprocess.check_output(['git', '-C', tree, 'status', '--porcelain'], text=True).strip()
    if head != source['head'] or status:
        raise SystemExit('source changed after preparation: ' + name)
checks = {}
checks.update(record['protocol_generation']['inputs'])
checks.update(record['protocol_generation']['outputs'])
checks.update({str(root / name): expected
               for name, expected in record['prepared_files_sha256'].items()})
for info in record['tools'].values():
    if info.get('path') and info.get('sha256'):
        checks[info['path']] = info['sha256']
for path, info in record['static_files'].items():
    if info.get('sha256'):
        checks[path] = info['sha256']
for path, expected in checks.items():
    if hashlib.sha256(Path(path).read_bytes()).hexdigest() != expected:
        raise SystemExit('prepared input changed: ' + path)
print('Exact sources and recorded protocol/tool inputs match preparation.')
