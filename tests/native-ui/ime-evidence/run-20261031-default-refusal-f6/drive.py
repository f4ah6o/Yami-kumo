import hashlib, json, subprocess
from pathlib import Path
out = Path('/workspace/evidence/yami-default-refusal-f6')
app = Path('/workspace/yami-release-handoff-build-final/native/debug/build/f4ah6o/yami_kumo_native/examples/ubuntu/ubuntu.exe')
with (out / 'app.log').open('wb') as log:
    process = subprocess.run([str(app), '--settings-e2e'], stdout=log, stderr=subprocess.STDOUT, timeout=12)
result = {'framework_sha':'b28cff9a8a92a155e67421a397a1030dedac9301','app_source_sha':'f6c4b40abbecd74b76a1fb459c360a104fd132dd','app_binary_sha256':hashlib.sha256(app.read_bytes()).hexdigest(),'command':'ubuntu.exe --settings-e2e','exit_code':process.returncode,'expected_one_shot_refusal':'ordered input requires a retained owner' in (out / 'app.log').read_text(errors='replace'),'full_live_acceptance':'NOT_RUN'}
(out / 'result.json').write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps(result))
