#!/usr/bin/env python3
"""Bounded Linux x86-64 record-call target scheduling witness.

Tests all eight native option combinations with PIE/non-PIE clients and normal/
preload binding. For local execution follow the repository verification policy.
This witness does not certify N13, M04, or the held integration gate.
"""
import argparse,fcntl,hashlib,itertools,json,os,platform,re,resource,shutil,subprocess,tempfile
from pathlib import Path

if not __debug__:
 raise SystemExit('Python optimization disables required safety checks')
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--compiler',required=True,type=Path)
p.add_argument('--cc',default='cc')
p.add_argument('--readelf',default='readelf')
p.add_argument('--lock',type=Path,default=Path('/data/zbe-coordination/full-verification.lock'))
p.add_argument('--evidence-dir',type=Path)
a=p.parse_args()
if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64'):
 p.error('Linux x86-64 ELF required')
compiler=a.compiler.resolve(strict=True); cc=shutil.which(a.cc); readelf=shutil.which(a.readelf)
if not cc or not readelf: p.error('C compiler and readelf required')
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
soft,hard=resource.getrlimit(resource.RLIMIT_AS)
cap=min(x for x in (4*1024**3,soft,hard) if x!=resource.RLIM_INFINITY)
resource.setrlimit(resource.RLIMIT_AS,(cap,hard))
if hasattr(os,'sched_getaffinity'): os.sched_setaffinity(0,sorted(os.sched_getaffinity(0))[:2])
lock=a.lock.open('a')
try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
except BlockingIOError: raise SystemExit('verification lock is busy; no commands were run')
tmp=None
if a.evidence_dir:
 root=a.evidence_dir.resolve(); root.mkdir(parents=True,exist_ok=False)
else:
 tmp=tempfile.TemporaryDirectory(prefix='zbe-record-target-'); root=Path(tmp.name)
src=Path(__file__).resolve().parents[1]/'src/fixtures/extern-got-record-target'
clean={'PATH':os.environ.get('PATH','/usr/bin:/bin'),'LC_ALL':'C'}
flags=['--fold-integers','--reuse-stack-homes','--callee-saved-homes']
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in (compiler,Path(__file__).resolve(),*(src/x for x in ('input.ssa','provider.c','provider.S','client.c')))}
(root/'hashes.json').write_text(json.dumps(hashes,indent=2)+'\n')
count=0
for bits in itertools.product((False,True),repeat=3):
 d=root/('opt-'+''.join(str(int(b)) for b in bits)); d.mkdir()
 for x in ('input.ssa','provider.c','provider.S','client.c'): shutil.copyfile(src/x,d/x)
 journal=d/'commands.jsonl'
 def run(argv,env=None,expected=0):
  argv=list(map(str,argv)); e=clean if env is None else env
  try:
   p=subprocess.run(argv,cwd=d,env=e,capture_output=True,text=True,errors='replace',timeout=90)
   record={'argv':argv,'env':e,'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
  except subprocess.TimeoutExpired as exc:
   with journal.open('a') as f: f.write(json.dumps({'argv':argv,'env':e,'timeout':str(exc)})+'\n')
   raise
  with journal.open('a') as f: f.write(json.dumps(record)+'\n')
  if p.returncode!=expected: raise RuntimeError(f'{argv}: expected {expected}, got {p.returncode}; {p.stdout!r} {p.stderr!r}')
  return p.stdout
 active=[f for f,b in zip(flags,bits) if b]
 run([compiler,*active,'input.ssa','base.s'])
 asm=(d/'base.s').read_text(); start=asm.index('run_record_early:\n'); end=asm.index('.size run_record_early,',start); body=asm[start:end]
 needle='\tmovq m04_real@GOTPCREL(%rip), %rax\n\tmovq %rax, %r11\n'; assert body.count(needle)==1
 target=body.index(needle); calls=list(re.finditer(r'\tcall \*%r11\n',body)); assert len(calls)==1 and calls[0].start()>target
 pack=body.rfind('\tmovq %rax, %r11\n',0,target); assert pack>=0
 prev=body.rfind('\n',0,pack-1)+1; source=body[prev:pack]
 if not re.fullmatch(r'\tmovq [^\n]+, %rax\n',source): raise RuntimeError('unexpected source load before packing: '+repr(source))
 between=body[pack+len('\tmovq %rax, %r11\n'):target]
 if re.search(r'\b(?:mov|lea|pop|xor|add|sub|and|or|shl|shr)[a-z]*\s+[^\n]*,\s*%r11\b',between): raise RuntimeError('unexpected R11 write after packing')
 # Relocate, not replace or synthesize, the exact emitted late target load.
 mutant=body[:prev]+needle+body[prev:target]+body[target+len(needle):]
 (d/'mutant.s').write_text(asm[:start]+mutant+asm[end:])
 for base,name in ((10,'provider'),(200,'override')):
  run([cc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-fPIC','-shared',f'-DBASE={base}','provider.c','provider.S','-Wl,-soname,lib'+name+'.so','-o','lib'+name+'.so'])
 def link(assembly):
  run([cc,'-fPIC','-c',assembly,'-o','subject.o'])
  run([cc,'-shared','subject.o','-Wl,--no-relax','-L.','-Wl,--no-as-needed','-lprovider','-Wl,-rpath,$ORIGIN','-o','libsubject.so'])
  reloc=run([readelf,'-rW','libsubject.so'])
  if not any('R_X86_64_GLOB_DAT' in line and re.search(r'\bm04_real\b',line) for line in reloc.splitlines()): raise RuntimeError('target lacks dynamic GLOB_DAT')
 def verify():
  for binary in ('libprovider.so','liboverride.so','libsubject.so','client'):
   if 'R_X86_64_COPY' in run([readelf,'-rW',binary]): raise RuntimeError(binary+' COPY')
   dyn=run([readelf,'-dW',binary]);
   if 'TEXTREL' in dyn or 'SYMBOLIC' in dyn: raise RuntimeError(binary+' forbidden dynamic property')
 preload={**clean,'LD_PRELOAD':str(d/'liboverride.so')}
 for pie in (False,True):
  link('base.s')
  mode=['-fPIE','-pie'] if pie else ['-fno-pie','-no-pie']
  run([cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',*mode,'client.c','-L.','-Wl,--no-as-needed','-lsubject','-lprovider','-Wl,-rpath,$ORIGIN','-Wl,-rpath-link,.','-ldl','-o','client'])
  verify()
  for expected,e in ((10,clean),(200,preload)):
   assert 'record target check passed' in run(['./client',expected],e)
   count+=1
  link('mutant.s'); verify()
  for expected,e in ((10,clean),(200,preload)): run(['./client',expected],e,expected=21)
  count+=2
print('PASS: 32 baseline executions and 32 callable early-target mutant sentinel detections; runs=',count)
