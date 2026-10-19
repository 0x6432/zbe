#define _GNU_SOURCE
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/mman.h>
#include <unistd.h>
static unsigned checks;
#define REQUIRE(x) do {++checks;if(!(x)){fprintf(stderr,"native MEMORY check %u at line %d failed\n",checks,__LINE__);abort();}}while(0)
static unsigned char pattern(size_t i,size_t n){return (unsigned char)(3+i*17+n);}
extern uintptr_t aggregate_abi_native_guard_return(void*,void*,const void*);
extern uint32_t aggregate_abi_native_env_bridge(const void*);
typedef struct { unsigned char b[17]; } R17;
_Static_assert(sizeof(R17)==17 && _Alignof(R17)==1,"independent R17 layout");
extern R17 aggregate_abi_native_echo17(R17);
extern R17 aggregate_abi_native_ret17(const void*);
extern uint32_t aggregate_abi_native_send17(const void*);
uint32_t aggregate_abi_native_check17(R17 a){ for(size_t i=0;i<17;++i) if(a.b[i]!=pattern(i,17)) return 0;return 1; }
typedef struct { unsigned char b[23]; } R23;
_Static_assert(sizeof(R23)==23 && _Alignof(R23)==1,"independent R23 layout");
extern R23 aggregate_abi_native_echo23(R23);
extern R23 aggregate_abi_native_ret23(const void*);
extern uint32_t aggregate_abi_native_send23(const void*);
uint32_t aggregate_abi_native_check23(R23 a){ for(size_t i=0;i<23;++i) if(a.b[i]!=pattern(i,23)) return 0;return 1; }
typedef struct { unsigned char b[24]; } R24;
_Static_assert(sizeof(R24)==24 && _Alignof(R24)==1,"independent R24 layout");
extern R24 aggregate_abi_native_echo24(R24);
extern R24 aggregate_abi_native_ret24(const void*);
extern uint32_t aggregate_abi_native_send24(const void*);
uint32_t aggregate_abi_native_check24(R24 a){ for(size_t i=0;i<24;++i) if(a.b[i]!=pattern(i,24)) return 0;return 1; }
typedef struct { unsigned char b[31]; } R31;
_Static_assert(sizeof(R31)==31 && _Alignof(R31)==1,"independent R31 layout");
extern R31 aggregate_abi_native_echo31(R31);
extern R31 aggregate_abi_native_ret31(const void*);
extern uint32_t aggregate_abi_native_send31(const void*);
uint32_t aggregate_abi_native_check31(R31 a){ for(size_t i=0;i<31;++i) if(a.b[i]!=pattern(i,31)) return 0;return 1; }
typedef struct { unsigned char b[32]; } R32;
_Static_assert(sizeof(R32)==32 && _Alignof(R32)==1,"independent R32 layout");
extern R32 aggregate_abi_native_echo32(R32);
extern R32 aggregate_abi_native_ret32(const void*);
extern uint32_t aggregate_abi_native_send32(const void*);
uint32_t aggregate_abi_native_check32(R32 a){ for(size_t i=0;i<32;++i) if(a.b[i]!=pattern(i,32)) return 0;return 1; }
typedef struct { unsigned char b[4096]; } R4096;
_Static_assert(sizeof(R4096)==4096 && _Alignof(R4096)==1,"independent R4096 layout");
extern R4096 aggregate_abi_native_echo4096(R4096);
extern R4096 aggregate_abi_native_ret4096(const void*);
extern uint32_t aggregate_abi_native_send4096(const void*);
uint32_t aggregate_abi_native_check4096(R4096 a){ for(size_t i=0;i<4096;++i) if(a.b[i]!=pattern(i,4096)) return 0;return 1; }
typedef struct { _Alignas(16) uint64_t q[3]; } Aligned;
_Static_assert(sizeof(Aligned)==32 && _Alignof(Aligned)==16 && offsetof(Aligned,q)==0,"independent aligned layout");
extern Aligned aggregate_abi_native_aligned(Aligned);
extern uint32_t aggregate_abi_native_mutate(R17,R17),aggregate_abi_native_sendtwice(const void*),aggregate_abi_native_sites(void),aggregate_abi_native_loop(uint32_t);
extern R17 aggregate_abi_native_roundtrip(R17),aggregate_abi_native_recurse(R17,uint32_t),aggregate_abi_native_dynamic(const void*);
extern uint32_t aggregate_abi_native_varcaller(const void*,...);
extern R17 aggregate_abi_native_scalarindirect(R17,uint32_t(*)(uint32_t));
R17 aggregate_abi_native_cecho(R17 a){ a.b[16]^=0x55;return a; }
uint32_t aggregate_abi_native_cmutate(R17 a,R17 b){volatile unsigned char *pa=a.b,*pb=b.b;unsigned before=pb[0];REQUIRE(pa!=pb);pa[0]=91;return pa[0]==91 && pb[0]==before;}
R17 aggregate_abi_native_make(uint32_t value){R17 r;memset(&r,(unsigned char)value,sizeof r);return r;}
static const void* observed;
uint32_t aggregate_abi_native_observe(const void* p,uint32_t i){if(!i)observed=p;return observed==p && *(const unsigned char*)p==(unsigned char)i;}
uint32_t aggregate_abi_native_varcheck(uint32_t n,...){va_list ap;va_start(ap,n);unsigned a=va_arg(ap,unsigned);double d=va_arg(ap,double);va_end(ap);return n==1 && a==9 && d==2.0 ? 1 : 0;}
static uint32_t indirect(uint32_t value){return value+35;}
extern R17 aggregate_abi_native_mix(uint64_t l0,uint64_t l1,uint64_t l2,uint64_t l3,uint64_t l4,uint64_t l5,R17 a,Aligned b,double d0,double d1,double d2,double d3,double d4,double d5,double d6,double d7,double d8);
extern uint32_t aggregate_abi_native_callmix(const void*,const void*),aggregate_abi_native_callprobe(const void*,const void*);
extern uint32_t aggregate_abi_native_manual_caller(void*,const void*,const void*);
uint32_t aggregate_abi_native_scalarcheck(uint64_t l0,uint64_t l1,uint64_t l2,uint64_t l3,uint64_t l4,uint64_t l5,uint32_t x,uint64_t y,double d0,double d1,double d2,double d3,double d4,double d5,double d6,double d7,double d8){return l0==11 && l1==22 && l2==33 && l3==44 && l4==55 && l5==66 && d0==1.0 && d1==2.0 && d2==3.0 && d3==4.0 && d4==5.0 && d5==6.0 && d6==7.0 && d7==8.0 && d8==9.0 && x==20 && y==UINT64_C(0x1122334455667788);}
R17 aggregate_abi_native_cmix(uint64_t l0,uint64_t l1,uint64_t l2,uint64_t l3,uint64_t l4,uint64_t l5,R17 a,Aligned b,double d0,double d1,double d2,double d3,double d4,double d5,double d6,double d7,double d8){ REQUIRE(l0==11 && l1==22 && l2==33 && l3==44 && l4==55 && l5==66 && d0==1.0 && d1==2.0 && d2==3.0 && d3==4.0 && d4==5.0 && d5==6.0 && d6==7.0 && d7==8.0 && d8==9.0); REQUIRE(a.b[0]==20 && b.q[0]==UINT64_C(0x1122334455667788));a.b[0]=233;return a;}
static uint64_t raw(double value){uint64_t result;memcpy(&result,&value,8);return result;}
extern uint32_t aggregate_abi_native_bits(const void*);
extern R17 aggregate_abi_native_bitreceiver(R17,double,double,double,double,double,double,double,double,double);
R17 aggregate_abi_native_cbits(R17 a,double z,double n,double d2,double d3,double d4,double d5,double d6,double d7,double last){
REQUIRE(raw(z)==UINT64_C(0x8000000000000000));REQUIRE(raw(n)==UINT64_C(0x7ff8000000001234));REQUIRE(raw(last)==UINT64_C(0x7ff8000000005678));REQUIRE(d2==3.&&d3==4.&&d4==5.&&d5==6.&&d6==7.&&d7==8.);a.b[0]=235;return a;}
extern R17 aggregate_abi_native_subincoming(int8_t,uint8_t,int16_t,uint16_t,int8_t,uint8_t,R17);
extern uint32_t aggregate_abi_native_suboutgoing(const void*);
uint32_t aggregate_abi_native_normalized(int32_t a,uint32_t b,int32_t c,uint32_t d,int32_t e,uint32_t f){return a==-128 && b==255 && c==-32768 && d==65535 && e==-1 && f==254;}
R17 aggregate_abi_native_csub(int8_t a,uint8_t b,int16_t c,uint16_t d,int8_t e,uint8_t f,R17 p){REQUIRE(a==-128 && b==255 && c==-32768 && d==65535 && e==-1 && f==254);REQUIRE(p.b[0]==20);p.b[0]=237;return p;}
static unsigned char* guarded(size_t n,void** mapping,size_t* total){long pg=sysconf(_SC_PAGESIZE);REQUIRE(pg>0 && n<=(size_t)pg);*total=(size_t)pg*3;void* base=mmap(NULL,*total,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);REQUIRE(base!=MAP_FAILED);REQUIRE(mprotect((char*)base+pg,(size_t)pg,PROT_READ|PROT_WRITE)==0);*mapping=base;return (unsigned char*)base+2*pg-n;}
int main(void){
{R17 a;for(size_t i=0;i<17;++i)a.b[i]=pattern(i,17);R17 r=aggregate_abi_native_echo17(a);REQUIRE(memcmp(&r,&a,sizeof a)==0);
void *sm,*dm;size_t sl,dl;unsigned char* src=guarded(17,&sm,&sl);unsigned char* dst=guarded(17,&dm,&dl);for(size_t i=0;i<17;++i)src[i]=pattern(i,17);REQUIRE(mprotect((char*)sm+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);memset(dst,0xa5,17);if(17<(size_t)sysconf(_SC_PAGESIZE))dst[-1]=0x6c;
REQUIRE(aggregate_abi_native_send17(src)==1);REQUIRE(aggregate_abi_native_guard_return((void*)aggregate_abi_native_ret17,dst,src)==(uintptr_t)dst);REQUIRE(memcmp(dst,src,17)==0);if(17<(size_t)sysconf(_SC_PAGESIZE))REQUIRE(dst[-1]==0x6c);for(size_t i=0;i<17;++i)REQUIRE(src[i]==pattern(i,17));REQUIRE(munmap(sm,sl)==0);REQUIRE(munmap(dm,dl)==0);}
{R23 a;for(size_t i=0;i<23;++i)a.b[i]=pattern(i,23);R23 r=aggregate_abi_native_echo23(a);REQUIRE(memcmp(&r,&a,sizeof a)==0);
void *sm,*dm;size_t sl,dl;unsigned char* src=guarded(23,&sm,&sl);unsigned char* dst=guarded(23,&dm,&dl);for(size_t i=0;i<23;++i)src[i]=pattern(i,23);REQUIRE(mprotect((char*)sm+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);memset(dst,0xa5,23);if(23<(size_t)sysconf(_SC_PAGESIZE))dst[-1]=0x6c;
REQUIRE(aggregate_abi_native_send23(src)==1);REQUIRE(aggregate_abi_native_guard_return((void*)aggregate_abi_native_ret23,dst,src)==(uintptr_t)dst);REQUIRE(memcmp(dst,src,23)==0);if(23<(size_t)sysconf(_SC_PAGESIZE))REQUIRE(dst[-1]==0x6c);for(size_t i=0;i<23;++i)REQUIRE(src[i]==pattern(i,23));REQUIRE(munmap(sm,sl)==0);REQUIRE(munmap(dm,dl)==0);}
{R24 a;for(size_t i=0;i<24;++i)a.b[i]=pattern(i,24);R24 r=aggregate_abi_native_echo24(a);REQUIRE(memcmp(&r,&a,sizeof a)==0);
void *sm,*dm;size_t sl,dl;unsigned char* src=guarded(24,&sm,&sl);unsigned char* dst=guarded(24,&dm,&dl);for(size_t i=0;i<24;++i)src[i]=pattern(i,24);REQUIRE(mprotect((char*)sm+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);memset(dst,0xa5,24);if(24<(size_t)sysconf(_SC_PAGESIZE))dst[-1]=0x6c;
REQUIRE(aggregate_abi_native_send24(src)==1);REQUIRE(aggregate_abi_native_guard_return((void*)aggregate_abi_native_ret24,dst,src)==(uintptr_t)dst);REQUIRE(memcmp(dst,src,24)==0);if(24<(size_t)sysconf(_SC_PAGESIZE))REQUIRE(dst[-1]==0x6c);for(size_t i=0;i<24;++i)REQUIRE(src[i]==pattern(i,24));REQUIRE(munmap(sm,sl)==0);REQUIRE(munmap(dm,dl)==0);}
{R31 a;for(size_t i=0;i<31;++i)a.b[i]=pattern(i,31);R31 r=aggregate_abi_native_echo31(a);REQUIRE(memcmp(&r,&a,sizeof a)==0);
void *sm,*dm;size_t sl,dl;unsigned char* src=guarded(31,&sm,&sl);unsigned char* dst=guarded(31,&dm,&dl);for(size_t i=0;i<31;++i)src[i]=pattern(i,31);REQUIRE(mprotect((char*)sm+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);memset(dst,0xa5,31);if(31<(size_t)sysconf(_SC_PAGESIZE))dst[-1]=0x6c;
REQUIRE(aggregate_abi_native_send31(src)==1);REQUIRE(aggregate_abi_native_guard_return((void*)aggregate_abi_native_ret31,dst,src)==(uintptr_t)dst);REQUIRE(memcmp(dst,src,31)==0);if(31<(size_t)sysconf(_SC_PAGESIZE))REQUIRE(dst[-1]==0x6c);for(size_t i=0;i<31;++i)REQUIRE(src[i]==pattern(i,31));REQUIRE(munmap(sm,sl)==0);REQUIRE(munmap(dm,dl)==0);}
{R32 a;for(size_t i=0;i<32;++i)a.b[i]=pattern(i,32);R32 r=aggregate_abi_native_echo32(a);REQUIRE(memcmp(&r,&a,sizeof a)==0);
void *sm,*dm;size_t sl,dl;unsigned char* src=guarded(32,&sm,&sl);unsigned char* dst=guarded(32,&dm,&dl);for(size_t i=0;i<32;++i)src[i]=pattern(i,32);REQUIRE(mprotect((char*)sm+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);memset(dst,0xa5,32);if(32<(size_t)sysconf(_SC_PAGESIZE))dst[-1]=0x6c;
REQUIRE(aggregate_abi_native_send32(src)==1);REQUIRE(aggregate_abi_native_guard_return((void*)aggregate_abi_native_ret32,dst,src)==(uintptr_t)dst);REQUIRE(memcmp(dst,src,32)==0);if(32<(size_t)sysconf(_SC_PAGESIZE))REQUIRE(dst[-1]==0x6c);for(size_t i=0;i<32;++i)REQUIRE(src[i]==pattern(i,32));REQUIRE(munmap(sm,sl)==0);REQUIRE(munmap(dm,dl)==0);}
{R4096 a;for(size_t i=0;i<4096;++i)a.b[i]=pattern(i,4096);R4096 r=aggregate_abi_native_echo4096(a);REQUIRE(memcmp(&r,&a,sizeof a)==0);
void *sm,*dm;size_t sl,dl;unsigned char* src=guarded(4096,&sm,&sl);unsigned char* dst=guarded(4096,&dm,&dl);for(size_t i=0;i<4096;++i)src[i]=pattern(i,4096);REQUIRE(mprotect((char*)sm+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);memset(dst,0xa5,4096);if(4096<(size_t)sysconf(_SC_PAGESIZE))dst[-1]=0x6c;
REQUIRE(aggregate_abi_native_send4096(src)==1);REQUIRE(aggregate_abi_native_guard_return((void*)aggregate_abi_native_ret4096,dst,src)==(uintptr_t)dst);REQUIRE(memcmp(dst,src,4096)==0);if(4096<(size_t)sysconf(_SC_PAGESIZE))REQUIRE(dst[-1]==0x6c);for(size_t i=0;i<4096;++i)REQUIRE(src[i]==pattern(i,4096));REQUIRE(munmap(sm,sl)==0);REQUIRE(munmap(dm,dl)==0);}
R17 a;for(size_t i=0;i<17;++i)a.b[i]=pattern(i,17);R17 original=a;
REQUIRE(aggregate_abi_native_mutate(a,a)==a.b[0]);REQUIRE(memcmp(&a,&original,sizeof a)==0);
REQUIRE(aggregate_abi_native_sendtwice(&a)==1);REQUIRE(memcmp(&a,&original,sizeof a)==0);
R17 r=aggregate_abi_native_roundtrip(a);REQUIRE(r.b[16]==(unsigned char)(a.b[16]^0x55));REQUIRE(r.b[0]==a.b[0]);
r=aggregate_abi_native_recurse(a,10);REQUIRE(memcmp(&r,&a,sizeof a)==0);
r=aggregate_abi_native_dynamic(&a);REQUIRE(memcmp(&r,&a,sizeof a)==0);
REQUIRE(aggregate_abi_native_sites()==33);REQUIRE(aggregate_abi_native_loop(9)==1);
REQUIRE(aggregate_abi_native_varcaller(&a,UINT64_C(9))==a.b[0]+9u);
REQUIRE(aggregate_abi_native_env_bridge(&a)==a.b[0]+7u);
r=aggregate_abi_native_scalarindirect(a,indirect);REQUIRE(r.b[0]==43);REQUIRE(a.b[0]==20);
Aligned b;memset(&b,0,sizeof b);b.q[0]=UINT64_C(0x1122334455667788);b.q[1]=UINT64_C(0x8877665544332211);b.q[2]=93;Aligned br=aggregate_abi_native_aligned(b);REQUIRE(br.q[0]==b.q[0] && br.q[1]==b.q[1] && br.q[2]==b.q[2]);
r=aggregate_abi_native_mix(11,22,33,44,55,66,a,b,1.,2.,3.,4.,5.,6.,7.,8.,9.);REQUIRE(memcmp(&r,&a,sizeof a)==0);REQUIRE(aggregate_abi_native_callmix(&a,&b)==233);
REQUIRE(aggregate_abi_native_callprobe(&a,&b)==234);R17 manual;memset(&manual,0,sizeof manual);REQUIRE(aggregate_abi_native_manual_caller(&manual,&a,&b)==1);REQUIRE(memcmp(&manual,&a,sizeof a)==0);
REQUIRE(aggregate_abi_native_bits(&a)==235);uint64_t zb=UINT64_C(0x8000000000000000),nb=UINT64_C(0x7ff8000000001234),lb=UINT64_C(0x7ff8000000005678);double zv,nv,lv;memcpy(&zv,&zb,8);memcpy(&nv,&nb,8);memcpy(&lv,&lb,8);r=aggregate_abi_native_bitreceiver(a,zv,nv,3.,4.,5.,6.,7.,8.,lv);REQUIRE(r.b[0]==235);
r=aggregate_abi_native_subincoming(-128,255,-32768,65535,-1,254,a);REQUIRE(r.b[0]==236);REQUIRE(aggregate_abi_native_suboutgoing(&a)==237);
printf("%u independent native MEMORY checks passed\n",checks);return 0;}
