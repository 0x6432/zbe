#!/usr/bin/env python3
"""Independent C va_list and hand-laid raw descriptor consumer checks."""
from pathlib import Path
import argparse
import platform
import resource
import subprocess
import tempfile

MASK=(1<<64)-1

def main():
    root=Path(__file__).resolve().parents[1]
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler',type=Path,default=root/'zig-out/bin/zbe-native')
    parser.add_argument('--cc',default='cc')
    options=('fold-integers','reuse-stack-homes','callee-saved-homes')
    for option in options:parser.add_argument('--'+option,action='store_true')
    args=parser.parse_args()
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64'):
        raise SystemExit('vaarg checks require Linux AMD64; no result claimed')
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    flags=['--'+o for o in options if getattr(args,o.replace('-','_'))]
    source=(root/'src/fixtures/vaarg-consumers.ssa').read_text()
    helpers=[];checks=[];declarations=[]
    # Named banks independently spill in both declaration orders. Variable C
    # values are promoted word/long/double, never va_arg(float) or small types.
    for case in range(64):
        gp=['l']*(case%9);fp=['d']*((case*3)%11)
        named=(gp+fp if case%2 else fp+gp)+['w']
        tail=[('w','l','d','l','d')[(case+i)%5] for i in range(3+case%23)]
        params=', '.join(f'{dict(w="uint32_t",l="uint64_t",d="double")[t]} n{i}' for i,t in enumerate(named))
        last=f'n{len(named)-1}'
        helper=f'vaget_case_{case}'
        source+=f'\nexport function l ${helper}(l %list) {{\n@e\n'
        total='0'
        for i,t in enumerate(tail):
            source+=f'%v{i} ={t} vaarg %list\n'
            source+= {'w':f'%x{i} =l extuw %v{i}\n','d':f'%x{i} =l dtoui %v{i}\n','l':f'%x{i} =l copy %v{i}\n'}[t]
            source+=f'%m{i} =l mul %x{i}, {i+1}\n%sum{i} =l add {total}, %m{i}\n';total=f'%sum{i}'
        source+=f'ret {total}\n}}\n'
        declarations.append(f'extern uint64_t {helper}(void *);')
        body=[f'static uint64_t run_case_{case}({params}, ...) {{']
        body += [f'(void)n{i};' for i in range(len(named))]
        body += [f'va_list ap,copy;va_start(ap,{last});va_copy(copy,ap);',f'uint64_t value={helper}(ap);']
        # Host va_arg advances an independent copy; Python provides numerical
        # expectations rather than deriving them from either descriptor cursor.
        for t in tail:body.append(f'(void)va_arg(copy,{dict(w="uint32_t",l="uint64_t",d="double")[t]});')
        body += ['REQUIRE(memcmp(ap,copy,24)==0);va_end(copy);va_end(ap);return value;}']
        helpers.append('\n'.join(body))
        for seed in range(3):
            values=[];expected=0
            for i,t in enumerate(named):values.append('1.0' if t=='d' else ('UINT64_C(99)' if t=='l' else '17U'))
            for i,t in enumerate(tail):
                n=(case*131+seed*73+i*17+1)%1024
                if t=='l':n|=0xa987654300000000
                expected=(expected+n*(i+1))&MASK
                values.append(f'{n}.0' if t=='d' else (f'UINT64_C({n})' if t=='l' else f'{n}U'))
            checks.append(f'REQUIRE(run_case_{case}('+','.join(values)+f')==UINT64_C({expected}));')
    c=r'''#define _GNU_SOURCE
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/mman.h>
#include <unistd.h>
static size_t count;
#define REQUIRE(x) do {if(!(x)){fprintf(stderr,"vaarg check failed line %d\n",__LINE__);exit(1);}++count;}while(0)
_Static_assert(sizeof(va_list)==24,"SysV descriptor required");
struct descriptor {uint32_t gp,fp;void *overflow,*registers;};
_Static_assert(sizeof(struct descriptor)==24,"descriptor width");
_Static_assert(offsetof(struct descriptor,fp)==4 && offsetof(struct descriptor,overflow)==8 && offsetof(struct descriptor,registers)==16,"descriptor fields");
extern uint32_t vaget_word(void *);
extern uint64_t vaget_long(void *),vaget_drop(void *),vaget_nested(void *);
extern float vaget_single(void *);
extern double vaget_double(void *);
extern uint64_t vaget_loop(void *,uint32_t),vaget_recursive(void *,uint32_t);
extern uint32_t vaget_safe(void *,uint32_t);
extern int zbe_check_preserved(void *);
static uint64_t raw_result(unsigned kind,void *p) {
 uint64_t raw=0;
 if(kind==0)raw=vaget_word(p);
 else if(kind==1)raw=vaget_long(p);
 else if(kind==2){float value=vaget_single(p);uint32_t bits;memcpy(&bits,&value,4);raw=bits;}
 else {double value=vaget_double(p);memcpy(&raw,&value,8);}
 return raw;
}
'''+'\n'.join(declarations)+'\n'+'\n'.join(helpers)+r'''
int main(int argc,char **argv) {
 (void)argv;
 if(argc>1 && (uintptr_t)vaget_word<=UINT32_MAX){fputs("PIE high address precondition\n",stderr);return 2;}
'''+ '\n'.join(checks)+r'''
 const uint64_t patterns[]={0,1,UINT64_C(0xffffffffffffffff),UINT64_C(0x8000000080000000),UINT64_C(0x7ff812347fc12345),UINT64_C(0x7ff000017f800001),UINT64_C(0x8000000000000000),UINT64_C(0x0000000080000000)};
 _Alignas(16) unsigned char bank[176],overflow[32];
 const uint32_t gp_offsets[]={0,40,48,0x80000000U,0xffffffffU};
 const uint32_t fp_offsets[]={48,160,176,0x80000000U,0xffffffffU};
 for(unsigned kind=0;kind<4;++kind)for(unsigned index=0;index<5;++index)for(unsigned n=0;n<8;++n){
   memset(bank,0xa5,sizeof bank);memset(overflow,0x5a,sizeof overflow);
   unsigned fp=kind>=2,width=(kind==0 || kind==2)?4:8;
   uint32_t offset=fp?fp_offsets[index]:gp_offsets[index];
   unsigned on_stack=index>=2;
   memcpy(on_stack?overflow:bank+offset,&patterns[n],width);
   struct descriptor d={fp?24:offset,fp?offset:96,overflow,bank};
   unsigned char saved_bank[176],saved_overflow[32];memcpy(saved_bank,bank,176);memcpy(saved_overflow,overflow,32);
   uint64_t expected=width==4?(uint32_t)patterns[n]:patterns[n];
   REQUIRE(raw_result(kind,&d)==expected);
   REQUIRE(d.gp==(fp?24:(on_stack?offset:offset+8)));
   REQUIRE(d.fp==(fp?(on_stack?offset:offset+16):96));
   REQUIRE(d.overflow==overflow+(on_stack?8:0));
   REQUIRE(d.registers==bank);
   REQUIRE(memcmp(bank,saved_bank,176)==0 && memcmp(overflow,saved_overflow,32)==0);
 }
 // Separate GP/SSE fields, descriptor copies and advancement through all banks.
 uint64_t integers[]={11,22,33,44,55,66};
 memset(bank,0,sizeof bank);memcpy(bank,integers,48);
 double floats[]={1.5,2.5,3.5,4.5,5.5,6.5,7.5,8.5};
 for(unsigned i=0;i<8;++i)memcpy(bank+48+i*16,&floats[i],8);
 struct descriptor d={0,48,overflow,bank},copy=d;
 REQUIRE(vaget_word(&d)==11);REQUIRE(vaget_double(&d)==1.5);
 REQUIRE(vaget_long(&copy)==11);REQUIRE(vaget_single(&copy)==0.0f);
 REQUIRE(d.gp==8 && d.fp==64 && copy.gp==8 && copy.fp==64);
 d.gp=0;REQUIRE(vaget_drop(&d)==22);REQUIRE(d.gp==16);
 d.gp=0;REQUIRE(vaget_nested(&d)==33);REQUIRE(d.gp==16);
 d.gp=0;REQUIRE(vaget_loop(&d,6)==231);REQUIRE(d.gp==48);
 d.gp=0;REQUIRE(vaget_recursive(&d,6)==231);REQUIRE(d.gp==48);
 REQUIRE(vaget_safe(NULL,0)==42);
 REQUIRE(zbe_check_preserved((void *)vaget_preserved)==0);
 // Width-specific reads stop at the last valid byte; a wider accidental load
 // would cross the protected page. Neither descriptor nor source is fabricated
 // as a C va_list here: these are explicitly raw native descriptor contracts.
 long page=sysconf(_SC_PAGESIZE);if(page!=4096)return 4;
 unsigned char *map=mmap(NULL,8192,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
 if(map==MAP_FAILED || mprotect(map+4096,4096,PROT_NONE)!=0)return 5;
 for(unsigned kind=0;kind<4;++kind){
   unsigned width=(kind==0 || kind==2)?4:8;
   uint64_t bits=UINT64_C(0x7ff812347fc12345);memcpy(map+4096-width,&bits,width);
   struct descriptor edge={48,176,map+4096-width,NULL};
   REQUIRE(raw_result(kind,&edge)==(width==4?(uint32_t)bits:bits));
   REQUIRE(edge.overflow==map+4096-width+8);
 }
 if(munmap(map,8192)!=0)return 6;
 if(count!=1367)return 7;
 printf("%zu native vaarg descriptor checks passed\n",count);return 0;
}
'''
    # Call-free adapter shape matches the existing full-width preservation oracle.
    source+='''
export function l $vaget_preserved() {
@e
%list =l alloc16 64
%fp =l add %list, 4
%overflow =l add %list, 8
%save =l add %list, 16
%payload =l add %list, 32
storew 0, %list
storew 176, %fp
storel %payload, %overflow
storel %payload, %save
storel 72623859790382856, %payload
%x =l vaarg %list
ret %x
}
'''
    c=c.replace('extern int zbe_check_preserved(void *);','extern int zbe_check_preserved(void *);\nextern uint64_t vaget_preserved(void);')
    with tempfile.TemporaryDirectory(prefix='zbe-vaarg-') as directory:
        work=Path(directory);src,asm,driver,binary=[work/n for n in ('input.ssa','output.s','main.c','check')]
        src.write_text(source);driver.write_text(c);compiler=str(args.compiler.resolve())
        subprocess.run([compiler,*flags,str(src),str(asm)],check=True,timeout=120)
        for pie in (False,True):
            mode=['-fPIE','-pie'] if pie else ['-fno-pie','-no-pie']
            subprocess.run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',*mode,str(driver),str(asm),str(root/'src/fixtures/check-preserved.s'),'-o',str(binary)],check=True,timeout=90)
            subprocess.run([str(binary),*(['high-address'] if pie else [])],check=True,timeout=30)
            dynamic=subprocess.run(['readelf','-d',str(binary)],capture_output=True,text=True,check=True,timeout=30).stdout
            if 'TEXTREL' in dynamic:raise SystemExit('vaarg consumers introduced a dynamic text relocation')
        print('2 vaarg executable no-TEXTREL checks passed')
        bad=[
            'function w $f(w %p) {\n@e\n%x =w vaarg %p\nret %x\n}',
            'function w $f(s %p) {\n@e\n%x =w vaarg %p\nret %x\n}',
            'function w $f(d %p) {\n@e\n%x =w vaarg %p\nret %x\n}',
            'function w $f(l %p) {\n@e\n%x =w vaarg\nret %x\n}',
            'function w $f(l %p) {\n@e\n%x =w vaarg %p, %p\nret %x\n}',
            'function w $f(l %p) {\n@e\n%x =sb vaarg %p\nret %x\n}',
            'function $f(l %p) {\n@e\nvaarg %p\nret\n}',
            'function $f(l %p) {\n@e\nvastart %p\nret\n}',
            'function $f(...) {\n@e\nret\n}',
            'function w $f() {\n@e\n%x =w vaarg %p\n%p =l copy 0\nret %x\n}',
        ]
        for text in bad:
            src.write_text(text)
            if asm.exists():asm.unlink()
            for exists in (False,True):
                if exists:asm.write_text('preserve-vaarg-output')
                result=subprocess.run([compiler,*flags,str(src),str(asm)],capture_output=True,timeout=30)
                if result.returncode==0:raise SystemExit('Invalid/unsupported vaarg consumer accepted')
                if (exists and asm.read_text()!='preserve-vaarg-output') or (not exists and asm.exists()):raise SystemExit('Rejected vaarg changed output')
        print('20 vaarg rejection/output-preservation checks passed')

if __name__=='__main__':main()
