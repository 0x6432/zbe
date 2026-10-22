#define _GNU_SOURCE
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdarg.h>
typedef struct __attribute__((packed)) { unsigned char b; uint16_t h; } C_B3;
extern C_B3 opaque_B3_id(C_B3,uint64_t,double), opaque_B3_private(C_B3,uint64_t,double);
typedef struct __attribute__((packed)) { unsigned char b; double d; } C_B9;
extern C_B9 opaque_B9_id(C_B9,uint64_t,double), opaque_B9_private(C_B9,uint64_t,double);
typedef struct __attribute__((packed,aligned(8))) { unsigned char b; uint32_t w; } C_A8;
extern C_A8 opaque_A8_id(C_A8,uint64_t,double), opaque_A8_private(C_A8,uint64_t,double);
typedef struct { unsigned char b[17]; } C_B17;
extern C_B17 opaque_B17_id(C_B17,uint64_t,double), opaque_B17_private(C_B17,uint64_t,double);
static unsigned checks;
#define REQUIRE(x) do { ++checks; if (!(x)) { fprintf(stderr,"opaque check %u line %d failed\n",checks,__LINE__);abort();} } while(0)
const unsigned char *opaque_source;
void opaque_scalars(uint64_t n, double d) { REQUIRE(n==77); REQUIRE(d==1.0); }
extern void *opaque_forward(void*,void*,const void*,void*,uint64_t);
static void fill(unsigned char *p,size_t n){for(size_t i=0;i<n;i++)p[i]=(unsigned char)(i*29+7);}

extern void *opaque_B1_invoke(void*,void*,const void*);
extern void opaque_B1_id(void);
extern void opaque_B1_private(void);
extern void opaque_B1_knownenv(void);
extern void opaque_B1_known(void);
extern void opaque_B1_direct(void);
extern void opaque_B1_indirect(void);
extern void opaque_B1_var(void);
extern void opaque_B1_dynamic(void);
extern void opaque_B1_loop(void);
extern void opaque_B1_recurse(void);
extern void opaque_B1_asm(void);
extern void opaque_B1_env(void);
extern void opaque_B1_al(void);
extern void *opaque_A1_invoke(void*,void*,const void*);
extern void opaque_A1_id(void);
extern void opaque_A1_private(void);
extern void opaque_A1_knownenv(void);
extern void opaque_A1_known(void);
extern void opaque_A1_direct(void);
extern void opaque_A1_indirect(void);
extern void opaque_A1_var(void);
extern void opaque_A1_dynamic(void);
extern void opaque_A1_loop(void);
extern void opaque_A1_recurse(void);
extern void opaque_A1_asm(void);
extern void opaque_A1_env(void);
extern void opaque_A1_al(void);
extern void *opaque_B3_invoke(void*,void*,const void*);
extern void opaque_B3_knownenv(void);
extern void opaque_B3_known(void);
extern void opaque_B3_direct(void);
extern void opaque_B3_indirect(void);
extern void opaque_B3_var(void);
extern void opaque_B3_dynamic(void);
extern void opaque_B3_loop(void);
extern void opaque_B3_recurse(void);
extern void opaque_B3_asm(void);
extern void opaque_B3_env(void);
extern void opaque_B3_al(void);
extern void *opaque_A8_invoke(void*,void*,const void*);
extern void opaque_A8_knownenv(void);
extern void opaque_A8_known(void);
extern void opaque_A8_direct(void);
extern void opaque_A8_indirect(void);
extern void opaque_A8_var(void);
extern void opaque_A8_dynamic(void);
extern void opaque_A8_loop(void);
extern void opaque_A8_recurse(void);
extern void opaque_A8_asm(void);
extern void opaque_A8_env(void);
extern void opaque_A8_al(void);
extern void *opaque_B9_invoke(void*,void*,const void*);
extern void opaque_B9_knownenv(void);
extern void opaque_B9_known(void);
extern void opaque_B9_direct(void);
extern void opaque_B9_indirect(void);
extern void opaque_B9_var(void);
extern void opaque_B9_dynamic(void);
extern void opaque_B9_loop(void);
extern void opaque_B9_recurse(void);
extern void opaque_B9_asm(void);
extern void opaque_B9_env(void);
extern void opaque_B9_al(void);
extern void *opaque_A13_invoke(void*,void*,const void*);
extern void opaque_A13_id(void);
extern void opaque_A13_private(void);
extern void opaque_A13_knownenv(void);
extern void opaque_A13_known(void);
extern void opaque_A13_direct(void);
extern void opaque_A13_indirect(void);
extern void opaque_A13_var(void);
extern void opaque_A13_dynamic(void);
extern void opaque_A13_loop(void);
extern void opaque_A13_recurse(void);
extern void opaque_A13_asm(void);
extern void opaque_A13_env(void);
extern void opaque_A13_al(void);
extern void *opaque_A16_invoke(void*,void*,const void*);
extern void opaque_A16_id(void);
extern void opaque_A16_private(void);
extern void opaque_A16_knownenv(void);
extern void opaque_A16_known(void);
extern void opaque_A16_direct(void);
extern void opaque_A16_indirect(void);
extern void opaque_A16_var(void);
extern void opaque_A16_dynamic(void);
extern void opaque_A16_loop(void);
extern void opaque_A16_recurse(void);
extern void opaque_A16_asm(void);
extern void opaque_A16_env(void);
extern void opaque_A16_al(void);
extern void *opaque_B17_invoke(void*,void*,const void*);
extern void opaque_B17_knownenv(void);
extern void opaque_B17_known(void);
extern void opaque_B17_direct(void);
extern void opaque_B17_indirect(void);
extern void opaque_B17_var(void);
extern void opaque_B17_dynamic(void);
extern void opaque_B17_loop(void);
extern void opaque_B17_recurse(void);
extern void opaque_B17_asm(void);
extern void opaque_B17_env(void);
extern void opaque_B17_al(void);
extern void *opaque_A17_invoke(void*,void*,const void*);
extern void opaque_A17_id(void);
extern void opaque_A17_private(void);
extern void opaque_A17_knownenv(void);
extern void opaque_A17_known(void);
extern void opaque_A17_direct(void);
extern void opaque_A17_indirect(void);
extern void opaque_A17_var(void);
extern void opaque_A17_dynamic(void);
extern void opaque_A17_loop(void);
extern void opaque_A17_recurse(void);
extern void opaque_A17_asm(void);
extern void opaque_A17_env(void);
extern void opaque_A17_al(void);
extern void *opaque_A32_invoke(void*,void*,const void*);
extern void opaque_A32_id(void);
extern void opaque_A32_private(void);
extern void opaque_A32_knownenv(void);
extern void opaque_A32_known(void);
extern void opaque_A32_direct(void);
extern void opaque_A32_indirect(void);
extern void opaque_A32_var(void);
extern void opaque_A32_dynamic(void);
extern void opaque_A32_loop(void);
extern void opaque_A32_recurse(void);
extern void opaque_A32_asm(void);
extern void opaque_A32_env(void);
extern void opaque_A32_al(void);
extern void *opaque_A4096_invoke(void*,void*,const void*);
extern void opaque_A4096_id(void);
extern void opaque_A4096_private(void);
extern void opaque_A4096_knownenv(void);
extern void opaque_A4096_known(void);
extern void opaque_A4096_direct(void);
extern void opaque_A4096_indirect(void);
extern void opaque_A4096_var(void);
extern void opaque_A4096_dynamic(void);
extern void opaque_A4096_loop(void);
extern void opaque_A4096_recurse(void);
extern void opaque_A4096_asm(void);
extern void opaque_A4096_env(void);
extern void opaque_A4096_al(void);
void opaque_dynamic_check(unsigned v){REQUIRE(v==33);}
void opaque_clobber(void) { __asm__ volatile("" ::: "rax","rcx","rdx","rsi","rdi","r8","r9","r10","r11","xmm0","xmm1","memory"); }

/* Explicit QBE opaque descriptor consumers, NOT C va_arg on invented C types.
 * The helper advances the SAME live descriptor; no list pointer escapes. */
typedef struct { unsigned gp,fp; unsigned char *overflow,*save; } Descriptor;
_Static_assert(sizeof(Descriptor)==24 && offsetof(Descriptor,save)==16,"AMD64 va_list descriptor");
void opaque_last(uint64_t n){REQUIRE(n==101);}
void opaque_namedA(uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,uint64_t six){REQUIRE(a==1&&b==2&&c==3&&d==4&&e==5&&six==6);}
void opaque_namedB(double a,double b,double c,double d,double e,double f,double g,double h,const void *tag){REQUIRE(a==1&&b==2&&c==3&&d==4&&e==5&&f==6&&g==7&&h==8);REQUIRE(tag==opaque_source);}
void opaque_consumeA(void *raw){
 Descriptor *v=raw; REQUIRE(v->gp==48&&v->fp==48); REQUIRE(((uintptr_t)v->overflow&15)==8);
 REQUIRE(memcmp(v->overflow,opaque_source,13)==0); uint64_t n; double d;
 memcpy(&d,v->save+48,8); REQUIRE(d==1); memcpy(&n,v->overflow+16,8); REQUIRE(n==99);
 REQUIRE(v->overflow[24]==opaque_source[0]); v->overflow+=40; v->fp+=16;
}
void opaque_consumeB(void *raw){
 Descriptor *v=raw; REQUIRE(v->gp==16&&v->fp==176); REQUIRE(((uintptr_t)v->overflow&15)==8);
 double d;uint64_t n;memcpy(&d,v->overflow,8);REQUIRE(d==2);memcpy(&n,v->save+16,8);REQUIRE(n==99);
 REQUIRE(memcmp(v->overflow+8,opaque_source,17)==0);REQUIRE(v->overflow[40]==opaque_source[0]);
 v->overflow+=56;v->gp+=8;
}
extern void opaque_pressureA_driver(void),opaque_pressureA_entry(void),opaque_pressureB_driver(void),opaque_pressureB_entry(void);
_Static_assert(sizeof(C_B3)==3 && _Alignof(C_B3)==1 && offsetof(C_B3,h)==1,"real C MEMORY B3");
C_B3 opaque_B3_c_read(C_B3 p,uint64_t tag,...){va_list ap;va_start(ap,tag);C_B3 v=va_arg(ap,C_B3);uint64_t n=va_arg(ap,uint64_t);double d=va_arg(ap,double);va_end(ap);REQUIRE(tag==77&&n==99&&d==1);REQUIRE(memcmp(&p,&v,3)==0);return v;}
void opaque_B3_c_consume(void *raw){va_list *ap=raw;C_B3 v=va_arg(*ap,C_B3);uint64_t n=va_arg(*ap,uint64_t);double d=va_arg(*ap,double);REQUIRE(n==99&&d==1);REQUIRE(memcmp(&v,opaque_source,3)==0);}
extern C_B3 opaque_B3_c_definition(C_B3,uint64_t,...); extern void opaque_B3_c_driver(void);
_Static_assert(sizeof(C_B9)==9 && _Alignof(C_B9)==1 && offsetof(C_B9,d)==1,"real C MEMORY B9");
C_B9 opaque_B9_c_read(C_B9 p,uint64_t tag,...){va_list ap;va_start(ap,tag);C_B9 v=va_arg(ap,C_B9);uint64_t n=va_arg(ap,uint64_t);double d=va_arg(ap,double);va_end(ap);REQUIRE(tag==77&&n==99&&d==1);REQUIRE(memcmp(&p,&v,9)==0);return v;}
void opaque_B9_c_consume(void *raw){va_list *ap=raw;C_B9 v=va_arg(*ap,C_B9);uint64_t n=va_arg(*ap,uint64_t);double d=va_arg(*ap,double);REQUIRE(n==99&&d==1);REQUIRE(memcmp(&v,opaque_source,9)==0);}
extern C_B9 opaque_B9_c_definition(C_B9,uint64_t,...); extern void opaque_B9_c_driver(void);
/* C A8 has3 padding bytes: C results compare only occupied bytes0..4.
 * Independent opaque ASM probes still require all8 declared bytes exactly. */
_Static_assert(sizeof(C_A8)==8 && _Alignof(C_A8)==8 && offsetof(C_A8,w)==1,"real C MEMORY A8");
C_A8 opaque_A8_c_read(C_A8 p,uint64_t tag,...){va_list ap;va_start(ap,tag);C_A8 v=va_arg(ap,C_A8);uint64_t n=va_arg(ap,uint64_t);double d=va_arg(ap,double);va_end(ap);REQUIRE(tag==77&&n==99&&d==1);REQUIRE(memcmp(&p,&v,5)==0);return v;}
void opaque_A8_c_consume(void *raw){va_list *ap=raw;C_A8 v=va_arg(*ap,C_A8);uint64_t n=va_arg(*ap,uint64_t);double d=va_arg(*ap,double);REQUIRE(n==99&&d==1);REQUIRE(memcmp(&v,opaque_source,5)==0);}
extern C_A8 opaque_A8_c_definition(C_A8,uint64_t,...); extern void opaque_A8_c_driver(void);
_Static_assert(sizeof(C_B17)==17 && _Alignof(C_B17)==1 && offsetof(C_B17,b)==0,"real C MEMORY B17");
C_B17 opaque_B17_c_read(C_B17 p,uint64_t tag,...){va_list ap;va_start(ap,tag);C_B17 v=va_arg(ap,C_B17);uint64_t n=va_arg(ap,uint64_t);double d=va_arg(ap,double);va_end(ap);REQUIRE(tag==77&&n==99&&d==1);REQUIRE(memcmp(&p,&v,17)==0);return v;}
void opaque_B17_c_consume(void *raw){va_list *ap=raw;C_B17 v=va_arg(*ap,C_B17);uint64_t n=va_arg(*ap,uint64_t);double d=va_arg(*ap,double);REQUIRE(n==99&&d==1);REQUIRE(memcmp(&v,opaque_source,17)==0);}
extern C_B17 opaque_B17_c_definition(C_B17,uint64_t,...); extern void opaque_B17_c_driver(void);
typedef struct { unsigned char b[32]; } C32;
extern C32 opaque_nestedR(C32),opaque_nestedU(C32);
void opaque_env_check(uint64_t e){REQUIRE(e==2748);}
extern uint64_t opaque_scalar_var(const void*,...);
static void more_checks(void){
 _Alignas(16) unsigned char src[64],out[64];fill(src,64);memset(out,0xa5,64);opaque_source=src;
 REQUIRE(opaque_forward((void*)opaque_pressureA_driver,out,src,(void*)opaque_pressureA_entry,0)==out);REQUIRE(out[0]==src[0]);
 REQUIRE(opaque_forward((void*)opaque_pressureB_driver,out,src,(void*)opaque_pressureB_entry,0)==out);REQUIRE(memcmp(out,src,13)==0);
 REQUIRE(opaque_scalar_var(src,UINT64_C(77),1.0)==src[0]);
 C32 v;memcpy(&v,src,32);C32 r=opaque_nestedR(v);REQUIRE(memcmp(&r,&v,32)==0);r=opaque_nestedU(v);REQUIRE(memcmp(&r,&v,32)==0);
 { C_B3 v;memcpy(&v,src,3);C_B3 r=opaque_B3_id(v,77,1.0);REQUIRE(memcmp(&r,&v,3)==0);
 r=opaque_B3_private(v,77,1.0);REQUIRE(((unsigned char*)&r)[0]==123);REQUIRE(memcmp(&v,src,3)==0);
 REQUIRE(opaque_forward((void*)opaque_B3_c_driver,out,src,0,0)==out);REQUIRE(memcmp(out,src,3)==0);
 r=opaque_B3_c_definition(v,77,v,UINT64_C(99),1.0,UINT64_C(101));REQUIRE(memcmp(&r,&v,3)==0); }
 { C_B9 v;memcpy(&v,src,9);C_B9 r=opaque_B9_id(v,77,1.0);REQUIRE(memcmp(&r,&v,9)==0);
 r=opaque_B9_private(v,77,1.0);REQUIRE(((unsigned char*)&r)[0]==123);REQUIRE(memcmp(&v,src,9)==0);
 REQUIRE(opaque_forward((void*)opaque_B9_c_driver,out,src,0,0)==out);REQUIRE(memcmp(out,src,9)==0);
 r=opaque_B9_c_definition(v,77,v,UINT64_C(99),1.0,UINT64_C(101));REQUIRE(memcmp(&r,&v,9)==0); }
 { C_A8 v;memcpy(&v,src,8);C_A8 r=opaque_A8_id(v,77,1.0);REQUIRE(memcmp(&r,&v,5)==0);
 r=opaque_A8_private(v,77,1.0);REQUIRE(((unsigned char*)&r)[0]==123);REQUIRE(memcmp(&v,src,8)==0);
 REQUIRE(opaque_forward((void*)opaque_A8_c_driver,out,src,0,0)==out);REQUIRE(memcmp(out,src,5)==0);
 r=opaque_A8_c_definition(v,77,v,UINT64_C(99),1.0,UINT64_C(101));REQUIRE(memcmp(&r,&v,5)==0); }
 { C_B17 v;memcpy(&v,src,17);C_B17 r=opaque_B17_id(v,77,1.0);REQUIRE(memcmp(&r,&v,17)==0);
 r=opaque_B17_private(v,77,1.0);REQUIRE(((unsigned char*)&r)[0]==123);REQUIRE(memcmp(&v,src,17)==0);
 REQUIRE(opaque_forward((void*)opaque_B17_c_driver,out,src,0,0)==out);REQUIRE(memcmp(out,src,17)==0);
 r=opaque_B17_c_definition(v,77,v,UINT64_C(99),1.0,UINT64_C(101));REQUIRE(memcmp(&r,&v,17)==0); }
}
int main(void){
more_checks();
{
enum {N=1, A=1};
size_t page=(size_t)sysconf(_SC_PAGESIZE);
unsigned char *map=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(map!=MAP_FAILED); REQUIRE(mprotect(map+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *src = map+2*page-N;
fill(src,N); unsigned char expected[N]; memcpy(expected,src,N); opaque_source=src; REQUIRE(mprotect(map+page,page,PROT_READ)==0);
unsigned char *destmap=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(destmap!=MAP_FAILED); REQUIRE(mprotect(destmap+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *out=destmap+2*page-N;
memset(destmap+page,0xa5,page);
REQUIRE(opaque_B1_invoke((void*)opaque_B1_id,out,src)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_B1_invoke((void*)opaque_B1_private,out,src)==out); REQUIRE(out[0]==123); REQUIRE(memcmp(src,expected,N)==0); memcpy(out,expected,N);
REQUIRE(opaque_forward((void*)opaque_B1_knownenv,out,src,0,2748)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B1_known,out,src,(void*)opaque_B1_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B1_direct,out,src,(void*)opaque_B1_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B1_indirect,out,src,(void*)opaque_B1_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B1_var,out,src,(void*)opaque_B1_al,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B1_dynamic,out,src,(void*)opaque_B1_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B1_loop,out,src,(void*)opaque_B1_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B1_recurse,out,src,(void*)opaque_B1_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
for(unsigned char *p=destmap+page;p<out;p++) { REQUIRE(*p==0xa5); }
for(unsigned char *p=out+N;p<destmap+2*page;p++) { REQUIRE(*p==0xa5); }
REQUIRE(munmap(map,3*page)==0); REQUIRE(munmap(destmap,3*page)==0);
}
{
enum {N=1, A=16};
size_t page=(size_t)sysconf(_SC_PAGESIZE);
unsigned char *map=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(map!=MAP_FAILED); REQUIRE(mprotect(map+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *src = map+page+64;
fill(src,N); unsigned char expected[N]; memcpy(expected,src,N); opaque_source=src; REQUIRE(mprotect(map+page,page,PROT_READ)==0);
unsigned char *destmap=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(destmap!=MAP_FAILED); REQUIRE(mprotect(destmap+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *out=destmap+page+64;
memset(destmap+page,0xa5,page);
REQUIRE(opaque_A1_invoke((void*)opaque_A1_id,out,src)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_A1_invoke((void*)opaque_A1_private,out,src)==out); REQUIRE(out[0]==123); REQUIRE(memcmp(src,expected,N)==0); memcpy(out,expected,N);
REQUIRE(opaque_forward((void*)opaque_A1_knownenv,out,src,0,2748)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A1_known,out,src,(void*)opaque_A1_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A1_direct,out,src,(void*)opaque_A1_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A1_indirect,out,src,(void*)opaque_A1_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A1_var,out,src,(void*)opaque_A1_al,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A1_dynamic,out,src,(void*)opaque_A1_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A1_loop,out,src,(void*)opaque_A1_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A1_recurse,out,src,(void*)opaque_A1_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
for(unsigned char *p=destmap+page;p<out;p++) { REQUIRE(*p==0xa5); }
for(unsigned char *p=out+N;p<destmap+2*page;p++) { REQUIRE(*p==0xa5); }
REQUIRE(munmap(map,3*page)==0); REQUIRE(munmap(destmap,3*page)==0);
}
{
enum {N=3, A=1};
size_t page=(size_t)sysconf(_SC_PAGESIZE);
unsigned char *map=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(map!=MAP_FAILED); REQUIRE(mprotect(map+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *src = map+2*page-N;
fill(src,N); unsigned char expected[N]; memcpy(expected,src,N); opaque_source=src; REQUIRE(mprotect(map+page,page,PROT_READ)==0);
unsigned char *destmap=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(destmap!=MAP_FAILED); REQUIRE(mprotect(destmap+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *out=destmap+2*page-N;
memset(destmap+page,0xa5,page);
REQUIRE(opaque_B3_invoke((void*)opaque_B3_id,out,src)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_B3_invoke((void*)opaque_B3_private,out,src)==out); REQUIRE(out[0]==123); REQUIRE(memcmp(src,expected,N)==0); memcpy(out,expected,N);
REQUIRE(opaque_forward((void*)opaque_B3_knownenv,out,src,0,2748)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B3_known,out,src,(void*)opaque_B3_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B3_direct,out,src,(void*)opaque_B3_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B3_indirect,out,src,(void*)opaque_B3_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B3_var,out,src,(void*)opaque_B3_al,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B3_dynamic,out,src,(void*)opaque_B3_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B3_loop,out,src,(void*)opaque_B3_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B3_recurse,out,src,(void*)opaque_B3_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
for(unsigned char *p=destmap+page;p<out;p++) { REQUIRE(*p==0xa5); }
for(unsigned char *p=out+N;p<destmap+2*page;p++) { REQUIRE(*p==0xa5); }
REQUIRE(munmap(map,3*page)==0); REQUIRE(munmap(destmap,3*page)==0);
}
{
enum {N=8, A=8};
size_t page=(size_t)sysconf(_SC_PAGESIZE);
unsigned char *map=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(map!=MAP_FAILED); REQUIRE(mprotect(map+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *src = map+2*page-N;
fill(src,N); unsigned char expected[N]; memcpy(expected,src,N); opaque_source=src; REQUIRE(mprotect(map+page,page,PROT_READ)==0);
unsigned char *destmap=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(destmap!=MAP_FAILED); REQUIRE(mprotect(destmap+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *out=destmap+2*page-N;
memset(destmap+page,0xa5,page);
REQUIRE(opaque_A8_invoke((void*)opaque_A8_id,out,src)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_A8_invoke((void*)opaque_A8_private,out,src)==out); REQUIRE(out[0]==123); REQUIRE(memcmp(src,expected,N)==0); memcpy(out,expected,N);
REQUIRE(opaque_forward((void*)opaque_A8_knownenv,out,src,0,2748)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A8_known,out,src,(void*)opaque_A8_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A8_direct,out,src,(void*)opaque_A8_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A8_indirect,out,src,(void*)opaque_A8_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A8_var,out,src,(void*)opaque_A8_al,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A8_dynamic,out,src,(void*)opaque_A8_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A8_loop,out,src,(void*)opaque_A8_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A8_recurse,out,src,(void*)opaque_A8_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
for(unsigned char *p=destmap+page;p<out;p++) { REQUIRE(*p==0xa5); }
for(unsigned char *p=out+N;p<destmap+2*page;p++) { REQUIRE(*p==0xa5); }
REQUIRE(munmap(map,3*page)==0); REQUIRE(munmap(destmap,3*page)==0);
}
{
enum {N=9, A=1};
size_t page=(size_t)sysconf(_SC_PAGESIZE);
unsigned char *map=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(map!=MAP_FAILED); REQUIRE(mprotect(map+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *src = map+2*page-N;
fill(src,N); unsigned char expected[N]; memcpy(expected,src,N); opaque_source=src; REQUIRE(mprotect(map+page,page,PROT_READ)==0);
unsigned char *destmap=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(destmap!=MAP_FAILED); REQUIRE(mprotect(destmap+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *out=destmap+2*page-N;
memset(destmap+page,0xa5,page);
REQUIRE(opaque_B9_invoke((void*)opaque_B9_id,out,src)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_B9_invoke((void*)opaque_B9_private,out,src)==out); REQUIRE(out[0]==123); REQUIRE(memcmp(src,expected,N)==0); memcpy(out,expected,N);
REQUIRE(opaque_forward((void*)opaque_B9_knownenv,out,src,0,2748)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B9_known,out,src,(void*)opaque_B9_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B9_direct,out,src,(void*)opaque_B9_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B9_indirect,out,src,(void*)opaque_B9_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B9_var,out,src,(void*)opaque_B9_al,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B9_dynamic,out,src,(void*)opaque_B9_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B9_loop,out,src,(void*)opaque_B9_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B9_recurse,out,src,(void*)opaque_B9_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
for(unsigned char *p=destmap+page;p<out;p++) { REQUIRE(*p==0xa5); }
for(unsigned char *p=out+N;p<destmap+2*page;p++) { REQUIRE(*p==0xa5); }
REQUIRE(munmap(map,3*page)==0); REQUIRE(munmap(destmap,3*page)==0);
}
{
enum {N=13, A=8};
size_t page=(size_t)sysconf(_SC_PAGESIZE);
unsigned char *map=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(map!=MAP_FAILED); REQUIRE(mprotect(map+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *src = map+page+64;
fill(src,N); unsigned char expected[N]; memcpy(expected,src,N); opaque_source=src; REQUIRE(mprotect(map+page,page,PROT_READ)==0);
unsigned char *destmap=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(destmap!=MAP_FAILED); REQUIRE(mprotect(destmap+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *out=destmap+page+64;
memset(destmap+page,0xa5,page);
REQUIRE(opaque_A13_invoke((void*)opaque_A13_id,out,src)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_A13_invoke((void*)opaque_A13_private,out,src)==out); REQUIRE(out[0]==123); REQUIRE(memcmp(src,expected,N)==0); memcpy(out,expected,N);
REQUIRE(opaque_forward((void*)opaque_A13_knownenv,out,src,0,2748)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A13_known,out,src,(void*)opaque_A13_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A13_direct,out,src,(void*)opaque_A13_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A13_indirect,out,src,(void*)opaque_A13_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A13_var,out,src,(void*)opaque_A13_al,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A13_dynamic,out,src,(void*)opaque_A13_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A13_loop,out,src,(void*)opaque_A13_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A13_recurse,out,src,(void*)opaque_A13_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
for(unsigned char *p=destmap+page;p<out;p++) { REQUIRE(*p==0xa5); }
for(unsigned char *p=out+N;p<destmap+2*page;p++) { REQUIRE(*p==0xa5); }
REQUIRE(munmap(map,3*page)==0); REQUIRE(munmap(destmap,3*page)==0);
}
{
enum {N=16, A=16};
size_t page=(size_t)sysconf(_SC_PAGESIZE);
unsigned char *map=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(map!=MAP_FAILED); REQUIRE(mprotect(map+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *src = map+2*page-N;
fill(src,N); unsigned char expected[N]; memcpy(expected,src,N); opaque_source=src; REQUIRE(mprotect(map+page,page,PROT_READ)==0);
unsigned char *destmap=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(destmap!=MAP_FAILED); REQUIRE(mprotect(destmap+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *out=destmap+2*page-N;
memset(destmap+page,0xa5,page);
REQUIRE(opaque_A16_invoke((void*)opaque_A16_id,out,src)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_A16_invoke((void*)opaque_A16_private,out,src)==out); REQUIRE(out[0]==123); REQUIRE(memcmp(src,expected,N)==0); memcpy(out,expected,N);
REQUIRE(opaque_forward((void*)opaque_A16_knownenv,out,src,0,2748)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A16_known,out,src,(void*)opaque_A16_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A16_direct,out,src,(void*)opaque_A16_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A16_indirect,out,src,(void*)opaque_A16_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A16_var,out,src,(void*)opaque_A16_al,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A16_dynamic,out,src,(void*)opaque_A16_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A16_loop,out,src,(void*)opaque_A16_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A16_recurse,out,src,(void*)opaque_A16_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
for(unsigned char *p=destmap+page;p<out;p++) { REQUIRE(*p==0xa5); }
for(unsigned char *p=out+N;p<destmap+2*page;p++) { REQUIRE(*p==0xa5); }
REQUIRE(munmap(map,3*page)==0); REQUIRE(munmap(destmap,3*page)==0);
}
{
enum {N=17, A=1};
size_t page=(size_t)sysconf(_SC_PAGESIZE);
unsigned char *map=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(map!=MAP_FAILED); REQUIRE(mprotect(map+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *src = map+2*page-N;
fill(src,N); unsigned char expected[N]; memcpy(expected,src,N); opaque_source=src; REQUIRE(mprotect(map+page,page,PROT_READ)==0);
unsigned char *destmap=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(destmap!=MAP_FAILED); REQUIRE(mprotect(destmap+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *out=destmap+2*page-N;
memset(destmap+page,0xa5,page);
REQUIRE(opaque_B17_invoke((void*)opaque_B17_id,out,src)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_B17_invoke((void*)opaque_B17_private,out,src)==out); REQUIRE(out[0]==123); REQUIRE(memcmp(src,expected,N)==0); memcpy(out,expected,N);
REQUIRE(opaque_forward((void*)opaque_B17_knownenv,out,src,0,2748)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B17_known,out,src,(void*)opaque_B17_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B17_direct,out,src,(void*)opaque_B17_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B17_indirect,out,src,(void*)opaque_B17_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B17_var,out,src,(void*)opaque_B17_al,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B17_dynamic,out,src,(void*)opaque_B17_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B17_loop,out,src,(void*)opaque_B17_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_B17_recurse,out,src,(void*)opaque_B17_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
for(unsigned char *p=destmap+page;p<out;p++) { REQUIRE(*p==0xa5); }
for(unsigned char *p=out+N;p<destmap+2*page;p++) { REQUIRE(*p==0xa5); }
REQUIRE(munmap(map,3*page)==0); REQUIRE(munmap(destmap,3*page)==0);
}
{
enum {N=17, A=16};
size_t page=(size_t)sysconf(_SC_PAGESIZE);
unsigned char *map=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(map!=MAP_FAILED); REQUIRE(mprotect(map+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *src = map+page+64;
fill(src,N); unsigned char expected[N]; memcpy(expected,src,N); opaque_source=src; REQUIRE(mprotect(map+page,page,PROT_READ)==0);
unsigned char *destmap=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(destmap!=MAP_FAILED); REQUIRE(mprotect(destmap+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *out=destmap+page+64;
memset(destmap+page,0xa5,page);
REQUIRE(opaque_A17_invoke((void*)opaque_A17_id,out,src)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_A17_invoke((void*)opaque_A17_private,out,src)==out); REQUIRE(out[0]==123); REQUIRE(memcmp(src,expected,N)==0); memcpy(out,expected,N);
REQUIRE(opaque_forward((void*)opaque_A17_knownenv,out,src,0,2748)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A17_known,out,src,(void*)opaque_A17_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A17_direct,out,src,(void*)opaque_A17_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A17_indirect,out,src,(void*)opaque_A17_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A17_var,out,src,(void*)opaque_A17_al,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A17_dynamic,out,src,(void*)opaque_A17_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A17_loop,out,src,(void*)opaque_A17_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A17_recurse,out,src,(void*)opaque_A17_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
for(unsigned char *p=destmap+page;p<out;p++) { REQUIRE(*p==0xa5); }
for(unsigned char *p=out+N;p<destmap+2*page;p++) { REQUIRE(*p==0xa5); }
REQUIRE(munmap(map,3*page)==0); REQUIRE(munmap(destmap,3*page)==0);
}
{
enum {N=32, A=16};
size_t page=(size_t)sysconf(_SC_PAGESIZE);
unsigned char *map=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(map!=MAP_FAILED); REQUIRE(mprotect(map+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *src = map+2*page-N;
fill(src,N); unsigned char expected[N]; memcpy(expected,src,N); opaque_source=src; REQUIRE(mprotect(map+page,page,PROT_READ)==0);
unsigned char *destmap=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(destmap!=MAP_FAILED); REQUIRE(mprotect(destmap+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *out=destmap+2*page-N;
memset(destmap+page,0xa5,page);
REQUIRE(opaque_A32_invoke((void*)opaque_A32_id,out,src)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_A32_invoke((void*)opaque_A32_private,out,src)==out); REQUIRE(out[0]==123); REQUIRE(memcmp(src,expected,N)==0); memcpy(out,expected,N);
REQUIRE(opaque_forward((void*)opaque_A32_knownenv,out,src,0,2748)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A32_known,out,src,(void*)opaque_A32_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A32_direct,out,src,(void*)opaque_A32_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A32_indirect,out,src,(void*)opaque_A32_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A32_var,out,src,(void*)opaque_A32_al,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A32_dynamic,out,src,(void*)opaque_A32_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A32_loop,out,src,(void*)opaque_A32_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A32_recurse,out,src,(void*)opaque_A32_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
for(unsigned char *p=destmap+page;p<out;p++) { REQUIRE(*p==0xa5); }
for(unsigned char *p=out+N;p<destmap+2*page;p++) { REQUIRE(*p==0xa5); }
REQUIRE(munmap(map,3*page)==0); REQUIRE(munmap(destmap,3*page)==0);
}
{
enum {N=4096, A=16};
size_t page=(size_t)sysconf(_SC_PAGESIZE);
unsigned char *map=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(map!=MAP_FAILED); REQUIRE(mprotect(map+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *src = map+2*page-N;
fill(src,N); unsigned char expected[N]; memcpy(expected,src,N); opaque_source=src; REQUIRE(mprotect(map+page,page,PROT_READ)==0);
unsigned char *destmap=mmap(0,3*page,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0); REQUIRE(destmap!=MAP_FAILED); REQUIRE(mprotect(destmap+page,page,PROT_READ|PROT_WRITE)==0);
unsigned char *out=destmap+2*page-N;
memset(destmap+page,0xa5,page);
REQUIRE(opaque_A4096_invoke((void*)opaque_A4096_id,out,src)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_A4096_invoke((void*)opaque_A4096_private,out,src)==out); REQUIRE(out[0]==123); REQUIRE(memcmp(src,expected,N)==0); memcpy(out,expected,N);
REQUIRE(opaque_forward((void*)opaque_A4096_knownenv,out,src,0,2748)==out); REQUIRE(memcmp(out,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A4096_known,out,src,(void*)opaque_A4096_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A4096_direct,out,src,(void*)opaque_A4096_asm,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A4096_indirect,out,src,(void*)opaque_A4096_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A4096_var,out,src,(void*)opaque_A4096_al,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A4096_dynamic,out,src,(void*)opaque_A4096_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A4096_loop,out,src,(void*)opaque_A4096_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
REQUIRE(opaque_forward((void*)opaque_A4096_recurse,out,src,(void*)opaque_A4096_env,2748)==out); REQUIRE(memcmp(out,expected,N)==0); REQUIRE(memcmp(src,expected,N)==0);
for(unsigned char *p=destmap+page;p<out;p++) { REQUIRE(*p==0xa5); }
for(unsigned char *p=out+N;p<destmap+2*page;p++) { REQUIRE(*p==0xa5); }
REQUIRE(munmap(map,3*page)==0); REQUIRE(munmap(destmap,3*page)==0);
}
printf("%u opaque independent ASM exact-byte, occupied-extent and private-copy checks passed\n",checks);return 0;}
