import hashlib, json, os, re, signal, subprocess, time
from pathlib import Path
out = Path('/workspace/evidence/yami-ci-kiosk-default-104')
app = Path('/workspace/yami-default-exact-build/native/debug/build/f4ah6o/yami_kumo_native/examples/ubuntu/ubuntu.exe')
with (out / 'app.log').open('w') as log:
    proc = subprocess.Popen(['stdbuf','-oL','-eL',str(app),'--settings-e2e'], stdout=log, stderr=subprocess.STDOUT, env=dict(os.environ, WAYLAND_DEBUG='client'))
    deadline=time.monotonic()+12
    while time.monotonic()<deadline and proc.poll() is None:
        data=(out/'app.log').read_text(errors='replace')
        if '"state":"active"' in data:
            break
        time.sleep(.1)
    data=(out/'app.log').read_text(errors='replace')
    result={'framework_sha':'b28cff9a8a92a155e67421a397a1030dedac9301','app_source_sha':'0ee49e9c593e14f2336c1ff8a7e8154a3b0b2e10','app_binary_sha256':hashlib.sha256(app.read_bytes()).hexdigest(),'command':'ubuntu.exe --settings-e2e','profile':'nested Weston x11 gl kiosk shell no-config; no input or injected X focus','active_control':'"state":"active"' in data,'reason_lines':re.findall(r'^YAMI_SETTINGS_CONTROL reason:.*$',data,re.M),'frame_markers':re.findall(r'^YAMI_NATIVE_UI_SETTINGS .*"phase":"frame".*$',data,re.M),'full_live_acceptance':'NOT_RUN'}
    match=re.search(r'YAMI_SETTINGS_CONTROL \{"path":"([^"]+)"',data)
    if match and proc.poll() is None and result['active_control']:
        status=subprocess.run(['python3','/workspace/yami-retained-default/scripts/settings_retained_control.py',match.group(1),'status'],capture_output=True,text=True,timeout=5)
        result['control_status']={'rc':status.returncode,'stdout':status.stdout,'stderr':status.stderr}
    result['forced_termination']=proc.poll() is None
    if proc.poll() is None:
        result['cleanup']='FAIL_FORCED_TERMINATION_OWNER_NOT_PERSISTED'
        proc.send_signal(signal.SIGTERM)
    result['exit_code']=proc.wait(timeout=5)
    if match:
        p=Path(match.group(1))
        p.unlink(missing_ok=True)
        p.parent.rmdir()
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
