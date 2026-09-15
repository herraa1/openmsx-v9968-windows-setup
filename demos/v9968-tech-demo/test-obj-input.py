from pathlib import Path
import ast,json,math,subprocess,sys,hashlib,shutil,tempfile,atexit
reference_assets=Path(__file__).resolve().parent/'assets'
work=tempfile.TemporaryDirectory(prefix='v9968-obj-test-')
atexit.register(work.cleanup)
root=Path(work.name);demo=root/'demo';demo.mkdir()
shutil.copytree(reference_assets,demo/'assets')
src=demo/'generate-megarom.py'
shutil.copy2(Path(__file__).resolve().parent/'generate-megarom.py',src)
fixtures=root/'fixtures';fixtures.mkdir()
tree=ast.parse(src.read_text(encoding='utf-8'));nodes=[]
for n in tree.body:
 if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='parser' for t in n.targets):break
 nodes.append(n)
ns={'__file__':str(src)};exec(compile(ast.Module(body=nodes,type_ignores=[]),str(src),'exec'),ns)
results={}
for value in ['nan','inf','-inf','1e999']:
 p=fixtures/'nonfinite.obj';p.write_text(f'# test\nv {value} 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n')
 try:ns['load_obj'](p)
 except ValueError as e:assert ':2: vertex must be finite' in str(e)
 else:raise AssertionError(value)
results['nonfinite_vertex_diagnostics']='PASS: nan, inf, -inf, overflow; path and line2'
base=(demo/'assets/octahedron.obj').read_text();expected=ns['load_obj'](demo/'assets/octahedron.obj')
continued=[]
for line in base.splitlines():
 if line.startswith('f '):
  x=line.split();line=' '.join(x[:3])+' '+chr(92)+' # continuation\n  '+x[3]
 continued.append(line)
p=fixtures/'continued.obj';p.write_text('\n'.join(continued));assert ns['load_obj'](p)==expected
results['continued_faces']='PASS: all octahedron faces equal, including comments'
p.write_text('v 0 '+chr(92)+'\n0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n');assert len(ns['load_obj'](p)[0])==3
p.write_text('v 0 0 0\nf 1 2 '+chr(92))
try:ns['load_obj'](p)
except ValueError as e:assert ':2: unfinished line continuation' in str(e)
else:raise AssertionError('dangling continuation')
results['continued_vertex_and_unterminated_eof']='PASS'
def run(script,*args):
 p=subprocess.run([sys.executable,'-X','utf8',str(script),*map(str,args)],capture_output=True,text=True,encoding='utf-8')
 return p
p=run(src);assert p.returncode==0,p.stderr
outputs=['mesh-source-preview.png','mesh-reference.json','megarom-data.bin','bank-layout.h','bank-layout.json']
snap=lambda:{n:hashlib.sha256((demo/'assets'/n).read_bytes()).hexdigest() for n in outputs}
before=snap()
late=demo/'late-failure.py';code=src.read_text(encoding='utf-8');assert 'if count>MAX_MESH_RECTS:' in code
late.write_text(code.replace('if count>MAX_MESH_RECTS:','if count>(0 if f==17 else MAX_MESH_RECTS):'),encoding='utf-8')
p=run(late,'--mesh-obj','assets/torus.obj','--mesh-radius','74');assert p.returncode!=0 and 'frame 17' in p.stderr,p.stderr
assert snap()==before
results['injected_capacity_failure_after_preview_frame']='PASS: frame17 failure leaves all five output files unchanged'
results['generated_default_assets_match_pre_review']={n:before[n]==hashlib.sha256((reference_assets/n).read_bytes()).hexdigest() for n in outputs if (reference_assets/n).is_file()}
assert all(results['generated_default_assets_match_pre_review'].values())
results['late_failure_kind']='Artificial test-only threshold at frame17; not a naturally oversized OBJ'
(root/'review-host-results.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2))
