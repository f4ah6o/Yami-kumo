#!/usr/bin/env python3
"""Execute isolated production mutants; compilation failures do not count as kills.
Requires the pinned GPUI source via GPUI_SOURCE and installed MoonBit. No hosts.
"""
import json, os, pathlib, shutil, subprocess, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[2]
CASES = [
 ('wrong-native-fill','native/ui/ui.mbt','normal_fill=palette_color(token, @view.NormalFill)','normal_fill=palette_color(token, @view.HoveredFill)'),
 ('bypass-resolved-foreground','native/ui/ui.mbt','''      match text {
        Some(text) => {
          let align''','''      match binding.text {
        Some(text) => {
          let align'''),
 ('palette-recreates-native-binding','native/ui/ui.mbt','Some(binding) if binding.view.kind() == node.kind() => Some(binding)','Some(binding) if binding.view.kind() == node.kind() && binding.view.button_palette() == node.button_palette() => Some(binding)'),
 ('palette-recreates-runtime-token','ui/runtime/runtime.mbt','Some(previous) if previous.view.kind() == node.kind() => {','Some(previous) if previous.view.kind() == node.kind() && previous.view.button_palette() == node.button_palette() => {'),
 ('bootstrap-strips-palette','native/examples/shared_counter/app.mbt','''Some(token) =>
          @view.button_with_palette(
            view.key(),
            view.label(),
            token,
            disabled~,
            loading~,
          )''','''Some(_token) => @view.button(view.key(), view.label(), disabled~, loading~)'''),
]
def main():
 out=pathlib.Path(os.environ['YAMI_PALETTE_CONTROL_EVIDENCE']);out.mkdir(parents=True,exist_ok=True)
 gpui=pathlib.Path(os.environ['GPUI_SOURCE']).resolve()
 results=[]
 with tempfile.TemporaryDirectory(prefix='yami-palette-controls-') as temp:
  temp=pathlib.Path(temp); source=temp/'yami';source.mkdir()
  for path in ROOT.rglob('*'):
   rel=path.relative_to(ROOT)
   if any(p in {'.git','_build','node_modules','__pycache__'} for p in rel.parts) or not path.is_file():continue
   if path.suffix in {'.mbt','.mbti','.c','.h'} or path.name in {'moon.mod','moon.pkg'}:
    target=source/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,target)
  work=temp/'work';work.mkdir();(work/'moon.work').write_text('members = '+json.dumps([str(gpui),str(source),str(source/'native')])+'\n')
  shutil.copytree(gpui/'script',work/'script')
  for name,path,before,after in CASES:
   target=source/path;original=target.read_text();assert original.count(before)==1,(name,'missing/ambiguous mutation')
   target.write_text(original.replace(before,after))
   try:
    command=['moon','test',str(source/'native/ui'),str(source/'native/examples/shared_counter'),'--target','js','--no-parallelize']
    check=subprocess.run(['moon','check',str(source/'native/ui'),str(source/'native/examples/shared_counter'),'--target','js'],cwd=work,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
    (out/(name+'-check.log')).write_text(check.stdout)
    assert check.returncode==0,(name,'mutant did not compile')
    run=subprocess.run(command,cwd=work,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
    (out/(name+'.log')).write_text(run.stdout)
    assert run.returncode!=0 and ('failed:' in run.stdout or 'Assertion failed' in run.stdout),(name,'mutant was not assertion-killed')
    results.append({'name':name,'compiled':True,'assertionKilled':True,'exitCode':run.returncode,'command':command})
   finally:target.write_text(original)
 (out/'controls.json').write_text(json.dumps(results,indent=2)+'\n')
 print(json.dumps(results,indent=2))
if __name__=='__main__':main()
