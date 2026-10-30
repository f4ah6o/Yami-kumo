import importlib.util, json, os, subprocess, sys, time
from pathlib import Path
path=str(Path(__file__).resolve().parents[1] / 'drive_settings.py')
spec=importlib.util.spec_from_file_location('settings_driver',path); d=importlib.util.module_from_spec(spec); sys.modules[spec.name]=d; spec.loader.exec_module(d)
out=Path(os.environ['YAMI_IME_OUT']).resolve()
out.mkdir(parents=True, exist_ok=True)
app=str(Path(os.environ['YAMI_IME_APP']).resolve())
process=subprocess.Popen([app,'--settings-e2e'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',bufsize=1,env=dict(os.environ,WAYLAND_DEBUG='client'))
o=d.Output(process,out/'app.log')
def marker(pred, timeout=12, start=0):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  for m in o.markers[start:]:
   if pred(m): return m
  try: o.next_line(min(1,max(.01,end-time.monotonic())))
  except d.SettingsError as e:
   if process.poll() is not None or 'timed out waiting' not in str(e): raise
 raise RuntimeError('marker timeout: '+repr(o.markers[-15:]))
def send(key):
 if key in ('ctrl+z','ctrl+shift+z'):
  d.xdotool('keydown','ctrl'); time.sleep(.15)
  if 'shift' in key: d.xdotool('keydown','shift'); time.sleep(.15)
  d.xdotool('key','z'); time.sleep(.15)
  if 'shift' in key: d.xdotool('keyup','shift')
  d.xdotool('keyup','ctrl')
 else: d.xdotool('key','--clearmodifiers',key)
 time.sleep(.1)
result={'framework_sha':os.environ['YAMI_IME_FRAMEWORK_SHA'],'app_source_sha':os.environ['YAMI_IME_APP_SHA'],'app_binary_sha256':__import__('hashlib').sha256(Path(app).read_bytes()).hexdigest(),'status':'FAIL','stage':'startup','observations':{}}
try:
 window=d.wait_window(o,30); result['x11Focus']=d.focus_window(o,window)
 o.wait_frame(lambda f:f.get('focus')=='name',20)
 result['observations']['started']=marker(lambda m:m.get('phase')=='text' and m.get('status')=='started',20)
 result['stage']='ime-readiness'
 end=time.monotonic()+15
 while time.monotonic()<end:
  w=(out/'ibus-ui-wayland.log').read_text(errors='replace'); b=(out/'ibus-ui-dbus.log').read_text(errors='replace')
  if '.grab_keyboard(' in w and "member -> 'RegisterProperties'" in b: break
  time.sleep(.05)
 else: raise RuntimeError('IME keyboard grab or properties not ready')
 time.sleep(1)
 result['stage']='preedit'
 for k in 'nihonn': send(k)
 result['observations']['preedit']=marker(lambda m:m.get('phase')=='preedit' and m.get('text')=='にほん',12)
 result['observations']['uncommitted_frame']=o.wait_frame(lambda f:f.get('name')=='',5)
 result['stage']='cancel-candidate'
 for k in ['space','space']: send(k)
 time.sleep(.3)
 subprocess.run(['import','-window','root',str(out/'candidates-before-cancel.png')],check=True)
 send('Escape')
 time.sleep(.3)
 subprocess.run(['import','-window','root',str(out/'after-candidate-cancel.png')],check=True)
 result['stage']='cancel-preedit'
 before=len(o.markers); send('Escape')
 result['observations']['cancel_preedit']=marker(lambda m:m.get('phase')=='preedit' and m.get('text')=='',12,before)
 # The empty preedit marker fences the output stream before counting frames.
 cancel_frames=len(o.frames)
 result['observations']['cancel_frame']=o.wait_frame(lambda f:f.get('name')=='',12,after=cancel_frames)
 time.sleep(.3)
 subprocess.run(['import','-window','root',str(out/'after-preedit-cancel.png')],check=True)
 before=len(o.markers)
 for k in 'nihonn': send(k)
 marker(lambda m:m.get('phase')=='preedit' and m.get('text')=='にほん',12,before)
 result['stage']='conversion'
 for k in ['space','space']: send(k)
 time.sleep(.3)
 subprocess.run(['import','-window','root',str(out/'candidates.png')],check=True)
 send('Up')
 time.sleep(.3)
 subprocess.run(['import','-window','root',str(out/'candidate-selected.png')],check=True)
 result['observations']['conversion']=marker(lambda m:m.get('phase')=='preedit' and m.get('text')=='日本',12)
 result['stage']='commit'
 start=len(o.markers); send('Return')
 result['observations']['commit']=marker(lambda m:m.get('phase')=='commit' and m.get('text')=='日本',12,start)
 result['observations']['committed_frame']=o.wait_frame(lambda f:f.get('name')=='日本',12)
 if len([m for m in o.markers[start:] if m.get('phase')=='commit' and m.get('text')=='日本']) != 1: raise RuntimeError('duplicate commit observed')
 time.sleep(.3)
 subprocess.run(['import','-window','root',str(out/'after-commit.png')],check=True)
 result['stage']='undo'
 after=len(o.frames); send('ctrl+z')
 result['observations']['undo_frame']=o.wait_frame(lambda f:f.get('name')=='',12,after=after)
 result['stage']='redo'
 after=len(o.frames); send('ctrl+shift+z')
 result['observations']['redo_frame']=o.wait_frame(lambda f:f.get('name')=='日本',12,after=after)
 result['stage']='dialog'
 def step(key,dialog,focus):
  after=len(o.frames); send(key)
  return o.wait_frame(lambda f:f.get('dialog') is dialog and f.get('focus')==focus and f.get('name')=='日本',12,after=after)
 result['observations']['field_open']=step('Return',True,'confirm')
 subprocess.run(['import','-window','root',str(out/'dialog.png')],check=True)
 if os.environ.get('YAMI_IME_BACKGROUND_POINT'):
  x,y=os.environ['YAMI_IME_BACKGROUND_POINT'].split(',')
  after=len(o.frames)
  d.xdotool('mousemove','--sync',x,y,'click','1')
  result['observations']['background_click']=o.wait_frame(lambda f:f.get('dialog') is False and f.get('focus')=='name' and f.get('name')=='日本',12,after=after)
  dismissed_index=len(o.frames)-1
  time.sleep(.3)
  while not o.lines.empty():
   line=o.lines.get_nowait()
   if line is not None: o._handle(line)
  if any(f.get('dialog') is True or f.get('status') != 'editing' or f.get('name') != '日本' for f in o.frames[dismissed_index+1:]):
   raise RuntimeError('background click caused an unexpected model action')
  subprocess.run(['import','-window','root',str(out/'after-background-click.png')],check=True)
  result['observations']['background_click_point']={'x':int(x),'y':int(y)}
  result['observations']['after_backdrop_reopen']=step('Return',True,'confirm')
 send('x')
 # A fresh later frame must retain the model after background key delivery.
 result['observations']['after_background_key']=step('shift+Tab',True,'cancel')
 result['observations']['tab']=step('Tab',True,'confirm')
 result['observations']['field_restore']=step('Escape',False,'name')
 result['observations']['field_reopen']=step('Return',True,'confirm')
 result['observations']['field_restore_again']=step('Escape',False,'name')
 result['observations']['field_open_to_confirm']=step('Return',True,'confirm')
 after=len(o.frames); send('Return')
 result['observations']['saved']=o.wait_frame(lambda f:f.get('dialog') is False and f.get('status')=='saved' and f.get('name')=='日本',12,after=after)
 if len([m for m in o.markers if m.get('phase')=='commit' and m.get('text')=='日本']) != 1: raise RuntimeError('duplicate commit observed')
 result['status']='PASS'; result['stage']='complete'
except Exception as e:
 result['error']=str(e)
finally:
 if process.poll() is None: process.terminate()
 try: process.wait(timeout=5)
 except subprocess.TimeoutExpired: process.kill(); process.wait()
 while not o.lines.empty():
  line=o.lines.get_nowait()
  if line is not None: o._handle(line)
 o.close()
 (out/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps(result,ensure_ascii=False))
 sys.exit(0 if result['status']=='PASS' else 1)
