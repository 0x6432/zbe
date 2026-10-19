#define _GNU_SOURCE
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
static unsigned checks;
#define REQUIRE(c) do{++checks;if(!(c)){fprintf(stderr,"small SSE line%d\n",__LINE__);abort();}}while(0)
static const uint32_t bits32[]={0x80000000u,0x7f800000u,0xff800000u,0x7fc12345u,0x7fa12345u,1u,0x3f800001u,0x7fffffffu};
static const uint64_t bits64[]={UINT64_C(0x8000000000000000),UINT64_C(0x7ff0000000000000),UINT64_C(0xfff0000000000000),UINT64_C(0x7ff8123456789abc),UINT64_C(0x7ff0123456789abc),UINT64_C(1),UINT64_C(0x3ff0000000000001),UINT64_C(0x7fffffffffffffff)};
static uint32_t raw32(float f){uint32_t u;memcpy(&u,&f,4);return u;}
static uint64_t raw64(double d){uint64_t u;memcpy(&u,&d,8);return u;}
typedef struct{uint32_t u;float f;} QIS;
typedef struct{float f;uint32_t u;} QSI;
_Static_assert(sizeof(QIS)==8 && offsetof(QIS,f)==4 && sizeof(QSI)==8 && offsetof(QSI,u)==4,"independent shifted child layout");
static unsigned char* guarded(size_t n,void** mapping,size_t* length){long pg=sysconf(_SC_PAGESIZE);REQUIRE(pg>=4096);*length=(size_t)pg*3;*mapping=mmap(NULL,*length,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);REQUIRE(*mapping!=MAP_FAILED);REQUIRE(mprotect((char*)*mapping+pg,(size_t)pg,PROT_READ|PROT_WRITE)==0);return (unsigned char*)*mapping+2*pg-n;}

typedef struct{float f;} F4;
_Static_assert(sizeof(F4)==4 && _Alignof(F4)==4,"independent F4 layout");
static F4 expected_F4;
static void init_F4(F4* p,unsigned n){memset(p,0,sizeof *p);uint32_t f0=bits32[(n+0)%8];memcpy(&p->f,&f0,4);}
uint32_t aggregate_abi_small_sse_check_F4(F4 p){return raw32(p.f)==raw32(expected_F4.f);}
F4 aggregate_abi_small_sse_make_F4(const void* source){F4 p;memcpy(&p,source,sizeof p);return p;}
extern F4 aggregate_abi_small_sse_echo_F4(F4),aggregate_abi_small_sse_ret_F4(const void*);
extern uint32_t aggregate_abi_small_sse_send_F4(const void*),aggregate_abi_small_sse_roundtrip_F4(const void*),aggregate_abi_small_sse_mutate_F4(F4,F4);
typedef struct{float f[2];} F8;
_Static_assert(sizeof(F8)==8 && _Alignof(F8)==4,"independent F8 layout");
static F8 expected_F8;
static void init_F8(F8* p,unsigned n){memset(p,0,sizeof *p);uint32_t f0=bits32[(n+0)%8];memcpy(&p->f[0],&f0,4);uint32_t f1=bits32[(n+1)%8];memcpy(&p->f[1],&f1,4);}
uint32_t aggregate_abi_small_sse_check_F8(F8 p){return raw32(p.f[0])==raw32(expected_F8.f[0]) && raw32(p.f[1])==raw32(expected_F8.f[1]);}
F8 aggregate_abi_small_sse_make_F8(const void* source){F8 p;memcpy(&p,source,sizeof p);return p;}
extern F8 aggregate_abi_small_sse_echo_F8(F8),aggregate_abi_small_sse_ret_F8(const void*);
extern uint32_t aggregate_abi_small_sse_send_F8(const void*),aggregate_abi_small_sse_roundtrip_F8(const void*),aggregate_abi_small_sse_mutate_F8(F8,F8);
typedef struct{float f[3];} F12;
_Static_assert(sizeof(F12)==12 && _Alignof(F12)==4,"independent F12 layout");
static F12 expected_F12;
static void init_F12(F12* p,unsigned n){memset(p,0,sizeof *p);uint32_t f0=bits32[(n+0)%8];memcpy(&p->f[0],&f0,4);uint32_t f1=bits32[(n+1)%8];memcpy(&p->f[1],&f1,4);uint32_t f2=bits32[(n+2)%8];memcpy(&p->f[2],&f2,4);}
uint32_t aggregate_abi_small_sse_check_F12(F12 p){return raw32(p.f[0])==raw32(expected_F12.f[0]) && raw32(p.f[1])==raw32(expected_F12.f[1]) && raw32(p.f[2])==raw32(expected_F12.f[2]);}
F12 aggregate_abi_small_sse_make_F12(const void* source){F12 p;memcpy(&p,source,sizeof p);return p;}
extern F12 aggregate_abi_small_sse_echo_F12(F12),aggregate_abi_small_sse_ret_F12(const void*);
extern uint32_t aggregate_abi_small_sse_send_F12(const void*),aggregate_abi_small_sse_roundtrip_F12(const void*),aggregate_abi_small_sse_mutate_F12(F12,F12);
typedef struct{double d;} D8;
_Static_assert(sizeof(D8)==8 && _Alignof(D8)==8,"independent D8 layout");
static D8 expected_D8;
static void init_D8(D8* p,unsigned n){memset(p,0,sizeof *p);uint64_t d0=bits64[(n+0)%8];memcpy(&p->d,&d0,8);}
uint32_t aggregate_abi_small_sse_check_D8(D8 p){return raw64(p.d)==raw64(expected_D8.d);}
D8 aggregate_abi_small_sse_make_D8(const void* source){D8 p;memcpy(&p,source,sizeof p);return p;}
extern D8 aggregate_abi_small_sse_echo_D8(D8),aggregate_abi_small_sse_ret_D8(const void*);
extern uint32_t aggregate_abi_small_sse_send_D8(const void*),aggregate_abi_small_sse_roundtrip_D8(const void*),aggregate_abi_small_sse_mutate_D8(D8,D8);
typedef struct{double d[2];} D16;
_Static_assert(sizeof(D16)==16 && _Alignof(D16)==8,"independent D16 layout");
static D16 expected_D16;
static void init_D16(D16* p,unsigned n){memset(p,0,sizeof *p);uint64_t d0=bits64[(n+0)%8];memcpy(&p->d[0],&d0,8);uint64_t d1=bits64[(n+1)%8];memcpy(&p->d[1],&d1,8);}
uint32_t aggregate_abi_small_sse_check_D16(D16 p){return raw64(p.d[0])==raw64(expected_D16.d[0]) && raw64(p.d[1])==raw64(expected_D16.d[1]);}
D16 aggregate_abi_small_sse_make_D16(const void* source){D16 p;memcpy(&p,source,sizeof p);return p;}
extern D16 aggregate_abi_small_sse_echo_D16(D16),aggregate_abi_small_sse_ret_D16(const void*);
extern uint32_t aggregate_abi_small_sse_send_D16(const void*),aggregate_abi_small_sse_roundtrip_D16(const void*),aggregate_abi_small_sse_mutate_D16(D16,D16);
typedef struct{float f; uint64_t u;} SI16;
_Static_assert(sizeof(SI16)==16 && _Alignof(SI16)==8,"independent SI16 layout");
static SI16 expected_SI16;
static void init_SI16(SI16* p,unsigned n){memset(p,0,sizeof *p);uint32_t f0=bits32[(n+0)%8];memcpy(&p->f,&f0,4);p->u=UINT64_C(0x8877665544332200)+n;}
uint32_t aggregate_abi_small_sse_check_SI16(SI16 p){return raw32(p.f)==raw32(expected_SI16.f) && p.u==expected_SI16.u;}
SI16 aggregate_abi_small_sse_make_SI16(const void* source){SI16 p;memcpy(&p,source,sizeof p);return p;}
extern SI16 aggregate_abi_small_sse_echo_SI16(SI16),aggregate_abi_small_sse_ret_SI16(const void*);
extern uint32_t aggregate_abi_small_sse_send_SI16(const void*),aggregate_abi_small_sse_roundtrip_SI16(const void*),aggregate_abi_small_sse_mutate_SI16(SI16,SI16);
typedef struct{uint64_t u; float f;} IS16;
_Static_assert(sizeof(IS16)==16 && _Alignof(IS16)==8,"independent IS16 layout");
static IS16 expected_IS16;
static void init_IS16(IS16* p,unsigned n){memset(p,0,sizeof *p);uint32_t f0=bits32[(n+0)%8];memcpy(&p->f,&f0,4);p->u=UINT64_C(0x8877665544332200)+n;}
uint32_t aggregate_abi_small_sse_check_IS16(IS16 p){return raw32(p.f)==raw32(expected_IS16.f) && p.u==expected_IS16.u;}
IS16 aggregate_abi_small_sse_make_IS16(const void* source){IS16 p;memcpy(&p,source,sizeof p);return p;}
extern IS16 aggregate_abi_small_sse_echo_IS16(IS16),aggregate_abi_small_sse_ret_IS16(const void*);
extern uint32_t aggregate_abi_small_sse_send_IS16(const void*),aggregate_abi_small_sse_roundtrip_IS16(const void*),aggregate_abi_small_sse_mutate_IS16(IS16,IS16);
typedef struct{uint32_t u; float f;} I8;
_Static_assert(sizeof(I8)==8 && _Alignof(I8)==4,"independent I8 layout");
static I8 expected_I8;
static void init_I8(I8* p,unsigned n){memset(p,0,sizeof *p);uint32_t f0=bits32[(n+0)%8];memcpy(&p->f,&f0,4);p->u=UINT32_C(0xaabbcc00)+n;}
uint32_t aggregate_abi_small_sse_check_I8(I8 p){return raw32(p.f)==raw32(expected_I8.f) && p.u==expected_I8.u;}
I8 aggregate_abi_small_sse_make_I8(const void* source){I8 p;memcpy(&p,source,sizeof p);return p;}
extern I8 aggregate_abi_small_sse_echo_I8(I8),aggregate_abi_small_sse_ret_I8(const void*);
extern uint32_t aggregate_abi_small_sse_send_I8(const void*),aggregate_abi_small_sse_roundtrip_I8(const void*),aggregate_abi_small_sse_mutate_I8(I8,I8);
typedef struct{float first; QIS child;} PIS12;
_Static_assert(sizeof(PIS12)==12 && _Alignof(PIS12)==4,"independent PIS12 layout");
static PIS12 expected_PIS12;
static void init_PIS12(PIS12* p,unsigned n){memset(p,0,sizeof *p);uint32_t f0=bits32[(n+0)%8];memcpy(&p->first,&f0,4);uint32_t f1=bits32[(n+1)%8];memcpy(&p->child.f,&f1,4);p->child.u=UINT32_C(0xaabbcc00)+n;}
uint32_t aggregate_abi_small_sse_check_PIS12(PIS12 p){return raw32(p.first)==raw32(expected_PIS12.first) && raw32(p.child.f)==raw32(expected_PIS12.child.f) && p.child.u==expected_PIS12.child.u;}
PIS12 aggregate_abi_small_sse_make_PIS12(const void* source){PIS12 p;memcpy(&p,source,sizeof p);return p;}
extern PIS12 aggregate_abi_small_sse_echo_PIS12(PIS12),aggregate_abi_small_sse_ret_PIS12(const void*);
extern uint32_t aggregate_abi_small_sse_send_PIS12(const void*),aggregate_abi_small_sse_roundtrip_PIS12(const void*),aggregate_abi_small_sse_mutate_PIS12(PIS12,PIS12);
typedef struct{float first; QSI child;} PSI12;
_Static_assert(sizeof(PSI12)==12 && _Alignof(PSI12)==4,"independent PSI12 layout");
static PSI12 expected_PSI12;
static void init_PSI12(PSI12* p,unsigned n){memset(p,0,sizeof *p);uint32_t f0=bits32[(n+0)%8];memcpy(&p->first,&f0,4);uint32_t f1=bits32[(n+1)%8];memcpy(&p->child.f,&f1,4);p->child.u=UINT32_C(0xaabbcc00)+n;}
uint32_t aggregate_abi_small_sse_check_PSI12(PSI12 p){return raw32(p.first)==raw32(expected_PSI12.first) && raw32(p.child.f)==raw32(expected_PSI12.child.f) && p.child.u==expected_PSI12.child.u;}
PSI12 aggregate_abi_small_sse_make_PSI12(const void* source){PSI12 p;memcpy(&p,source,sizeof p);return p;}
extern PSI12 aggregate_abi_small_sse_echo_PSI12(PSI12),aggregate_abi_small_sse_ret_PSI12(const void*);
extern uint32_t aggregate_abi_small_sse_send_PSI12(const void*),aggregate_abi_small_sse_roundtrip_PSI12(const void*),aggregate_abi_small_sse_mutate_PSI12(PSI12,PSI12);
extern uint32_t aggregate_abi_small_sse_preserved(void(*)(void),const void*,unsigned char[32]);
extern F4 aggregate_abi_small_sse_poison_incoming_F4(const void*);
extern uint32_t aggregate_abi_small_sse_poison_capture_F4(const void*);
extern F12 aggregate_abi_small_sse_poison_incoming_F12(const void*);
extern uint32_t aggregate_abi_small_sse_poison_capture_F12(const void*);
extern PIS12 aggregate_abi_small_sse_poison_incoming_PIS12(const void*);
extern uint32_t aggregate_abi_small_sse_poison_capture_PIS12(const void*);
extern PSI12 aggregate_abi_small_sse_poison_incoming_PSI12(const void*);
extern uint32_t aggregate_abi_small_sse_poison_capture_PSI12(const void*);
typedef struct{uint8_t b;} Byte;
uint32_t aggregate_abi_small_sse_verify_gp(uint64_t l0,uint64_t l1,uint64_t l2,uint64_t l3,uint64_t l4,uint64_t l5,double d0,double d1,double d2,double d3,double d4,double d5,double d6,IS16 m,double after,double spill){return l0==1 && l1==2 && l2==3 && l3==4 && l4==5 && l5==6 && d0==1. && d1==2. && d2==3. && d3==4. && d4==5. && d5==6. && d6==7. && after==8. && spill==9. && aggregate_abi_small_sse_check_IS16(m);}
extern IS16 aggregate_abi_small_sse_receiver_gp(uint64_t l0,uint64_t l1,uint64_t l2,uint64_t l3,uint64_t l4,uint64_t l5,double d0,double d1,double d2,double d3,double d4,double d5,double d6,IS16 m,double after,double spill);
extern uint32_t aggregate_abi_small_sse_probe_gp(const void*,const void*);
uint32_t aggregate_abi_small_sse_verify_sse(uint64_t l0,uint64_t l1,uint64_t l2,uint64_t l3,uint64_t l4,double d0,double d1,double d2,double d3,double d4,double d5,double d6,double d7,IS16 m,uint64_t after,Byte b,double spill){return l0==1 && l1==2 && l2==3 && l3==4 && l4==5 && after==99 && d0==1. && d1==2. && d2==3. && d3==4. && d4==5. && d5==6. && d6==7. && d7==8. && spill==9. && aggregate_abi_small_sse_check_IS16(m) && b.b==38;}
extern IS16 aggregate_abi_small_sse_receiver_sse(uint64_t l0,uint64_t l1,uint64_t l2,uint64_t l3,uint64_t l4,double d0,double d1,double d2,double d3,double d4,double d5,double d6,double d7,IS16 m,uint64_t after,Byte b,double spill);
extern uint32_t aggregate_abi_small_sse_probe_sse(const void*,const void*);
uint32_t aggregate_abi_small_sse_verify_fit(uint64_t l0,uint64_t l1,uint64_t l2,uint64_t l3,uint64_t l4,double d0,double d1,double d2,double d3,double d4,double d5,double d6,IS16 m,uint64_t after,double spill){return l0==1 && l1==2 && l2==3 && l3==4 && l4==5 && after==99 && d0==1. && d1==2. && d2==3. && d3==4. && d4==5. && d5==6. && d6==7. && spill==9. && aggregate_abi_small_sse_check_IS16(m);}
extern IS16 aggregate_abi_small_sse_receiver_fit(uint64_t l0,uint64_t l1,uint64_t l2,uint64_t l3,uint64_t l4,double d0,double d1,double d2,double d3,double d4,double d5,double d6,IS16 m,uint64_t after,double spill);
extern uint32_t aggregate_abi_small_sse_probe_fit(const void*,const void*);
uint32_t aggregate_abi_small_sse_verify_ss(double d0,double d1,double d2,double d3,double d4,double d5,double d6,F12 m,double after){return d0==1. && d1==2. && d2==3. && d3==4. && d4==5. && d5==6. && d6==7. && after==8. && aggregate_abi_small_sse_check_F12(m);}
extern F12 aggregate_abi_small_sse_receiver_ss(double d0,double d1,double d2,double d3,double d4,double d5,double d6,F12 m,double after);
extern uint32_t aggregate_abi_small_sse_probe_ss(const void*,const void*);

F4 aggregate_abi_small_sse_fill(uint32_t bits){F4 a;memcpy(&a.f,&bits,4);return a;}
static const void* observed;
uint32_t aggregate_abi_small_sse_observe(const void* p,uint32_t i){uint32_t bits;memcpy(&bits,p,4);if(!i)observed=p;return p==observed && bits==UINT32_C(0x12340000)+i;}
F12 aggregate_abi_small_sse_stack_F12(const void* p,uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,uint64_t f,uint64_t g,double d0,double d1,double d2,double d3,double d4,double d5,double d6,double d7,double d8){REQUIRE(a==1&&b==2&&c==3&&d==4&&e==5&&f==6&&g==7);REQUIRE(d0==1.&&d1==2.&&d2==3.&&d3==4.&&d4==5.&&d5==6.&&d6==7.&&d7==8.&&d8==9.);return aggregate_abi_small_sse_make_F12(p);}
typedef struct{unsigned char bytes[27];} M27;
_Static_assert(sizeof(M27)==27 && _Alignof(M27)==1,"independent MEMORY27 layout");
M27 aggregate_abi_small_sse_make_M27(uint32_t byte){M27 a;memset(&a,(unsigned char)byte,27);return a;}
extern M27 aggregate_abi_small_sse_hidden(F12,PSI12,const void*),aggregate_abi_small_sse_hidden_caller(const void*,const void*);
extern F12 aggregate_abi_small_sse_recurse(F12,uint32_t),aggregate_abi_small_sse_dynamic(const void*);
extern uint32_t aggregate_abi_small_sse_sites(void),aggregate_abi_small_sse_loop(uint32_t),aggregate_abi_small_sse_envbridge(const void*);
extern uint64_t aggregate_abi_small_sse_varcaller(const void*,...);
int main(void){
for(unsigned n=0;n<8;++n){F4 a;init_F4(&a,n);expected_F4=a;REQUIRE(aggregate_abi_small_sse_poison_capture_F4(&a)==1);
F4 result=aggregate_abi_small_sse_echo_F4(a);REQUIRE(aggregate_abi_small_sse_check_F4(result));result=aggregate_abi_small_sse_poison_incoming_F4(&a);REQUIRE(aggregate_abi_small_sse_check_F4(result));
REQUIRE(aggregate_abi_small_sse_send_F4(&a)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_F4(&a)==1);REQUIRE(aggregate_abi_small_sse_mutate_F4(a,a)==1);REQUIRE(aggregate_abi_small_sse_check_F4(a));
void* mapping;size_t length;unsigned char* p=guarded(4,&mapping,&length);memcpy(p,&a,4);REQUIRE(mprotect((char*)mapping+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
result=aggregate_abi_small_sse_ret_F4(p);REQUIRE(aggregate_abi_small_sse_check_F4(result));unsigned char captured[32];REQUIRE(aggregate_abi_small_sse_preserved((void(*)(void))aggregate_abi_small_sse_ret_F4,p,captured));F4 rebuilt;memset(&rebuilt,0,sizeof rebuilt);memcpy((char*)&rebuilt+0,captured+16,4);REQUIRE(aggregate_abi_small_sse_check_F4(rebuilt));REQUIRE(aggregate_abi_small_sse_send_F4(p)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_F4(p)==1);REQUIRE(memcmp(p,&a,4)==0);REQUIRE(munmap(mapping,length)==0);}
for(unsigned n=0;n<8;++n){F8 a;init_F8(&a,n);expected_F8=a;
F8 result=aggregate_abi_small_sse_echo_F8(a);REQUIRE(aggregate_abi_small_sse_check_F8(result));
REQUIRE(aggregate_abi_small_sse_send_F8(&a)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_F8(&a)==1);REQUIRE(aggregate_abi_small_sse_mutate_F8(a,a)==1);REQUIRE(aggregate_abi_small_sse_check_F8(a));
void* mapping;size_t length;unsigned char* p=guarded(8,&mapping,&length);memcpy(p,&a,8);REQUIRE(mprotect((char*)mapping+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
result=aggregate_abi_small_sse_ret_F8(p);REQUIRE(aggregate_abi_small_sse_check_F8(result));unsigned char captured[32];REQUIRE(aggregate_abi_small_sse_preserved((void(*)(void))aggregate_abi_small_sse_ret_F8,p,captured));F8 rebuilt;memset(&rebuilt,0,sizeof rebuilt);memcpy((char*)&rebuilt+0,captured+16,8);REQUIRE(aggregate_abi_small_sse_check_F8(rebuilt));REQUIRE(aggregate_abi_small_sse_send_F8(p)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_F8(p)==1);REQUIRE(memcmp(p,&a,8)==0);REQUIRE(munmap(mapping,length)==0);}
for(unsigned n=0;n<8;++n){F12 a;init_F12(&a,n);expected_F12=a;REQUIRE(aggregate_abi_small_sse_poison_capture_F12(&a)==1);
F12 result=aggregate_abi_small_sse_echo_F12(a);REQUIRE(aggregate_abi_small_sse_check_F12(result));result=aggregate_abi_small_sse_poison_incoming_F12(&a);REQUIRE(aggregate_abi_small_sse_check_F12(result));
REQUIRE(aggregate_abi_small_sse_send_F12(&a)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_F12(&a)==1);REQUIRE(aggregate_abi_small_sse_mutate_F12(a,a)==1);REQUIRE(aggregate_abi_small_sse_check_F12(a));
void* mapping;size_t length;unsigned char* p=guarded(12,&mapping,&length);memcpy(p,&a,12);REQUIRE(mprotect((char*)mapping+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
result=aggregate_abi_small_sse_ret_F12(p);REQUIRE(aggregate_abi_small_sse_check_F12(result));unsigned char captured[32];REQUIRE(aggregate_abi_small_sse_preserved((void(*)(void))aggregate_abi_small_sse_ret_F12,p,captured));F12 rebuilt;memset(&rebuilt,0,sizeof rebuilt);memcpy((char*)&rebuilt+0,captured+16,8);memcpy((char*)&rebuilt+8,captured+24,4);REQUIRE(aggregate_abi_small_sse_check_F12(rebuilt));REQUIRE(aggregate_abi_small_sse_send_F12(p)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_F12(p)==1);REQUIRE(memcmp(p,&a,12)==0);REQUIRE(munmap(mapping,length)==0);}
for(unsigned n=0;n<8;++n){D8 a;init_D8(&a,n);expected_D8=a;
D8 result=aggregate_abi_small_sse_echo_D8(a);REQUIRE(aggregate_abi_small_sse_check_D8(result));
REQUIRE(aggregate_abi_small_sse_send_D8(&a)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_D8(&a)==1);REQUIRE(aggregate_abi_small_sse_mutate_D8(a,a)==1);REQUIRE(aggregate_abi_small_sse_check_D8(a));
void* mapping;size_t length;unsigned char* p=guarded(8,&mapping,&length);memcpy(p,&a,8);REQUIRE(mprotect((char*)mapping+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
result=aggregate_abi_small_sse_ret_D8(p);REQUIRE(aggregate_abi_small_sse_check_D8(result));unsigned char captured[32];REQUIRE(aggregate_abi_small_sse_preserved((void(*)(void))aggregate_abi_small_sse_ret_D8,p,captured));D8 rebuilt;memset(&rebuilt,0,sizeof rebuilt);memcpy((char*)&rebuilt+0,captured+16,8);REQUIRE(aggregate_abi_small_sse_check_D8(rebuilt));REQUIRE(aggregate_abi_small_sse_send_D8(p)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_D8(p)==1);REQUIRE(memcmp(p,&a,8)==0);REQUIRE(munmap(mapping,length)==0);}
for(unsigned n=0;n<8;++n){D16 a;init_D16(&a,n);expected_D16=a;
D16 result=aggregate_abi_small_sse_echo_D16(a);REQUIRE(aggregate_abi_small_sse_check_D16(result));
REQUIRE(aggregate_abi_small_sse_send_D16(&a)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_D16(&a)==1);REQUIRE(aggregate_abi_small_sse_mutate_D16(a,a)==1);REQUIRE(aggregate_abi_small_sse_check_D16(a));
void* mapping;size_t length;unsigned char* p=guarded(16,&mapping,&length);memcpy(p,&a,16);REQUIRE(mprotect((char*)mapping+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
result=aggregate_abi_small_sse_ret_D16(p);REQUIRE(aggregate_abi_small_sse_check_D16(result));unsigned char captured[32];REQUIRE(aggregate_abi_small_sse_preserved((void(*)(void))aggregate_abi_small_sse_ret_D16,p,captured));D16 rebuilt;memset(&rebuilt,0,sizeof rebuilt);memcpy((char*)&rebuilt+0,captured+16,8);memcpy((char*)&rebuilt+8,captured+24,8);REQUIRE(aggregate_abi_small_sse_check_D16(rebuilt));REQUIRE(aggregate_abi_small_sse_send_D16(p)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_D16(p)==1);REQUIRE(memcmp(p,&a,16)==0);REQUIRE(munmap(mapping,length)==0);}
for(unsigned n=0;n<8;++n){SI16 a;init_SI16(&a,n);expected_SI16=a;
SI16 result=aggregate_abi_small_sse_echo_SI16(a);REQUIRE(aggregate_abi_small_sse_check_SI16(result));
REQUIRE(aggregate_abi_small_sse_send_SI16(&a)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_SI16(&a)==1);REQUIRE(aggregate_abi_small_sse_mutate_SI16(a,a)==1);REQUIRE(aggregate_abi_small_sse_check_SI16(a));
void* mapping;size_t length;unsigned char* p=guarded(16,&mapping,&length);memcpy(p,&a,16);REQUIRE(mprotect((char*)mapping+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
result=aggregate_abi_small_sse_ret_SI16(p);REQUIRE(aggregate_abi_small_sse_check_SI16(result));unsigned char captured[32];REQUIRE(aggregate_abi_small_sse_preserved((void(*)(void))aggregate_abi_small_sse_ret_SI16,p,captured));SI16 rebuilt;memset(&rebuilt,0,sizeof rebuilt);memcpy((char*)&rebuilt+0,captured+16,8);memcpy((char*)&rebuilt+8,captured+0,8);REQUIRE(aggregate_abi_small_sse_check_SI16(rebuilt));REQUIRE(aggregate_abi_small_sse_send_SI16(p)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_SI16(p)==1);REQUIRE(memcmp(p,&a,16)==0);REQUIRE(munmap(mapping,length)==0);}
for(unsigned n=0;n<8;++n){IS16 a;init_IS16(&a,n);expected_IS16=a;
IS16 result=aggregate_abi_small_sse_echo_IS16(a);REQUIRE(aggregate_abi_small_sse_check_IS16(result));
REQUIRE(aggregate_abi_small_sse_send_IS16(&a)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_IS16(&a)==1);REQUIRE(aggregate_abi_small_sse_mutate_IS16(a,a)==1);REQUIRE(aggregate_abi_small_sse_check_IS16(a));
void* mapping;size_t length;unsigned char* p=guarded(16,&mapping,&length);memcpy(p,&a,16);REQUIRE(mprotect((char*)mapping+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
result=aggregate_abi_small_sse_ret_IS16(p);REQUIRE(aggregate_abi_small_sse_check_IS16(result));unsigned char captured[32];REQUIRE(aggregate_abi_small_sse_preserved((void(*)(void))aggregate_abi_small_sse_ret_IS16,p,captured));IS16 rebuilt;memset(&rebuilt,0,sizeof rebuilt);memcpy((char*)&rebuilt+0,captured+0,8);memcpy((char*)&rebuilt+8,captured+16,8);REQUIRE(aggregate_abi_small_sse_check_IS16(rebuilt));REQUIRE(aggregate_abi_small_sse_send_IS16(p)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_IS16(p)==1);REQUIRE(memcmp(p,&a,16)==0);REQUIRE(munmap(mapping,length)==0);}
for(unsigned n=0;n<8;++n){I8 a;init_I8(&a,n);expected_I8=a;
I8 result=aggregate_abi_small_sse_echo_I8(a);REQUIRE(aggregate_abi_small_sse_check_I8(result));
REQUIRE(aggregate_abi_small_sse_send_I8(&a)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_I8(&a)==1);REQUIRE(aggregate_abi_small_sse_mutate_I8(a,a)==1);REQUIRE(aggregate_abi_small_sse_check_I8(a));
void* mapping;size_t length;unsigned char* p=guarded(8,&mapping,&length);memcpy(p,&a,8);REQUIRE(mprotect((char*)mapping+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
result=aggregate_abi_small_sse_ret_I8(p);REQUIRE(aggregate_abi_small_sse_check_I8(result));unsigned char captured[32];REQUIRE(aggregate_abi_small_sse_preserved((void(*)(void))aggregate_abi_small_sse_ret_I8,p,captured));I8 rebuilt;memset(&rebuilt,0,sizeof rebuilt);memcpy((char*)&rebuilt+0,captured+0,8);REQUIRE(aggregate_abi_small_sse_check_I8(rebuilt));REQUIRE(aggregate_abi_small_sse_send_I8(p)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_I8(p)==1);REQUIRE(memcmp(p,&a,8)==0);REQUIRE(munmap(mapping,length)==0);}
for(unsigned n=0;n<8;++n){PIS12 a;init_PIS12(&a,n);expected_PIS12=a;REQUIRE(aggregate_abi_small_sse_poison_capture_PIS12(&a)==1);
PIS12 result=aggregate_abi_small_sse_echo_PIS12(a);REQUIRE(aggregate_abi_small_sse_check_PIS12(result));result=aggregate_abi_small_sse_poison_incoming_PIS12(&a);REQUIRE(aggregate_abi_small_sse_check_PIS12(result));
REQUIRE(aggregate_abi_small_sse_send_PIS12(&a)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_PIS12(&a)==1);REQUIRE(aggregate_abi_small_sse_mutate_PIS12(a,a)==1);REQUIRE(aggregate_abi_small_sse_check_PIS12(a));
void* mapping;size_t length;unsigned char* p=guarded(12,&mapping,&length);memcpy(p,&a,12);REQUIRE(mprotect((char*)mapping+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
result=aggregate_abi_small_sse_ret_PIS12(p);REQUIRE(aggregate_abi_small_sse_check_PIS12(result));unsigned char captured[32];REQUIRE(aggregate_abi_small_sse_preserved((void(*)(void))aggregate_abi_small_sse_ret_PIS12,p,captured));PIS12 rebuilt;memset(&rebuilt,0,sizeof rebuilt);memcpy((char*)&rebuilt+0,captured+0,8);memcpy((char*)&rebuilt+8,captured+16,4);REQUIRE(aggregate_abi_small_sse_check_PIS12(rebuilt));REQUIRE(aggregate_abi_small_sse_send_PIS12(p)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_PIS12(p)==1);REQUIRE(memcmp(p,&a,12)==0);REQUIRE(munmap(mapping,length)==0);}
for(unsigned n=0;n<8;++n){PSI12 a;init_PSI12(&a,n);expected_PSI12=a;REQUIRE(aggregate_abi_small_sse_poison_capture_PSI12(&a)==1);
PSI12 result=aggregate_abi_small_sse_echo_PSI12(a);REQUIRE(aggregate_abi_small_sse_check_PSI12(result));result=aggregate_abi_small_sse_poison_incoming_PSI12(&a);REQUIRE(aggregate_abi_small_sse_check_PSI12(result));
REQUIRE(aggregate_abi_small_sse_send_PSI12(&a)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_PSI12(&a)==1);REQUIRE(aggregate_abi_small_sse_mutate_PSI12(a,a)==1);REQUIRE(aggregate_abi_small_sse_check_PSI12(a));
void* mapping;size_t length;unsigned char* p=guarded(12,&mapping,&length);memcpy(p,&a,12);REQUIRE(mprotect((char*)mapping+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
result=aggregate_abi_small_sse_ret_PSI12(p);REQUIRE(aggregate_abi_small_sse_check_PSI12(result));unsigned char captured[32];REQUIRE(aggregate_abi_small_sse_preserved((void(*)(void))aggregate_abi_small_sse_ret_PSI12,p,captured));PSI12 rebuilt;memset(&rebuilt,0,sizeof rebuilt);memcpy((char*)&rebuilt+0,captured+16,8);memcpy((char*)&rebuilt+8,captured+0,4);REQUIRE(aggregate_abi_small_sse_check_PSI12(rebuilt));REQUIRE(aggregate_abi_small_sse_send_PSI12(p)==1);REQUIRE(aggregate_abi_small_sse_roundtrip_PSI12(p)==1);REQUIRE(memcmp(p,&a,12)==0);REQUIRE(munmap(mapping,length)==0);}
{IS16 a;init_IS16(&a,0);expected_IS16=a;Byte b={38};REQUIRE(aggregate_abi_small_sse_probe_gp(&a,&b)==1);IS16 result=aggregate_abi_small_sse_receiver_gp(1,2,3,4,5,6,1.,2.,3.,4.,5.,6.,7.,a,8.,9.);REQUIRE(aggregate_abi_small_sse_check_IS16(result));}
{IS16 a;init_IS16(&a,0);expected_IS16=a;Byte b={38};REQUIRE(aggregate_abi_small_sse_probe_sse(&a,&b)==1);IS16 result=aggregate_abi_small_sse_receiver_sse(1,2,3,4,5,1.,2.,3.,4.,5.,6.,7.,8.,a,99,b,9.);REQUIRE(aggregate_abi_small_sse_check_IS16(result));}
{IS16 a;init_IS16(&a,0);expected_IS16=a;Byte b={38};REQUIRE(aggregate_abi_small_sse_probe_fit(&a,&b)==1);IS16 result=aggregate_abi_small_sse_receiver_fit(1,2,3,4,5,1.,2.,3.,4.,5.,6.,7.,a,99,9.);REQUIRE(aggregate_abi_small_sse_check_IS16(result));}
{F12 a;init_F12(&a,0);expected_F12=a;Byte b={38};REQUIRE(aggregate_abi_small_sse_probe_ss(&a,&b)==1);F12 result=aggregate_abi_small_sse_receiver_ss(1.,2.,3.,4.,5.,6.,7.,a,8.);REQUIRE(aggregate_abi_small_sse_check_F12(result));}
REQUIRE(aggregate_abi_small_sse_sites()==UINT32_C(0xff800000));REQUIRE(aggregate_abi_small_sse_loop(9)==1);
{F12 a;PSI12 b;init_F12(&a,0);init_PSI12(&b,0);expected_F12=a;expected_PSI12=b;F12 result=aggregate_abi_small_sse_recurse(a,9);REQUIRE(aggregate_abi_small_sse_check_F12(result));result=aggregate_abi_small_sse_dynamic(&a);REQUIRE(aggregate_abi_small_sse_check_F12(result));
uint64_t payload=UINT64_C(0x7ff0123456789abc);double value;memcpy(&value,&payload,8);REQUIRE(aggregate_abi_small_sse_varcaller(&a,value)==(payload^UINT64_C(0x80000000)));REQUIRE(aggregate_abi_small_sse_envbridge(&a)==UINT32_C(0x80000007));
M27 m=aggregate_abi_small_sse_hidden(a,b,&a);for(size_t i=0;i<27;++i)REQUIRE(m.bytes[i]==209);m=aggregate_abi_small_sse_hidden_caller(&a,&b);for(size_t i=0;i<27;++i)REQUIRE(m.bytes[i]==209);}
printf("%u independent small SSE checks passed\n",checks);return 0;}
