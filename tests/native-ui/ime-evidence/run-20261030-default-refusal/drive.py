import hashlib, json, subprocess
from pathlib import Path
out = Path('/workspace/evidence/yami-default-refusal-c8')
app = Path('/workspace/yami-entry-retained-build/native/debug/build/f4ah6o/yami_kumo_native/examples/ubuntu/ubuntu.exe')
with (out / 'app.log').open('wb') as log:
    process = subprocess.run([str(app), '--settings-e2e'], stdout=log, stderr=subprocess.STDOUT, timeout=12)
result = {'framework_sha':'5cd2f231c6cbf529396cae633f6e5a0d6c9bea41','app_source_sha':'c8ce64da8b566e0672d1ae92851da811b8e151ae','app_binary_sha256':hashlib.sha256(app.read_bytes()).hexdigest(),'command':'ubuntu.exe --settings-e2e','exit_code':process.returncode,'expected_one_shot_refusal':'ordered input requires a retained owner' in (out / 'app.log').read_text(errors='replace'),'full_live_acceptance':'NOT_RUN'}
(out / 'result.json').write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps(result))
