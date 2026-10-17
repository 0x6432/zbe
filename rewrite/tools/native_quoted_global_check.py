#!/usr/bin/env python3
"""Independent decoded ELF-name, relocation and executable quoted-global checks."""
from pathlib import Path
import argparse
import platform
import resource
import struct
import subprocess
import tempfile

NAMES=('space name','1leading','has-dash','has@at','semi;colon','quote"mark','back\\slash','a+b','with,comma','with%percent','with#hash','paren(name)','[bracket]','colon:name','star*name','eq=name','$cash','pipe|name','trap"; .globl quoted_injected; #',' leading ')
NAMES += tuple(chr(i) for i in range(32,127) if i != 46) + ('42','\\tail\\','ends\\\\','double"')
assert len(NAMES)==118 and len(set(NAMES))==118
# Keep the original corpus: the two ELF-@ spellings move to six rejection contexts,
# rather than silently deleting them or treating versioned linker names as literal.
SUPPORTED_NAMES=tuple(n for n in NAMES if '@' not in n)
REJECTED_NAMES=tuple(n for n in NAMES if '@' in n)
assert len(SUPPORTED_NAMES)==116 and REJECTED_NAMES==('has@at','@')

def quoted(name):return '"'+name.replace('\\','\\\\').replace('"','\\"')+'"'
def symbols(path):
    b=path.read_bytes()
    if b[:6]!=b'\x7fELF\x02\x01':raise SystemExit('Expected independent ELF64 little-endian symbol oracle')
    shoff=struct.unpack_from('<Q',b,40)[0];size,n=struct.unpack_from('<HH',b,58)
    sections=[struct.unpack_from('<IIQQQQIIQQ',b,shoff+i*size) for i in range(n)]
    result={}
    for sh in sections:
        if sh[1]!=2:continue
        strings=sections[sh[6]];st=b[strings[4]:strings[4]+strings[5]]
        for at in range(sh[4],sh[4]+sh[5],sh[9]):
            name,info,other,section,value,length=struct.unpack_from('<IBBHQQ',b,at)
            result[st[name:st.index(b'\0',name)].decode('ascii')]=(info,section,value,length)
    return result

def main():
    root=Path(__file__).resolve().parents[1]
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler',type=Path,default=root/'zig-out/bin/zbe-native');p.add_argument('--cc',default='cc')
    options=('fold-integers','reuse-stack-homes','callee-saved-homes')
    for flag in options:p.add_argument('--'+flag,action='store_true')
    args=p.parse_args()
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','amd64'):raise SystemExit('Quoted-global checks require Linux AMD64; no result claimed')
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    flags=['--'+f for f in options if getattr(args,f.replace('-','_'))]
    source=(root/'src/fixtures/quoted-globals.ssa').read_text();assembly=['.text'];declarations=[];checks=[];expected={}
    for i,name in enumerate(NAMES):
        if name in REJECTED_NAMES:continue
        f=name
        d,t,e,x,m=[prefix+name for prefix in ('data ','table ','external ','external data ','middle ')]
        fq,dq,tq,eq,xq,mq=map(quoted,(f,d,t,e,x,m))
        source+=f'\nexport data ${dq} = align 16 {{ l {i+1} {2*i+3} }}\nexport data ${tq} = {{ l ${dq}+8 ${fq} ${xq}+8 ${eq}+9223372036854775807 ${eq}+-9223372036854775808 }}\n'
        source+=f'\nexport function l ${fq}(l %x) {{\n@e\n%r =l add %x, {i+1}\nret %r\n}}\n'
        bodies={
            'direct':f'%r =l call ${fq}(l 7)\nret %r',
            'external':f'%r =l call ${eq}(l 7)\nret %r',
            'indirect':f'%target =l copy ${fq}\n%r =l call %target(l 9)\nret %r',
            'load':f'%r =l loadl ${dq}+8\nret %r',
            'external_load':f'%r =l loadl ${xq}+8\nret %r',
            'negative':f'%r =l loadl ${mq}+-8\nret %r',
        }
        for kind,body in bodies.items():
            caller=f'quoted_{kind}_{i}';source+=f'\nexport function l ${caller}() {{\n@e\n{body}\n}}\n'
            declarations.append(f'extern uint64_t {caller}(void);')
        source+=f'\nexport function l $quoted_table_{i}(l %offset) {{\n@e\n%base =l copy ${tq}\n%address =l add %base, %offset\n%r =l loadl %address\nret %r\n}}\n'
        source+=f'\nexport function l $quoted_phi_{i}(w %take) {{\n@e\njnz %take, @a, @b\n@a\njmp @join\n@b\njmp @join\n@join\n%r =l phi @a ${dq}+8, @b ${dq}\nret %r\n}}\n'
        source+=f'\nexport function $quoted_store_{i}(l %value) {{\n@e\nstorel %value, ${dq}\nret\n}}\n'
        declarations += [f'extern uint64_t quoted_table_{i}(uint64_t),quoted_phi_{i}(uint32_t);',f'extern void quoted_store_{i}(uint64_t);']
        assembly += ['.text',f'.globl {eq}',f'.type {eq}, @function',f'{eq}:','leaq (%rdi,%rdi,2), %rax',f'addq ${i}, %rax','ret',f'.size {eq}, .-{eq}',
            '.data','.balign 16',f'.globl {xq}',f'.type {xq}, @object',f'{xq}:',f'.quad {i+9},{i+10}',f'.size {xq}, .-{xq}',f'.globl {mq}',f'.set {mq},{xq}+8','.text']
        for kind,target in (('data',dq),('function',fq),('external_data',xq),('external_function',eq)):
            oracle=f'quoted_oracle_{kind}_{i}'
            assembly += [f'.set quoted_reference_{kind}_{i},{target}',f'.globl {oracle}',f'{oracle}:',f'leaq quoted_reference_{kind}_{i}(%rip), %rax','ret']
            declarations.append(f'extern uint64_t {oracle}(void);')
        for kind,result in (('direct',i+8),('external',i+21),('indirect',i+10),('load',2*i+3),('external_load',i+10),('negative',i+9)):
            checks.append(f'REQUIRE(quoted_{kind}_{i}()=={result});')
        for offset,result in ((0,f'quoted_oracle_data_{i}()+8'),(8,f'quoted_oracle_function_{i}()'),(16,f'quoted_oracle_external_data_{i}()+8'),(24,f'quoted_oracle_external_function_{i}()+UINT64_C(0x7fffffffffffffff)'),(32,f'quoted_oracle_external_function_{i}()+UINT64_C(0x8000000000000000)')):
            checks.append(f'REQUIRE(quoted_table_{i}({offset})=={result});')
        checks += [f'REQUIRE(quoted_phi_{i}(0)==quoted_oracle_data_{i}());',f'REQUIRE(quoted_phi_{i}(1)==quoted_oracle_data_{i}()+8);',
            f'uint64_t *p{i}=(void *)(uintptr_t)quoted_oracle_data_{i}();REQUIRE(p{i}[0]=={i+1} && p{i}[1]=={2*i+3});',
            f'quoted_store_{i}(UINT64_C(0xdeadbeef00000000)+{i});REQUIRE(p{i}[0]==UINT64_C(0xdeadbeef00000000)+{i} && p{i}[1]=={2*i+3});']
        expected.update({f:(0x12,None),d:(0x11,16),t:(0x11,40),e:(None,None),x:(None,None),m:(None,None)})
    source+='''
export function l $"plaincanonical"() {
@e
ret 17
}
export function l $quoted_canonical_call() {
@e
%r =l call $plaincanonical()
ret %r
}
function l $"variadic;quoted"(w %anchor, ...) {
@e
%list =l alloc16 24
vastart %list
%r =l vaarg %list
ret %r
}
export function l $quoted_variadic_direct() {
@e
%r =l call $"variadic;quoted"(w 0, ..., l 43)
ret %r
}
export function l $quoted_variadic_indirect() {
@e
%target =l copy $"variadic;quoted"
%r =l call %target(w 0, ..., l 43)
ret %r
}
export function l $quoted_escape_call() {
@e
%r =l call $"quote\\"back\\\\name"()
ret %r
}
'''
    declarations += ['extern uint64_t quote_call(void),quote_load(void),quoted_escape_call(void),quoted_canonical_call(void),quoted_variadic_direct(void),quoted_variadic_indirect(void);','extern uint64_t zbe_check_preserved(uint64_t (*)(void));']
    checks += ['REQUIRE(quote_call()==8);','REQUIRE(quote_load()==22);','REQUIRE(quoted_escape_call()==42);','REQUIRE(quoted_canonical_call()==17);','REQUIRE(quoted_variadic_direct()==43);','REQUIRE(quoted_variadic_indirect()==43);',
        'REQUIRE(zbe_check_preserved(quote_call)==0);','REQUIRE(zbe_check_preserved(quoted_escape_call)==0);']
    assert len(checks)==1748,len(checks)
    assembly += ['.section .note.GNU-stack,"",@progbits']
    c='''#include <stdint.h>
#include <stdio.h>
#define REQUIRE(c) do {++count;if(!(c)){fprintf(stderr,"quoted check %zu failed\\n",count);return 1;}}while(0)
'''+ '\n'.join(declarations)+'''
int main(int argc,char **argv) {
(void)argv;
if(argc>1 && (quoted_oracle_function_0()>>32)==0) return 2;
size_t count=0;
'''+ '\n'.join(checks)+'\nprintf("%zu native quoted-global checks passed\\n",count);return 0;\n}\n'
    with tempfile.TemporaryDirectory(prefix='zbe-quoted-') as directory:
        work=Path(directory);src,asm,obj,driver,adapter,binary=[work/n for n in ('input.ssa','output.s','output.o','main.c','oracle.s','check')]
        src.write_text(source);driver.write_text(c);adapter.write_text('\n'.join(assembly)+'\n');compiler=str(args.compiler.resolve())
        subprocess.run([compiler,*flags,str(src),str(asm)],check=True,timeout=120)
        subprocess.run([args.cc,'-c',str(asm),'-o',str(obj)],check=True,timeout=30)
        decoded=symbols(obj)
        for name,(info,length) in expected.items():
            if name not in decoded:raise SystemExit('ELF decoded quoted name mismatch')
            actual=decoded[name]
            if info is not None and (actual[0]!=info or not actual[1] or (length is not None and actual[3]!=length)):raise SystemExit('ELF quoted binding/type/size mismatch')
            if info==0x12 and actual[3]==0:raise SystemExit('Quoted function size is empty')
        if 'quoted_injected' in decoded:raise SystemExit('Quoted name escaped into assembler directive')
        assert len(expected)==696,len(expected)
        print('696 quoted-global ELF symbol identity/metadata checks passed')
        for pie in (False,True):
            mode=['-fPIE','-pie'] if pie else ['-fno-pie','-no-pie']
            subprocess.run([args.cc,'-std=c11','-O2','-Wall','-Wextra','-Werror',*mode,str(driver),str(obj),str(adapter),str(root/'src/fixtures/check-preserved.s'),'-o',str(binary)],check=True,timeout=90)
            subprocess.run([str(binary),*(['high-address'] if pie else [])],check=True,timeout=30)
            if 'TEXTREL' in subprocess.check_output(['readelf','-d',str(binary)],timeout=30).decode():raise SystemExit('Quoted global introduced TEXTREL')
        print('2 quoted-global executable no-TEXTREL checks passed')
        bad=['data $"" = {}','data $"." = {}',r'data $"bad\000name" = {}',r'data $"bad\nname" = {}',r'data $"bad\tname" = {}',r'data $"bad\xffname" = {}',r'data $"bad\qname" = {}','data $".Lzbe@0@b0" = {}',
            'function $""() {\n@e\nret\n}','data $plain = {}\ndata $"plain" = {}',r'data $plain = {} data $"pl\141in" = {}','data $x = { l $"" }']
        for name in REJECTED_NAMES:
            q=quoted(name)
            bad += [f'function ${q}() {{\n@e\nret\n}}',f'data ${q} = {{}}',
                f'function $f() {{\n@e\ncall ${q}()\nret\n}}',
                f'function l $f() {{\n@e\nret ${q}\n}}',f'data $f = {{ l ${q} }}',
                f'function l $f(w %c) {{\n@e\njnz %c, @a, @b\n@a\njmp @j\n@b\njmp @j\n@j\n%r =l phi @a ${q}, @b 0\nret %r\n}}']
        for name in ('name@PLT','name@GOTPCREL','name@GOT','name@TLSGD','name@TPOFF','name@@VER',r'name\x40PLT',r'name\100GOT'):
            bad.append('data $"'+name+'" = {}')
        assert len(bad)==32,len(bad)
        for text in bad:
            src.write_text(text)
            if asm.exists():asm.unlink()
            for exists in (False,True):
                if exists:asm.write_text('preserve-quoted-output')
                result=subprocess.run([compiler,*flags,str(src),str(asm)],capture_output=True,timeout=30)
                if result.returncode==0:raise SystemExit('Invalid quoted global accepted')
                if (exists and asm.read_text()!='preserve-quoted-output') or (not exists and asm.exists()):raise SystemExit('Rejected quoted global changed output')
        print('64 quoted-global rejection/output-preservation checks passed')

if __name__=='__main__':main()
