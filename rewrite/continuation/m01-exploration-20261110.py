import os,resource,fcntl,subprocess,pathlib,json,hashlib,shutil
D=pathlib.Path('/data/m01-exploration-20261110'); os.chdir(D)
os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:2]); soft,hard=resource.getrlimit(resource.RLIMIT_AS); cap=min(x for x in (4*1024**3,soft,hard) if x != resource.RLIM_INFINITY); resource.setrlimit(resource.RLIMIT_AS,(cap,hard)); resource.setrlimit(resource.RLIMIT_CORE,(0,0))
lock=open('/data/zbe-coordination/full-verification.lock','a')
try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
except BlockingIOError: print('LOCK HELD: no commands run'); raise SystemExit(75)
log={'affinity':sorted(os.sched_getaffinity(0)),'vmem_soft':cap,'commands':[]}
env={k:os.environ[k] for k in ('PATH','HOME','TMPDIR') if k in os.environ};env['LC_ALL']='C'
def run(*args,extra=None):
 e=dict(env);e.update(extra or {});p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=e,timeout=30); log['commands'].append({'args':args,'env':extra or {},'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr});return p
sources={
'provider.c':'int external_fn(void) { return 10; }\nint external_data = 10;\n',
'override.c':'int external_fn(void) { return 200; }\nint external_data = 200;\n',
'oracle.c':'extern int external_fn(void); extern int external_data; int (*oracle_fn(void))(void) { return external_fn; } int *oracle_data(void) { return &external_data; }\n',
'good.s':'.text\n.globl candidate\n.type candidate,@function\ncandidate:\n movq external_fn@GOTPCREL(%rip),%rax\n ret\n.size candidate,.-candidate\n.section .note.GNU-stack,"",@progbits\n',
'bad.s':'.text\n.globl candidate\n.type candidate,@function\ncandidate:\n leaq external_fn(%rip),%rax\n ret\n.size candidate,.-candidate\n.section .note.GNU-stack,"",@progbits\n',
'bad-data.s':'.text\n.globl data_candidate\n.type data_candidate,@function\ndata_candidate:\n leaq external_data(%rip),%rax\n ret\n.size data_candidate,.-data_candidate\n.section .note.GNU-stack,"",@progbits\n',
'main.c':'#include <stdio.h>\n#include <stdlib.h>\ntypedef int (*fn)(void); extern fn candidate(void); extern fn oracle_fn(void); extern int *oracle_data(void);\nint main(int argc,char **argv) { if(argc!=2) return 90; int expected=atoi(argv[1]); fn p=oracle_fn(), q=candidate(); if(!p || p()!=expected || *oracle_data()!=expected) { puts("baseline selection failed"); return 91; } if(p!=q) { puts("identity failed (oracle selected expected override)"); return 31; } puts("baseline and identity passed"); return 0; }\n'}
for n,s in sources.items():(D/n).write_text(s)
for cmd in [('gcc','--version'),('ld.bfd','--version'),('as','--version'),('readelf','--version'),('gcc','-dumpmachine'),('gcc','-fuse-ld=bfd','-###','-shared','-x','c','/dev/null','-o','/dev/null')]:run(*cmd)
cmds=[('gcc','-fPIC','-Wall','-Wextra','-Werror','-c','provider.c','-o','provider.o'),('gcc','-fPIC','-Wall','-Wextra','-Werror','-c','override.c','-o','override.o'),('gcc','-fPIC','-Wall','-Wextra','-Werror','-c','oracle.c','-o','oracle.o'),('gcc','-c','good.s','-o','good.o'),('gcc','-c','bad.s','-o','bad.o'),('gcc','-c','bad-data.s','-o','bad-data.o'),('gcc','-fPIE','-Wall','-Wextra','-Werror','-c','main.c','-o','main-pie.o'),('gcc','-fno-pie','-Wall','-Wextra','-Werror','-c','main.c','-o','main-nopie.o'),('gcc','-fuse-ld=bfd','-shared','provider.o','-Wl,-soname,libprovider.so','-o','libprovider.so'),('gcc','-fuse-ld=bfd','-shared','override.o','-Wl,-soname,liboverride.so','-o','liboverride.so'),('gcc','-fuse-ld=bfd','-shared','oracle.o','-L.','-Wl,--no-as-needed','-lprovider','-Wl,-rpath,$ORIGIN','-o','liboracle.so')]
try:
 for c in cmds:
  p=run(*c)
  if p.returncode: raise RuntimeError('setup failed '+str(c))
 for name in ('bad.o','bad-data.o'):
  run('readelf','-rW',name);run('gcc','-fuse-ld=bfd','-shared','-Wl,--no-relax',name,'-L.','-Wl,--no-as-needed','-lprovider','-Wl,-rpath,$ORIGIN','-o','lib'+name+'.so')
 for mode,flag in [('pie','-pie'),('nopie','-no-pie')]:
  for variant in ('good','bad'):
   out='test-'+mode+'-'+variant
   p=run('gcc','-fuse-ld=bfd',flag,'-Wl,-z,nocopyreloc','main-'+mode+'.o',variant+'.o','-L.','-Wl,--no-as-needed','-loracle','-loverride','-lprovider','-Wl,-rpath,$ORIGIN','-o',out)
   if p.returncode==0:
    for arg in ('-rW','-dW','-sW','-hW'):run('readelf',arg,out)
    run('objdump','-drwC',out)
    run('./'+out,'200')
    run('./'+out,'200',extra={'LD_PRELOAD':str(D/'liboverride.so')})
 for name in ('provider.o','override.o','oracle.o','good.o','bad.o','bad-data.o','main-pie.o','main-nopie.o','libprovider.so','liboverride.so','liboracle.so'):
  for arg in ('-rW','-sW'):run('readelf',arg,name)
  if name.endswith('.so'):run('readelf','-dW',name)
finally:
 log['hashes']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in D.iterdir() if p.is_file() and p.name!='record.json'}
 (D/'record.json').write_text(json.dumps(log,indent=2)+'\n')
 print('Recorded',len(log['commands']),'commands, affinity',log['affinity'],'vmem',cap,'at',D/'record.json')
 for c in log['commands']:
  if (c['args'][0]=='gcc' and '-o' in c['args'] and ('libbad.o.so' in c['args'] or 'libbad-data.o.so' in c['args'] or any(str(x).startswith('test-') for x in c['args']))) or c['args'][0].startswith('./'):
   print(' '.join(c['args']),'exit',c['exit'], 'stdout:',c['stdout'].strip(), 'stderr:',c['stderr'].strip()[:600])
