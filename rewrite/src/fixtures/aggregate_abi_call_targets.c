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
#define REQUIRE(c) do{++checks;if(!(c)){fprintf(stderr,"aggregate targets line%d\n",__LINE__);abort();}}while(0)
uint64_t aggregate_abi_call_targets_expected_env;
static unsigned env_seen,choice;
static const uint64_t bits[]={UINT64_C(0x8000000080000000),UINT64_C(0x7ff000007f800000),UINT64_C(0xfff00000ff800000),UINT64_C(0x7ff812347fc12345),UINT64_C(0x7ff012347fa12345),UINT64_C(1),UINT64_C(0x3ff000003f800001),UINT64_C(0x7fffffff7fffffff)};
void aggregate_abi_call_targets_env_check(uint64_t env,const void*p,uint32_t align){if(env!=aggregate_abi_call_targets_expected_env || ((uintptr_t)p%align))abort();++env_seen;}
uint32_t aggregate_abi_call_targets_vararg_probe(uint32_t count,...){va_list ap;va_start(ap,count);double d=va_arg(ap,double);va_end(ap);uint64_t u;memcpy(&u,&d,8);if(count!=1||u!=0)abort();return 1;}
static unsigned char* guarded(size_t size,void**mapping,size_t*len){long pg=sysconf(_SC_PAGESIZE);REQUIRE(pg>=4096);*len=(size_t)pg*3;*mapping=mmap(NULL,*len,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);REQUIRE(*mapping!=MAP_FAILED);REQUIRE(mprotect((char*)*mapping+pg,(size_t)pg,PROT_READ|PROT_WRITE)==0);return (unsigned char*)*mapping+2*pg-size;}

typedef struct{unsigned char b[3];}B3;
_Static_assert(sizeof(B3)==3 && _Alignof(B3)==1,"literal B3 layout");
_Static_assert(offsetof(B3,b[0])==0,"literal B3.b[0] offset");
_Static_assert(offsetof(B3,b[1])==1,"literal B3.b[1] offset");
_Static_assert(offsetof(B3,b[2])==2,"literal B3.b[2] offset");
static B3 expected_B3;
static int equal_B3(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,1)==0 && memcmp((const char*)a+1,(const char*)b+1,1)==0 && memcmp((const char*)a+2,(const char*)b+2,1)==0;}
B3 aggregate_abi_call_targets_B3_echo(B3 p){choice=1;return p;}
B3 aggregate_abi_call_targets_B3_echo_alt(B3 p){choice=2;return p;}
uint32_t aggregate_abi_call_targets_B3_check(B3 p){return equal_B3(&p,&expected_B3);}
extern B3 aggregate_abi_call_targets_B3_plain(B3),aggregate_abi_call_targets_B3_bridge(B3);
extern B3 aggregate_abi_call_targets_B3_indirect(B3(*)(B3),const void*),aggregate_abi_call_targets_B3_env_indirect(B3(*)(B3),const void*,uint64_t),aggregate_abi_call_targets_B3_alias(B3(*)(B3),const void*),aggregate_abi_call_targets_B3_loaded(const void*,const void*,uint64_t),aggregate_abi_call_targets_B3_choose(uint32_t,B3(*)(B3),B3(*)(B3),const void*,uint64_t),aggregate_abi_call_targets_B3_module_target(const void*,uint64_t),aggregate_abi_call_targets_B3_env_direct(const void*,uint64_t);
extern uint32_t aggregate_abi_call_targets_B3_send(uint32_t(*)(B3),const void*);
extern B3 aggregate_abi_call_targets_B3_env_target(B3),aggregate_abi_call_targets_B3_env_alt(B3),aggregate_abi_call_targets_B3_alias_target(B3);
typedef struct{unsigned char b[13];}I13;
_Static_assert(sizeof(I13)==13 && _Alignof(I13)==1,"literal I13 layout");
_Static_assert(offsetof(I13,b[0])==0,"literal I13.b[0] offset");
_Static_assert(offsetof(I13,b[1])==1,"literal I13.b[1] offset");
_Static_assert(offsetof(I13,b[2])==2,"literal I13.b[2] offset");
_Static_assert(offsetof(I13,b[3])==3,"literal I13.b[3] offset");
_Static_assert(offsetof(I13,b[4])==4,"literal I13.b[4] offset");
_Static_assert(offsetof(I13,b[5])==5,"literal I13.b[5] offset");
_Static_assert(offsetof(I13,b[6])==6,"literal I13.b[6] offset");
_Static_assert(offsetof(I13,b[7])==7,"literal I13.b[7] offset");
_Static_assert(offsetof(I13,b[8])==8,"literal I13.b[8] offset");
_Static_assert(offsetof(I13,b[9])==9,"literal I13.b[9] offset");
_Static_assert(offsetof(I13,b[10])==10,"literal I13.b[10] offset");
_Static_assert(offsetof(I13,b[11])==11,"literal I13.b[11] offset");
_Static_assert(offsetof(I13,b[12])==12,"literal I13.b[12] offset");
static I13 expected_I13;
static int equal_I13(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,1)==0 && memcmp((const char*)a+1,(const char*)b+1,1)==0 && memcmp((const char*)a+2,(const char*)b+2,1)==0 && memcmp((const char*)a+3,(const char*)b+3,1)==0 && memcmp((const char*)a+4,(const char*)b+4,1)==0 && memcmp((const char*)a+5,(const char*)b+5,1)==0 && memcmp((const char*)a+6,(const char*)b+6,1)==0 && memcmp((const char*)a+7,(const char*)b+7,1)==0 && memcmp((const char*)a+8,(const char*)b+8,1)==0 && memcmp((const char*)a+9,(const char*)b+9,1)==0 && memcmp((const char*)a+10,(const char*)b+10,1)==0 && memcmp((const char*)a+11,(const char*)b+11,1)==0 && memcmp((const char*)a+12,(const char*)b+12,1)==0;}
I13 aggregate_abi_call_targets_I13_echo(I13 p){choice=1;return p;}
I13 aggregate_abi_call_targets_I13_echo_alt(I13 p){choice=2;return p;}
uint32_t aggregate_abi_call_targets_I13_check(I13 p){return equal_I13(&p,&expected_I13);}
extern I13 aggregate_abi_call_targets_I13_plain(I13),aggregate_abi_call_targets_I13_bridge(I13);
extern I13 aggregate_abi_call_targets_I13_indirect(I13(*)(I13),const void*),aggregate_abi_call_targets_I13_env_indirect(I13(*)(I13),const void*,uint64_t),aggregate_abi_call_targets_I13_alias(I13(*)(I13),const void*),aggregate_abi_call_targets_I13_loaded(const void*,const void*,uint64_t),aggregate_abi_call_targets_I13_choose(uint32_t,I13(*)(I13),I13(*)(I13),const void*,uint64_t),aggregate_abi_call_targets_I13_module_target(const void*,uint64_t),aggregate_abi_call_targets_I13_env_direct(const void*,uint64_t);
extern uint32_t aggregate_abi_call_targets_I13_send(uint32_t(*)(I13),const void*);
extern I13 aggregate_abi_call_targets_I13_env_target(I13),aggregate_abi_call_targets_I13_env_alt(I13),aggregate_abi_call_targets_I13_alias_target(I13);
typedef struct{uint32_t u;float f;}W8;
_Static_assert(sizeof(W8)==8 && _Alignof(W8)==4,"literal W8 layout");
_Static_assert(offsetof(W8,u)==0,"literal W8.u offset");
_Static_assert(offsetof(W8,f)==4,"literal W8.f offset");
static W8 expected_W8;
static int equal_W8(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,4)==0 && memcmp((const char*)a+4,(const char*)b+4,4)==0;}
W8 aggregate_abi_call_targets_W8_echo(W8 p){choice=1;return p;}
W8 aggregate_abi_call_targets_W8_echo_alt(W8 p){choice=2;return p;}
uint32_t aggregate_abi_call_targets_W8_check(W8 p){return equal_W8(&p,&expected_W8);}
extern W8 aggregate_abi_call_targets_W8_plain(W8),aggregate_abi_call_targets_W8_bridge(W8);
extern W8 aggregate_abi_call_targets_W8_indirect(W8(*)(W8),const void*),aggregate_abi_call_targets_W8_env_indirect(W8(*)(W8),const void*,uint64_t),aggregate_abi_call_targets_W8_alias(W8(*)(W8),const void*),aggregate_abi_call_targets_W8_loaded(const void*,const void*,uint64_t),aggregate_abi_call_targets_W8_choose(uint32_t,W8(*)(W8),W8(*)(W8),const void*,uint64_t),aggregate_abi_call_targets_W8_module_target(const void*,uint64_t),aggregate_abi_call_targets_W8_env_direct(const void*,uint64_t);
extern uint32_t aggregate_abi_call_targets_W8_send(uint32_t(*)(W8),const void*);
extern W8 aggregate_abi_call_targets_W8_env_target(W8),aggregate_abi_call_targets_W8_env_alt(W8),aggregate_abi_call_targets_W8_alias_target(W8);
typedef struct{float f;}S4;
_Static_assert(sizeof(S4)==4 && _Alignof(S4)==4,"literal S4 layout");
_Static_assert(offsetof(S4,f)==0,"literal S4.f offset");
static S4 expected_S4;
static int equal_S4(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,4)==0;}
S4 aggregate_abi_call_targets_S4_echo(S4 p){choice=1;return p;}
S4 aggregate_abi_call_targets_S4_echo_alt(S4 p){choice=2;return p;}
uint32_t aggregate_abi_call_targets_S4_check(S4 p){return equal_S4(&p,&expected_S4);}
extern S4 aggregate_abi_call_targets_S4_plain(S4),aggregate_abi_call_targets_S4_bridge(S4);
extern S4 aggregate_abi_call_targets_S4_indirect(S4(*)(S4),const void*),aggregate_abi_call_targets_S4_env_indirect(S4(*)(S4),const void*,uint64_t),aggregate_abi_call_targets_S4_alias(S4(*)(S4),const void*),aggregate_abi_call_targets_S4_loaded(const void*,const void*,uint64_t),aggregate_abi_call_targets_S4_choose(uint32_t,S4(*)(S4),S4(*)(S4),const void*,uint64_t),aggregate_abi_call_targets_S4_module_target(const void*,uint64_t),aggregate_abi_call_targets_S4_env_direct(const void*,uint64_t);
extern uint32_t aggregate_abi_call_targets_S4_send(uint32_t(*)(S4),const void*);
extern S4 aggregate_abi_call_targets_S4_env_target(S4),aggregate_abi_call_targets_S4_env_alt(S4),aggregate_abi_call_targets_S4_alias_target(S4);
typedef struct{double d;}D8;
_Static_assert(sizeof(D8)==8 && _Alignof(D8)==8,"literal D8 layout");
_Static_assert(offsetof(D8,d)==0,"literal D8.d offset");
static D8 expected_D8;
static int equal_D8(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,8)==0;}
D8 aggregate_abi_call_targets_D8_echo(D8 p){choice=1;return p;}
D8 aggregate_abi_call_targets_D8_echo_alt(D8 p){choice=2;return p;}
uint32_t aggregate_abi_call_targets_D8_check(D8 p){return equal_D8(&p,&expected_D8);}
extern D8 aggregate_abi_call_targets_D8_plain(D8),aggregate_abi_call_targets_D8_bridge(D8);
extern D8 aggregate_abi_call_targets_D8_indirect(D8(*)(D8),const void*),aggregate_abi_call_targets_D8_env_indirect(D8(*)(D8),const void*,uint64_t),aggregate_abi_call_targets_D8_alias(D8(*)(D8),const void*),aggregate_abi_call_targets_D8_loaded(const void*,const void*,uint64_t),aggregate_abi_call_targets_D8_choose(uint32_t,D8(*)(D8),D8(*)(D8),const void*,uint64_t),aggregate_abi_call_targets_D8_module_target(const void*,uint64_t),aggregate_abi_call_targets_D8_env_direct(const void*,uint64_t);
extern uint32_t aggregate_abi_call_targets_D8_send(uint32_t(*)(D8),const void*);
extern D8 aggregate_abi_call_targets_D8_env_target(D8),aggregate_abi_call_targets_D8_env_alt(D8),aggregate_abi_call_targets_D8_alias_target(D8);
typedef struct{float f[3];}SS12;
_Static_assert(sizeof(SS12)==12 && _Alignof(SS12)==4,"literal SS12 layout");
_Static_assert(offsetof(SS12,f[0])==0,"literal SS12.f[0] offset");
_Static_assert(offsetof(SS12,f[1])==4,"literal SS12.f[1] offset");
_Static_assert(offsetof(SS12,f[2])==8,"literal SS12.f[2] offset");
static SS12 expected_SS12;
static int equal_SS12(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,4)==0 && memcmp((const char*)a+4,(const char*)b+4,4)==0 && memcmp((const char*)a+8,(const char*)b+8,4)==0;}
SS12 aggregate_abi_call_targets_SS12_echo(SS12 p){choice=1;return p;}
SS12 aggregate_abi_call_targets_SS12_echo_alt(SS12 p){choice=2;return p;}
uint32_t aggregate_abi_call_targets_SS12_check(SS12 p){return equal_SS12(&p,&expected_SS12);}
extern SS12 aggregate_abi_call_targets_SS12_plain(SS12),aggregate_abi_call_targets_SS12_bridge(SS12);
extern SS12 aggregate_abi_call_targets_SS12_indirect(SS12(*)(SS12),const void*),aggregate_abi_call_targets_SS12_env_indirect(SS12(*)(SS12),const void*,uint64_t),aggregate_abi_call_targets_SS12_alias(SS12(*)(SS12),const void*),aggregate_abi_call_targets_SS12_loaded(const void*,const void*,uint64_t),aggregate_abi_call_targets_SS12_choose(uint32_t,SS12(*)(SS12),SS12(*)(SS12),const void*,uint64_t),aggregate_abi_call_targets_SS12_module_target(const void*,uint64_t),aggregate_abi_call_targets_SS12_env_direct(const void*,uint64_t);
extern uint32_t aggregate_abi_call_targets_SS12_send(uint32_t(*)(SS12),const void*);
extern SS12 aggregate_abi_call_targets_SS12_env_target(SS12),aggregate_abi_call_targets_SS12_env_alt(SS12),aggregate_abi_call_targets_SS12_alias_target(SS12);
typedef struct{double d[2];}DD16;
_Static_assert(sizeof(DD16)==16 && _Alignof(DD16)==8,"literal DD16 layout");
_Static_assert(offsetof(DD16,d[0])==0,"literal DD16.d[0] offset");
_Static_assert(offsetof(DD16,d[1])==8,"literal DD16.d[1] offset");
static DD16 expected_DD16;
static int equal_DD16(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,8)==0 && memcmp((const char*)a+8,(const char*)b+8,8)==0;}
DD16 aggregate_abi_call_targets_DD16_echo(DD16 p){choice=1;return p;}
DD16 aggregate_abi_call_targets_DD16_echo_alt(DD16 p){choice=2;return p;}
uint32_t aggregate_abi_call_targets_DD16_check(DD16 p){return equal_DD16(&p,&expected_DD16);}
extern DD16 aggregate_abi_call_targets_DD16_plain(DD16),aggregate_abi_call_targets_DD16_bridge(DD16);
extern DD16 aggregate_abi_call_targets_DD16_indirect(DD16(*)(DD16),const void*),aggregate_abi_call_targets_DD16_env_indirect(DD16(*)(DD16),const void*,uint64_t),aggregate_abi_call_targets_DD16_alias(DD16(*)(DD16),const void*),aggregate_abi_call_targets_DD16_loaded(const void*,const void*,uint64_t),aggregate_abi_call_targets_DD16_choose(uint32_t,DD16(*)(DD16),DD16(*)(DD16),const void*,uint64_t),aggregate_abi_call_targets_DD16_module_target(const void*,uint64_t),aggregate_abi_call_targets_DD16_env_direct(const void*,uint64_t);
extern uint32_t aggregate_abi_call_targets_DD16_send(uint32_t(*)(DD16),const void*);
extern DD16 aggregate_abi_call_targets_DD16_env_target(DD16),aggregate_abi_call_targets_DD16_env_alt(DD16),aggregate_abi_call_targets_DD16_alias_target(DD16);
typedef struct{uint64_t u;float f;}IS16;
_Static_assert(sizeof(IS16)==16 && _Alignof(IS16)==8,"literal IS16 layout");
_Static_assert(offsetof(IS16,u)==0,"literal IS16.u offset");
_Static_assert(offsetof(IS16,f)==8,"literal IS16.f offset");
static IS16 expected_IS16;
static int equal_IS16(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,8)==0 && memcmp((const char*)a+8,(const char*)b+8,4)==0;}
IS16 aggregate_abi_call_targets_IS16_echo(IS16 p){choice=1;return p;}
IS16 aggregate_abi_call_targets_IS16_echo_alt(IS16 p){choice=2;return p;}
uint32_t aggregate_abi_call_targets_IS16_check(IS16 p){return equal_IS16(&p,&expected_IS16);}
extern IS16 aggregate_abi_call_targets_IS16_plain(IS16),aggregate_abi_call_targets_IS16_bridge(IS16);
extern IS16 aggregate_abi_call_targets_IS16_indirect(IS16(*)(IS16),const void*),aggregate_abi_call_targets_IS16_env_indirect(IS16(*)(IS16),const void*,uint64_t),aggregate_abi_call_targets_IS16_alias(IS16(*)(IS16),const void*),aggregate_abi_call_targets_IS16_loaded(const void*,const void*,uint64_t),aggregate_abi_call_targets_IS16_choose(uint32_t,IS16(*)(IS16),IS16(*)(IS16),const void*,uint64_t),aggregate_abi_call_targets_IS16_module_target(const void*,uint64_t),aggregate_abi_call_targets_IS16_env_direct(const void*,uint64_t);
extern uint32_t aggregate_abi_call_targets_IS16_send(uint32_t(*)(IS16),const void*);
extern IS16 aggregate_abi_call_targets_IS16_env_target(IS16),aggregate_abi_call_targets_IS16_env_alt(IS16),aggregate_abi_call_targets_IS16_alias_target(IS16);
typedef struct{float f;uint64_t u;}SI16;
_Static_assert(sizeof(SI16)==16 && _Alignof(SI16)==8,"literal SI16 layout");
_Static_assert(offsetof(SI16,f)==0,"literal SI16.f offset");
_Static_assert(offsetof(SI16,u)==8,"literal SI16.u offset");
static SI16 expected_SI16;
static int equal_SI16(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,4)==0 && memcmp((const char*)a+8,(const char*)b+8,8)==0;}
SI16 aggregate_abi_call_targets_SI16_echo(SI16 p){choice=1;return p;}
SI16 aggregate_abi_call_targets_SI16_echo_alt(SI16 p){choice=2;return p;}
uint32_t aggregate_abi_call_targets_SI16_check(SI16 p){return equal_SI16(&p,&expected_SI16);}
extern SI16 aggregate_abi_call_targets_SI16_plain(SI16),aggregate_abi_call_targets_SI16_bridge(SI16);
extern SI16 aggregate_abi_call_targets_SI16_indirect(SI16(*)(SI16),const void*),aggregate_abi_call_targets_SI16_env_indirect(SI16(*)(SI16),const void*,uint64_t),aggregate_abi_call_targets_SI16_alias(SI16(*)(SI16),const void*),aggregate_abi_call_targets_SI16_loaded(const void*,const void*,uint64_t),aggregate_abi_call_targets_SI16_choose(uint32_t,SI16(*)(SI16),SI16(*)(SI16),const void*,uint64_t),aggregate_abi_call_targets_SI16_module_target(const void*,uint64_t),aggregate_abi_call_targets_SI16_env_direct(const void*,uint64_t);
extern uint32_t aggregate_abi_call_targets_SI16_send(uint32_t(*)(SI16),const void*);
extern SI16 aggregate_abi_call_targets_SI16_env_target(SI16),aggregate_abi_call_targets_SI16_env_alt(SI16),aggregate_abi_call_targets_SI16_alias_target(SI16);
typedef struct{uint64_t u[2];}II16;
_Static_assert(sizeof(II16)==16 && _Alignof(II16)==8,"literal II16 layout");
_Static_assert(offsetof(II16,u[0])==0,"literal II16.u[0] offset");
_Static_assert(offsetof(II16,u[1])==8,"literal II16.u[1] offset");
static II16 expected_II16;
static int equal_II16(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,8)==0 && memcmp((const char*)a+8,(const char*)b+8,8)==0;}
II16 aggregate_abi_call_targets_II16_echo(II16 p){choice=1;return p;}
II16 aggregate_abi_call_targets_II16_echo_alt(II16 p){choice=2;return p;}
uint32_t aggregate_abi_call_targets_II16_check(II16 p){return equal_II16(&p,&expected_II16);}
extern II16 aggregate_abi_call_targets_II16_plain(II16),aggregate_abi_call_targets_II16_bridge(II16);
extern II16 aggregate_abi_call_targets_II16_indirect(II16(*)(II16),const void*),aggregate_abi_call_targets_II16_env_indirect(II16(*)(II16),const void*,uint64_t),aggregate_abi_call_targets_II16_alias(II16(*)(II16),const void*),aggregate_abi_call_targets_II16_loaded(const void*,const void*,uint64_t),aggregate_abi_call_targets_II16_choose(uint32_t,II16(*)(II16),II16(*)(II16),const void*,uint64_t),aggregate_abi_call_targets_II16_module_target(const void*,uint64_t),aggregate_abi_call_targets_II16_env_direct(const void*,uint64_t);
extern uint32_t aggregate_abi_call_targets_II16_send(uint32_t(*)(II16),const void*);
extern II16 aggregate_abi_call_targets_II16_env_target(II16),aggregate_abi_call_targets_II16_env_alt(II16),aggregate_abi_call_targets_II16_alias_target(II16);
typedef struct{_Alignas(16) float f;}N16;
_Static_assert(sizeof(N16)==16 && _Alignof(N16)==16,"literal N16 layout");
_Static_assert(offsetof(N16,f)==0,"literal N16.f offset");
static N16 expected_N16;
static int equal_N16(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,4)==0;}
N16 aggregate_abi_call_targets_N16_echo(N16 p){choice=1;return p;}
N16 aggregate_abi_call_targets_N16_echo_alt(N16 p){choice=2;return p;}
uint32_t aggregate_abi_call_targets_N16_check(N16 p){return equal_N16(&p,&expected_N16);}
extern N16 aggregate_abi_call_targets_N16_plain(N16),aggregate_abi_call_targets_N16_bridge(N16);
extern N16 aggregate_abi_call_targets_N16_indirect(N16(*)(N16),const void*),aggregate_abi_call_targets_N16_env_indirect(N16(*)(N16),const void*,uint64_t),aggregate_abi_call_targets_N16_alias(N16(*)(N16),const void*),aggregate_abi_call_targets_N16_loaded(const void*,const void*,uint64_t),aggregate_abi_call_targets_N16_choose(uint32_t,N16(*)(N16),N16(*)(N16),const void*,uint64_t),aggregate_abi_call_targets_N16_module_target(const void*,uint64_t),aggregate_abi_call_targets_N16_env_direct(const void*,uint64_t);
extern uint32_t aggregate_abi_call_targets_N16_send(uint32_t(*)(N16),const void*);
extern N16 aggregate_abi_call_targets_N16_env_target(N16),aggregate_abi_call_targets_N16_env_alt(N16),aggregate_abi_call_targets_N16_alias_target(N16);
typedef struct{unsigned char b[23];}M23;
_Static_assert(sizeof(M23)==23 && _Alignof(M23)==1,"literal M23 layout");
_Static_assert(offsetof(M23,b[0])==0,"literal M23.b[0] offset");
_Static_assert(offsetof(M23,b[1])==1,"literal M23.b[1] offset");
_Static_assert(offsetof(M23,b[2])==2,"literal M23.b[2] offset");
_Static_assert(offsetof(M23,b[3])==3,"literal M23.b[3] offset");
_Static_assert(offsetof(M23,b[4])==4,"literal M23.b[4] offset");
_Static_assert(offsetof(M23,b[5])==5,"literal M23.b[5] offset");
_Static_assert(offsetof(M23,b[6])==6,"literal M23.b[6] offset");
_Static_assert(offsetof(M23,b[7])==7,"literal M23.b[7] offset");
_Static_assert(offsetof(M23,b[8])==8,"literal M23.b[8] offset");
_Static_assert(offsetof(M23,b[9])==9,"literal M23.b[9] offset");
_Static_assert(offsetof(M23,b[10])==10,"literal M23.b[10] offset");
_Static_assert(offsetof(M23,b[11])==11,"literal M23.b[11] offset");
_Static_assert(offsetof(M23,b[12])==12,"literal M23.b[12] offset");
_Static_assert(offsetof(M23,b[13])==13,"literal M23.b[13] offset");
_Static_assert(offsetof(M23,b[14])==14,"literal M23.b[14] offset");
_Static_assert(offsetof(M23,b[15])==15,"literal M23.b[15] offset");
_Static_assert(offsetof(M23,b[16])==16,"literal M23.b[16] offset");
_Static_assert(offsetof(M23,b[17])==17,"literal M23.b[17] offset");
_Static_assert(offsetof(M23,b[18])==18,"literal M23.b[18] offset");
_Static_assert(offsetof(M23,b[19])==19,"literal M23.b[19] offset");
_Static_assert(offsetof(M23,b[20])==20,"literal M23.b[20] offset");
_Static_assert(offsetof(M23,b[21])==21,"literal M23.b[21] offset");
_Static_assert(offsetof(M23,b[22])==22,"literal M23.b[22] offset");
static M23 expected_M23;
static int equal_M23(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,1)==0 && memcmp((const char*)a+1,(const char*)b+1,1)==0 && memcmp((const char*)a+2,(const char*)b+2,1)==0 && memcmp((const char*)a+3,(const char*)b+3,1)==0 && memcmp((const char*)a+4,(const char*)b+4,1)==0 && memcmp((const char*)a+5,(const char*)b+5,1)==0 && memcmp((const char*)a+6,(const char*)b+6,1)==0 && memcmp((const char*)a+7,(const char*)b+7,1)==0 && memcmp((const char*)a+8,(const char*)b+8,1)==0 && memcmp((const char*)a+9,(const char*)b+9,1)==0 && memcmp((const char*)a+10,(const char*)b+10,1)==0 && memcmp((const char*)a+11,(const char*)b+11,1)==0 && memcmp((const char*)a+12,(const char*)b+12,1)==0 && memcmp((const char*)a+13,(const char*)b+13,1)==0 && memcmp((const char*)a+14,(const char*)b+14,1)==0 && memcmp((const char*)a+15,(const char*)b+15,1)==0 && memcmp((const char*)a+16,(const char*)b+16,1)==0 && memcmp((const char*)a+17,(const char*)b+17,1)==0 && memcmp((const char*)a+18,(const char*)b+18,1)==0 && memcmp((const char*)a+19,(const char*)b+19,1)==0 && memcmp((const char*)a+20,(const char*)b+20,1)==0 && memcmp((const char*)a+21,(const char*)b+21,1)==0 && memcmp((const char*)a+22,(const char*)b+22,1)==0;}
M23 aggregate_abi_call_targets_M23_echo(M23 p){choice=1;return p;}
M23 aggregate_abi_call_targets_M23_echo_alt(M23 p){choice=2;return p;}
uint32_t aggregate_abi_call_targets_M23_check(M23 p){return equal_M23(&p,&expected_M23);}
extern M23 aggregate_abi_call_targets_M23_plain(M23),aggregate_abi_call_targets_M23_bridge(M23);
extern M23 aggregate_abi_call_targets_M23_indirect(M23(*)(M23),const void*),aggregate_abi_call_targets_M23_env_indirect(M23(*)(M23),const void*,uint64_t),aggregate_abi_call_targets_M23_alias(M23(*)(M23),const void*),aggregate_abi_call_targets_M23_loaded(const void*,const void*,uint64_t),aggregate_abi_call_targets_M23_choose(uint32_t,M23(*)(M23),M23(*)(M23),const void*,uint64_t),aggregate_abi_call_targets_M23_module_target(const void*,uint64_t),aggregate_abi_call_targets_M23_env_direct(const void*,uint64_t);
extern uint32_t aggregate_abi_call_targets_M23_send(uint32_t(*)(M23),const void*);
extern M23 aggregate_abi_call_targets_M23_env_target(M23),aggregate_abi_call_targets_M23_env_alt(M23),aggregate_abi_call_targets_M23_alias_target(M23);
typedef struct{_Alignas(16) uint64_t u[4];}A32;
_Static_assert(sizeof(A32)==32 && _Alignof(A32)==16,"literal A32 layout");
_Static_assert(offsetof(A32,u[0])==0,"literal A32.u[0] offset");
_Static_assert(offsetof(A32,u[1])==8,"literal A32.u[1] offset");
_Static_assert(offsetof(A32,u[2])==16,"literal A32.u[2] offset");
_Static_assert(offsetof(A32,u[3])==24,"literal A32.u[3] offset");
static A32 expected_A32;
static int equal_A32(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,8)==0 && memcmp((const char*)a+8,(const char*)b+8,8)==0 && memcmp((const char*)a+16,(const char*)b+16,8)==0 && memcmp((const char*)a+24,(const char*)b+24,8)==0;}
A32 aggregate_abi_call_targets_A32_echo(A32 p){choice=1;return p;}
A32 aggregate_abi_call_targets_A32_echo_alt(A32 p){choice=2;return p;}
uint32_t aggregate_abi_call_targets_A32_check(A32 p){return equal_A32(&p,&expected_A32);}
extern A32 aggregate_abi_call_targets_A32_plain(A32),aggregate_abi_call_targets_A32_bridge(A32);
extern A32 aggregate_abi_call_targets_A32_indirect(A32(*)(A32),const void*),aggregate_abi_call_targets_A32_env_indirect(A32(*)(A32),const void*,uint64_t),aggregate_abi_call_targets_A32_alias(A32(*)(A32),const void*),aggregate_abi_call_targets_A32_loaded(const void*,const void*,uint64_t),aggregate_abi_call_targets_A32_choose(uint32_t,A32(*)(A32),A32(*)(A32),const void*,uint64_t),aggregate_abi_call_targets_A32_module_target(const void*,uint64_t),aggregate_abi_call_targets_A32_env_direct(const void*,uint64_t);
extern uint32_t aggregate_abi_call_targets_A32_send(uint32_t(*)(A32),const void*);
extern A32 aggregate_abi_call_targets_A32_env_target(A32),aggregate_abi_call_targets_A32_env_alt(A32),aggregate_abi_call_targets_A32_alias_target(A32);
static SI16 pressure_si;static SS12 pressure_ss;static M23 pressure_m;
static const uint64_t pressure_result_bits=UINT64_C(0x7ff0123456789abc);
M23 aggregate_abi_call_targets_pressure_c(uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,SI16 si,M23 m,uint64_t last,double d1,double d2,double d3,double d4,double d5,double d6,double d7,double d8,SS12 ss,double d9){
REQUIRE(a==1&&b==2&&c==3&&d==4&&e==5&&last==99);REQUIRE(d1==1&&d2==2&&d3==3&&d4==4&&d5==5&&d6==6&&d7==7&&d8==8&&d9==9);REQUIRE(equal_SI16(&si,&pressure_si));REQUIRE(equal_SS12(&ss,&pressure_ss));REQUIRE(equal_M23(&m,&pressure_m));m.b[22]^=0xa5;return m;}
extern M23 aggregate_abi_call_targets_pressure(void*,const void*,const void*,const void*,uint64_t),aggregate_abi_call_targets_pressure_bridge(void*,const void*,const void*,const void*,uint64_t);
extern void aggregate_abi_call_targets_pressure_target(void);
double aggregate_abi_call_targets_double_c(SS12 s){REQUIRE(equal_SS12(&s,&pressure_ss));double d;memcpy(&d,&pressure_result_bits,8);return d;}
void aggregate_abi_call_targets_void_c(SS12 s){REQUIRE(equal_SS12(&s,&pressure_ss));++choice;}
extern double aggregate_abi_call_targets_double(void*,const void*,uint64_t);extern void aggregate_abi_call_targets_void(void*,const void*,uint64_t),aggregate_abi_call_targets_double_target(void),aggregate_abi_call_targets_void_target(void);
static void pressure_tests(void){
memset(&pressure_si,0x34,sizeof pressure_si);memset(&pressure_ss,0x56,sizeof pressure_ss);for(unsigned i=0;i<23;++i)pressure_m.b[i]=(unsigned char)(17+i);
aggregate_abi_call_targets_expected_env=UINT64_C(0xdeadbeef71829304);M23 expected=pressure_m;expected.b[22]^=0xa5;
M23 result=aggregate_abi_call_targets_pressure_bridge(aggregate_abi_call_targets_pressure_target,&pressure_si,&pressure_m,&pressure_ss,aggregate_abi_call_targets_expected_env);REQUIRE(equal_M23(&result,&expected));REQUIRE(pressure_m.b[22]==39);
void*mapping;size_t len;unsigned char*g=guarded(23,&mapping,&len);memcpy(g,&pressure_m,23);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);result=aggregate_abi_call_targets_pressure_bridge(aggregate_abi_call_targets_pressure_target,&pressure_si,g,&pressure_ss,aggregate_abi_call_targets_expected_env);REQUIRE(equal_M23(&result,&expected));REQUIRE(equal_M23(g,&pressure_m));REQUIRE(munmap(mapping,len)==0);
double d=aggregate_abi_call_targets_double(aggregate_abi_call_targets_double_target,&pressure_ss,aggregate_abi_call_targets_expected_env);uint64_t u;memcpy(&u,&d,8);REQUIRE(u==pressure_result_bits);unsigned before=choice;aggregate_abi_call_targets_void(aggregate_abi_call_targets_void_target,&pressure_ss,aggregate_abi_call_targets_expected_env);REQUIRE(choice==before+1);
}

extern void* aggregate_abi_call_targets_common_address(void),*aggregate_abi_call_targets_ordinary_address(void);
extern SS12 aggregate_abi_call_targets_quoted(const void*,uint64_t),aggregate_abi_call_targets_common(void*,const void*),aggregate_abi_call_targets_ordinary(void*,const void*),aggregate_abi_call_targets_loop(void*,const void*,uint64_t,uint32_t);
extern uint64_t aggregate_abi_call_targets_varcaller(void*,const void*,uint64_t,...);
static void lifetime_tests(void){SS12 in;memset(&in,0x78,sizeof in);aggregate_abi_call_targets_expected_env=UINT64_C(0x123456789abcdef0);SS12 out=aggregate_abi_call_targets_quoted(&in,aggregate_abi_call_targets_expected_env);REQUIRE(equal_SS12(&in,&out));
aggregate_abi_call_targets_expected_env=(uintptr_t)aggregate_abi_call_targets_common_address();out=aggregate_abi_call_targets_common(aggregate_abi_call_targets_SS12_env_target,&in);REQUIRE(equal_SS12(&in,&out));
aggregate_abi_call_targets_expected_env=(uintptr_t)aggregate_abi_call_targets_ordinary_address();out=aggregate_abi_call_targets_ordinary(aggregate_abi_call_targets_SS12_env_target,&in);REQUIRE(equal_SS12(&in,&out));
uint64_t ua=UINT64_C(0x7ff0123456789abc),ub=UINT64_C(0x8000000000000000);double da,db;memcpy(&da,&ua,8);memcpy(&db,&ub,8);REQUIRE(aggregate_abi_call_targets_varcaller(aggregate_abi_call_targets_SS12_env_target,&in,aggregate_abi_call_targets_expected_env,da,db)==(ua^ub));out=aggregate_abi_call_targets_loop(aggregate_abi_call_targets_SS12_env_target,&in,aggregate_abi_call_targets_expected_env,6);REQUIRE(equal_SS12(&in,&out));}

int main(void){pressure_tests();lifetime_tests();
for(unsigned n=0;n<8;++n){B3 p;memset(&p,0x5a,sizeof p);uint64_t u0=bits[(n+0)%8];memcpy((char*)&p+0,&u0,1);uint64_t u1=bits[(n+1)%8];memcpy((char*)&p+1,&u1,1);uint64_t u2=bits[(n+2)%8];memcpy((char*)&p+2,&u2,1);expected_B3=p;aggregate_abi_call_targets_expected_env=UINT64_C(0xfedcba9876543200)+n;unsigned before=env_seen;
B3(*fp)(B3)=aggregate_abi_call_targets_B3_plain;B3 r=fp(p);REQUIRE(equal_B3(&r,&p));r=aggregate_abi_call_targets_B3_indirect(aggregate_abi_call_targets_B3_echo,&p);REQUIRE(equal_B3(&r,&p));REQUIRE(aggregate_abi_call_targets_B3_send(aggregate_abi_call_targets_B3_check,&p)==1);r=aggregate_abi_call_targets_B3_indirect(fp,&p);REQUIRE(equal_B3(&r,&p));
r=aggregate_abi_call_targets_B3_bridge(p);REQUIRE(equal_B3(&r,&p));REQUIRE(env_seen==before+1);r=aggregate_abi_call_targets_B3_env_direct(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_B3(&r,&p));REQUIRE(env_seen==before+2);r=aggregate_abi_call_targets_B3_module_target(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_B3(&r,&p));REQUIRE(env_seen==before+3);
r=aggregate_abi_call_targets_B3_env_indirect(aggregate_abi_call_targets_B3_env_target,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_B3(&r,&p));r=aggregate_abi_call_targets_B3_alias(aggregate_abi_call_targets_B3_alias_target,&p);REQUIRE(equal_B3(&r,&p));fp=aggregate_abi_call_targets_B3_env_target;r=aggregate_abi_call_targets_B3_loaded(&fp,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_B3(&r,&p));
r=aggregate_abi_call_targets_B3_choose(1,aggregate_abi_call_targets_B3_env_target,aggregate_abi_call_targets_B3_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_B3(&r,&p));REQUIRE(choice==1);r=aggregate_abi_call_targets_B3_choose(0,aggregate_abi_call_targets_B3_env_target,aggregate_abi_call_targets_B3_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_B3(&r,&p));REQUIRE(choice==2);
void*mapping;size_t len;unsigned char*g=guarded(sizeof p,&mapping,&len);memcpy(g,&p,sizeof p);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);r=aggregate_abi_call_targets_B3_env_indirect(aggregate_abi_call_targets_B3_env_target,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_B3(&r,&p));r=aggregate_abi_call_targets_B3_loaded(&fp,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_B3(&r,&p));REQUIRE(equal_B3(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){I13 p;memset(&p,0x5a,sizeof p);uint64_t u0=bits[(n+0)%8];memcpy((char*)&p+0,&u0,1);uint64_t u1=bits[(n+1)%8];memcpy((char*)&p+1,&u1,1);uint64_t u2=bits[(n+2)%8];memcpy((char*)&p+2,&u2,1);uint64_t u3=bits[(n+3)%8];memcpy((char*)&p+3,&u3,1);uint64_t u4=bits[(n+4)%8];memcpy((char*)&p+4,&u4,1);uint64_t u5=bits[(n+5)%8];memcpy((char*)&p+5,&u5,1);uint64_t u6=bits[(n+6)%8];memcpy((char*)&p+6,&u6,1);uint64_t u7=bits[(n+7)%8];memcpy((char*)&p+7,&u7,1);uint64_t u8=bits[(n+8)%8];memcpy((char*)&p+8,&u8,1);uint64_t u9=bits[(n+9)%8];memcpy((char*)&p+9,&u9,1);uint64_t u10=bits[(n+10)%8];memcpy((char*)&p+10,&u10,1);uint64_t u11=bits[(n+11)%8];memcpy((char*)&p+11,&u11,1);uint64_t u12=bits[(n+12)%8];memcpy((char*)&p+12,&u12,1);expected_I13=p;aggregate_abi_call_targets_expected_env=UINT64_C(0xfedcba9876543200)+n;unsigned before=env_seen;
I13(*fp)(I13)=aggregate_abi_call_targets_I13_plain;I13 r=fp(p);REQUIRE(equal_I13(&r,&p));r=aggregate_abi_call_targets_I13_indirect(aggregate_abi_call_targets_I13_echo,&p);REQUIRE(equal_I13(&r,&p));REQUIRE(aggregate_abi_call_targets_I13_send(aggregate_abi_call_targets_I13_check,&p)==1);r=aggregate_abi_call_targets_I13_indirect(fp,&p);REQUIRE(equal_I13(&r,&p));
r=aggregate_abi_call_targets_I13_bridge(p);REQUIRE(equal_I13(&r,&p));REQUIRE(env_seen==before+1);r=aggregate_abi_call_targets_I13_env_direct(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_I13(&r,&p));REQUIRE(env_seen==before+2);r=aggregate_abi_call_targets_I13_module_target(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_I13(&r,&p));REQUIRE(env_seen==before+3);
r=aggregate_abi_call_targets_I13_env_indirect(aggregate_abi_call_targets_I13_env_target,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_I13(&r,&p));r=aggregate_abi_call_targets_I13_alias(aggregate_abi_call_targets_I13_alias_target,&p);REQUIRE(equal_I13(&r,&p));fp=aggregate_abi_call_targets_I13_env_target;r=aggregate_abi_call_targets_I13_loaded(&fp,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_I13(&r,&p));
r=aggregate_abi_call_targets_I13_choose(1,aggregate_abi_call_targets_I13_env_target,aggregate_abi_call_targets_I13_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_I13(&r,&p));REQUIRE(choice==1);r=aggregate_abi_call_targets_I13_choose(0,aggregate_abi_call_targets_I13_env_target,aggregate_abi_call_targets_I13_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_I13(&r,&p));REQUIRE(choice==2);
void*mapping;size_t len;unsigned char*g=guarded(sizeof p,&mapping,&len);memcpy(g,&p,sizeof p);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);r=aggregate_abi_call_targets_I13_env_indirect(aggregate_abi_call_targets_I13_env_target,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_I13(&r,&p));r=aggregate_abi_call_targets_I13_loaded(&fp,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_I13(&r,&p));REQUIRE(equal_I13(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){W8 p;memset(&p,0x5a,sizeof p);uint64_t u0=bits[(n+0)%8];memcpy((char*)&p+0,&u0,4);uint64_t u1=bits[(n+1)%8];memcpy((char*)&p+4,&u1,4);expected_W8=p;aggregate_abi_call_targets_expected_env=UINT64_C(0xfedcba9876543200)+n;unsigned before=env_seen;
W8(*fp)(W8)=aggregate_abi_call_targets_W8_plain;W8 r=fp(p);REQUIRE(equal_W8(&r,&p));r=aggregate_abi_call_targets_W8_indirect(aggregate_abi_call_targets_W8_echo,&p);REQUIRE(equal_W8(&r,&p));REQUIRE(aggregate_abi_call_targets_W8_send(aggregate_abi_call_targets_W8_check,&p)==1);r=aggregate_abi_call_targets_W8_indirect(fp,&p);REQUIRE(equal_W8(&r,&p));
r=aggregate_abi_call_targets_W8_bridge(p);REQUIRE(equal_W8(&r,&p));REQUIRE(env_seen==before+1);r=aggregate_abi_call_targets_W8_env_direct(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_W8(&r,&p));REQUIRE(env_seen==before+2);r=aggregate_abi_call_targets_W8_module_target(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_W8(&r,&p));REQUIRE(env_seen==before+3);
r=aggregate_abi_call_targets_W8_env_indirect(aggregate_abi_call_targets_W8_env_target,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_W8(&r,&p));r=aggregate_abi_call_targets_W8_alias(aggregate_abi_call_targets_W8_alias_target,&p);REQUIRE(equal_W8(&r,&p));fp=aggregate_abi_call_targets_W8_env_target;r=aggregate_abi_call_targets_W8_loaded(&fp,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_W8(&r,&p));
r=aggregate_abi_call_targets_W8_choose(1,aggregate_abi_call_targets_W8_env_target,aggregate_abi_call_targets_W8_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_W8(&r,&p));REQUIRE(choice==1);r=aggregate_abi_call_targets_W8_choose(0,aggregate_abi_call_targets_W8_env_target,aggregate_abi_call_targets_W8_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_W8(&r,&p));REQUIRE(choice==2);
void*mapping;size_t len;unsigned char*g=guarded(sizeof p,&mapping,&len);memcpy(g,&p,sizeof p);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);r=aggregate_abi_call_targets_W8_env_indirect(aggregate_abi_call_targets_W8_env_target,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_W8(&r,&p));r=aggregate_abi_call_targets_W8_loaded(&fp,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_W8(&r,&p));REQUIRE(equal_W8(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){S4 p;memset(&p,0x5a,sizeof p);uint64_t u0=bits[(n+0)%8];memcpy((char*)&p+0,&u0,4);expected_S4=p;aggregate_abi_call_targets_expected_env=UINT64_C(0xfedcba9876543200)+n;unsigned before=env_seen;
S4(*fp)(S4)=aggregate_abi_call_targets_S4_plain;S4 r=fp(p);REQUIRE(equal_S4(&r,&p));r=aggregate_abi_call_targets_S4_indirect(aggregate_abi_call_targets_S4_echo,&p);REQUIRE(equal_S4(&r,&p));REQUIRE(aggregate_abi_call_targets_S4_send(aggregate_abi_call_targets_S4_check,&p)==1);r=aggregate_abi_call_targets_S4_indirect(fp,&p);REQUIRE(equal_S4(&r,&p));
r=aggregate_abi_call_targets_S4_bridge(p);REQUIRE(equal_S4(&r,&p));REQUIRE(env_seen==before+1);r=aggregate_abi_call_targets_S4_env_direct(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_S4(&r,&p));REQUIRE(env_seen==before+2);r=aggregate_abi_call_targets_S4_module_target(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_S4(&r,&p));REQUIRE(env_seen==before+3);
r=aggregate_abi_call_targets_S4_env_indirect(aggregate_abi_call_targets_S4_env_target,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_S4(&r,&p));r=aggregate_abi_call_targets_S4_alias(aggregate_abi_call_targets_S4_alias_target,&p);REQUIRE(equal_S4(&r,&p));fp=aggregate_abi_call_targets_S4_env_target;r=aggregate_abi_call_targets_S4_loaded(&fp,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_S4(&r,&p));
r=aggregate_abi_call_targets_S4_choose(1,aggregate_abi_call_targets_S4_env_target,aggregate_abi_call_targets_S4_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_S4(&r,&p));REQUIRE(choice==1);r=aggregate_abi_call_targets_S4_choose(0,aggregate_abi_call_targets_S4_env_target,aggregate_abi_call_targets_S4_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_S4(&r,&p));REQUIRE(choice==2);
void*mapping;size_t len;unsigned char*g=guarded(sizeof p,&mapping,&len);memcpy(g,&p,sizeof p);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);r=aggregate_abi_call_targets_S4_env_indirect(aggregate_abi_call_targets_S4_env_target,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_S4(&r,&p));r=aggregate_abi_call_targets_S4_loaded(&fp,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_S4(&r,&p));REQUIRE(equal_S4(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){D8 p;memset(&p,0x5a,sizeof p);uint64_t u0=bits[(n+0)%8];memcpy((char*)&p+0,&u0,8);expected_D8=p;aggregate_abi_call_targets_expected_env=UINT64_C(0xfedcba9876543200)+n;unsigned before=env_seen;
D8(*fp)(D8)=aggregate_abi_call_targets_D8_plain;D8 r=fp(p);REQUIRE(equal_D8(&r,&p));r=aggregate_abi_call_targets_D8_indirect(aggregate_abi_call_targets_D8_echo,&p);REQUIRE(equal_D8(&r,&p));REQUIRE(aggregate_abi_call_targets_D8_send(aggregate_abi_call_targets_D8_check,&p)==1);r=aggregate_abi_call_targets_D8_indirect(fp,&p);REQUIRE(equal_D8(&r,&p));
r=aggregate_abi_call_targets_D8_bridge(p);REQUIRE(equal_D8(&r,&p));REQUIRE(env_seen==before+1);r=aggregate_abi_call_targets_D8_env_direct(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_D8(&r,&p));REQUIRE(env_seen==before+2);r=aggregate_abi_call_targets_D8_module_target(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_D8(&r,&p));REQUIRE(env_seen==before+3);
r=aggregate_abi_call_targets_D8_env_indirect(aggregate_abi_call_targets_D8_env_target,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_D8(&r,&p));r=aggregate_abi_call_targets_D8_alias(aggregate_abi_call_targets_D8_alias_target,&p);REQUIRE(equal_D8(&r,&p));fp=aggregate_abi_call_targets_D8_env_target;r=aggregate_abi_call_targets_D8_loaded(&fp,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_D8(&r,&p));
r=aggregate_abi_call_targets_D8_choose(1,aggregate_abi_call_targets_D8_env_target,aggregate_abi_call_targets_D8_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_D8(&r,&p));REQUIRE(choice==1);r=aggregate_abi_call_targets_D8_choose(0,aggregate_abi_call_targets_D8_env_target,aggregate_abi_call_targets_D8_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_D8(&r,&p));REQUIRE(choice==2);
void*mapping;size_t len;unsigned char*g=guarded(sizeof p,&mapping,&len);memcpy(g,&p,sizeof p);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);r=aggregate_abi_call_targets_D8_env_indirect(aggregate_abi_call_targets_D8_env_target,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_D8(&r,&p));r=aggregate_abi_call_targets_D8_loaded(&fp,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_D8(&r,&p));REQUIRE(equal_D8(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){SS12 p;memset(&p,0x5a,sizeof p);uint64_t u0=bits[(n+0)%8];memcpy((char*)&p+0,&u0,4);uint64_t u1=bits[(n+1)%8];memcpy((char*)&p+4,&u1,4);uint64_t u2=bits[(n+2)%8];memcpy((char*)&p+8,&u2,4);expected_SS12=p;aggregate_abi_call_targets_expected_env=UINT64_C(0xfedcba9876543200)+n;unsigned before=env_seen;
SS12(*fp)(SS12)=aggregate_abi_call_targets_SS12_plain;SS12 r=fp(p);REQUIRE(equal_SS12(&r,&p));r=aggregate_abi_call_targets_SS12_indirect(aggregate_abi_call_targets_SS12_echo,&p);REQUIRE(equal_SS12(&r,&p));REQUIRE(aggregate_abi_call_targets_SS12_send(aggregate_abi_call_targets_SS12_check,&p)==1);r=aggregate_abi_call_targets_SS12_indirect(fp,&p);REQUIRE(equal_SS12(&r,&p));
r=aggregate_abi_call_targets_SS12_bridge(p);REQUIRE(equal_SS12(&r,&p));REQUIRE(env_seen==before+1);r=aggregate_abi_call_targets_SS12_env_direct(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_SS12(&r,&p));REQUIRE(env_seen==before+2);r=aggregate_abi_call_targets_SS12_module_target(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_SS12(&r,&p));REQUIRE(env_seen==before+3);
r=aggregate_abi_call_targets_SS12_env_indirect(aggregate_abi_call_targets_SS12_env_target,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_SS12(&r,&p));r=aggregate_abi_call_targets_SS12_alias(aggregate_abi_call_targets_SS12_alias_target,&p);REQUIRE(equal_SS12(&r,&p));fp=aggregate_abi_call_targets_SS12_env_target;r=aggregate_abi_call_targets_SS12_loaded(&fp,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_SS12(&r,&p));
r=aggregate_abi_call_targets_SS12_choose(1,aggregate_abi_call_targets_SS12_env_target,aggregate_abi_call_targets_SS12_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_SS12(&r,&p));REQUIRE(choice==1);r=aggregate_abi_call_targets_SS12_choose(0,aggregate_abi_call_targets_SS12_env_target,aggregate_abi_call_targets_SS12_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_SS12(&r,&p));REQUIRE(choice==2);
void*mapping;size_t len;unsigned char*g=guarded(sizeof p,&mapping,&len);memcpy(g,&p,sizeof p);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);r=aggregate_abi_call_targets_SS12_env_indirect(aggregate_abi_call_targets_SS12_env_target,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_SS12(&r,&p));r=aggregate_abi_call_targets_SS12_loaded(&fp,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_SS12(&r,&p));REQUIRE(equal_SS12(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){DD16 p;memset(&p,0x5a,sizeof p);uint64_t u0=bits[(n+0)%8];memcpy((char*)&p+0,&u0,8);uint64_t u1=bits[(n+1)%8];memcpy((char*)&p+8,&u1,8);expected_DD16=p;aggregate_abi_call_targets_expected_env=UINT64_C(0xfedcba9876543200)+n;unsigned before=env_seen;
DD16(*fp)(DD16)=aggregate_abi_call_targets_DD16_plain;DD16 r=fp(p);REQUIRE(equal_DD16(&r,&p));r=aggregate_abi_call_targets_DD16_indirect(aggregate_abi_call_targets_DD16_echo,&p);REQUIRE(equal_DD16(&r,&p));REQUIRE(aggregate_abi_call_targets_DD16_send(aggregate_abi_call_targets_DD16_check,&p)==1);r=aggregate_abi_call_targets_DD16_indirect(fp,&p);REQUIRE(equal_DD16(&r,&p));
r=aggregate_abi_call_targets_DD16_bridge(p);REQUIRE(equal_DD16(&r,&p));REQUIRE(env_seen==before+1);r=aggregate_abi_call_targets_DD16_env_direct(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_DD16(&r,&p));REQUIRE(env_seen==before+2);r=aggregate_abi_call_targets_DD16_module_target(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_DD16(&r,&p));REQUIRE(env_seen==before+3);
r=aggregate_abi_call_targets_DD16_env_indirect(aggregate_abi_call_targets_DD16_env_target,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_DD16(&r,&p));r=aggregate_abi_call_targets_DD16_alias(aggregate_abi_call_targets_DD16_alias_target,&p);REQUIRE(equal_DD16(&r,&p));fp=aggregate_abi_call_targets_DD16_env_target;r=aggregate_abi_call_targets_DD16_loaded(&fp,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_DD16(&r,&p));
r=aggregate_abi_call_targets_DD16_choose(1,aggregate_abi_call_targets_DD16_env_target,aggregate_abi_call_targets_DD16_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_DD16(&r,&p));REQUIRE(choice==1);r=aggregate_abi_call_targets_DD16_choose(0,aggregate_abi_call_targets_DD16_env_target,aggregate_abi_call_targets_DD16_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_DD16(&r,&p));REQUIRE(choice==2);
void*mapping;size_t len;unsigned char*g=guarded(sizeof p,&mapping,&len);memcpy(g,&p,sizeof p);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);r=aggregate_abi_call_targets_DD16_env_indirect(aggregate_abi_call_targets_DD16_env_target,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_DD16(&r,&p));r=aggregate_abi_call_targets_DD16_loaded(&fp,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_DD16(&r,&p));REQUIRE(equal_DD16(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){IS16 p;memset(&p,0x5a,sizeof p);uint64_t u0=bits[(n+0)%8];memcpy((char*)&p+0,&u0,8);uint64_t u1=bits[(n+1)%8];memcpy((char*)&p+8,&u1,4);expected_IS16=p;aggregate_abi_call_targets_expected_env=UINT64_C(0xfedcba9876543200)+n;unsigned before=env_seen;
IS16(*fp)(IS16)=aggregate_abi_call_targets_IS16_plain;IS16 r=fp(p);REQUIRE(equal_IS16(&r,&p));r=aggregate_abi_call_targets_IS16_indirect(aggregate_abi_call_targets_IS16_echo,&p);REQUIRE(equal_IS16(&r,&p));REQUIRE(aggregate_abi_call_targets_IS16_send(aggregate_abi_call_targets_IS16_check,&p)==1);r=aggregate_abi_call_targets_IS16_indirect(fp,&p);REQUIRE(equal_IS16(&r,&p));
r=aggregate_abi_call_targets_IS16_bridge(p);REQUIRE(equal_IS16(&r,&p));REQUIRE(env_seen==before+1);r=aggregate_abi_call_targets_IS16_env_direct(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_IS16(&r,&p));REQUIRE(env_seen==before+2);r=aggregate_abi_call_targets_IS16_module_target(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_IS16(&r,&p));REQUIRE(env_seen==before+3);
r=aggregate_abi_call_targets_IS16_env_indirect(aggregate_abi_call_targets_IS16_env_target,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_IS16(&r,&p));r=aggregate_abi_call_targets_IS16_alias(aggregate_abi_call_targets_IS16_alias_target,&p);REQUIRE(equal_IS16(&r,&p));fp=aggregate_abi_call_targets_IS16_env_target;r=aggregate_abi_call_targets_IS16_loaded(&fp,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_IS16(&r,&p));
r=aggregate_abi_call_targets_IS16_choose(1,aggregate_abi_call_targets_IS16_env_target,aggregate_abi_call_targets_IS16_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_IS16(&r,&p));REQUIRE(choice==1);r=aggregate_abi_call_targets_IS16_choose(0,aggregate_abi_call_targets_IS16_env_target,aggregate_abi_call_targets_IS16_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_IS16(&r,&p));REQUIRE(choice==2);
void*mapping;size_t len;unsigned char*g=guarded(sizeof p,&mapping,&len);memcpy(g,&p,sizeof p);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);r=aggregate_abi_call_targets_IS16_env_indirect(aggregate_abi_call_targets_IS16_env_target,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_IS16(&r,&p));r=aggregate_abi_call_targets_IS16_loaded(&fp,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_IS16(&r,&p));REQUIRE(equal_IS16(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){SI16 p;memset(&p,0x5a,sizeof p);uint64_t u0=bits[(n+0)%8];memcpy((char*)&p+0,&u0,4);uint64_t u1=bits[(n+1)%8];memcpy((char*)&p+8,&u1,8);expected_SI16=p;aggregate_abi_call_targets_expected_env=UINT64_C(0xfedcba9876543200)+n;unsigned before=env_seen;
SI16(*fp)(SI16)=aggregate_abi_call_targets_SI16_plain;SI16 r=fp(p);REQUIRE(equal_SI16(&r,&p));r=aggregate_abi_call_targets_SI16_indirect(aggregate_abi_call_targets_SI16_echo,&p);REQUIRE(equal_SI16(&r,&p));REQUIRE(aggregate_abi_call_targets_SI16_send(aggregate_abi_call_targets_SI16_check,&p)==1);r=aggregate_abi_call_targets_SI16_indirect(fp,&p);REQUIRE(equal_SI16(&r,&p));
r=aggregate_abi_call_targets_SI16_bridge(p);REQUIRE(equal_SI16(&r,&p));REQUIRE(env_seen==before+1);r=aggregate_abi_call_targets_SI16_env_direct(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_SI16(&r,&p));REQUIRE(env_seen==before+2);r=aggregate_abi_call_targets_SI16_module_target(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_SI16(&r,&p));REQUIRE(env_seen==before+3);
r=aggregate_abi_call_targets_SI16_env_indirect(aggregate_abi_call_targets_SI16_env_target,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_SI16(&r,&p));r=aggregate_abi_call_targets_SI16_alias(aggregate_abi_call_targets_SI16_alias_target,&p);REQUIRE(equal_SI16(&r,&p));fp=aggregate_abi_call_targets_SI16_env_target;r=aggregate_abi_call_targets_SI16_loaded(&fp,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_SI16(&r,&p));
r=aggregate_abi_call_targets_SI16_choose(1,aggregate_abi_call_targets_SI16_env_target,aggregate_abi_call_targets_SI16_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_SI16(&r,&p));REQUIRE(choice==1);r=aggregate_abi_call_targets_SI16_choose(0,aggregate_abi_call_targets_SI16_env_target,aggregate_abi_call_targets_SI16_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_SI16(&r,&p));REQUIRE(choice==2);
void*mapping;size_t len;unsigned char*g=guarded(sizeof p,&mapping,&len);memcpy(g,&p,sizeof p);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);r=aggregate_abi_call_targets_SI16_env_indirect(aggregate_abi_call_targets_SI16_env_target,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_SI16(&r,&p));r=aggregate_abi_call_targets_SI16_loaded(&fp,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_SI16(&r,&p));REQUIRE(equal_SI16(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){II16 p;memset(&p,0x5a,sizeof p);uint64_t u0=bits[(n+0)%8];memcpy((char*)&p+0,&u0,8);uint64_t u1=bits[(n+1)%8];memcpy((char*)&p+8,&u1,8);expected_II16=p;aggregate_abi_call_targets_expected_env=UINT64_C(0xfedcba9876543200)+n;unsigned before=env_seen;
II16(*fp)(II16)=aggregate_abi_call_targets_II16_plain;II16 r=fp(p);REQUIRE(equal_II16(&r,&p));r=aggregate_abi_call_targets_II16_indirect(aggregate_abi_call_targets_II16_echo,&p);REQUIRE(equal_II16(&r,&p));REQUIRE(aggregate_abi_call_targets_II16_send(aggregate_abi_call_targets_II16_check,&p)==1);r=aggregate_abi_call_targets_II16_indirect(fp,&p);REQUIRE(equal_II16(&r,&p));
r=aggregate_abi_call_targets_II16_bridge(p);REQUIRE(equal_II16(&r,&p));REQUIRE(env_seen==before+1);r=aggregate_abi_call_targets_II16_env_direct(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_II16(&r,&p));REQUIRE(env_seen==before+2);r=aggregate_abi_call_targets_II16_module_target(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_II16(&r,&p));REQUIRE(env_seen==before+3);
r=aggregate_abi_call_targets_II16_env_indirect(aggregate_abi_call_targets_II16_env_target,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_II16(&r,&p));r=aggregate_abi_call_targets_II16_alias(aggregate_abi_call_targets_II16_alias_target,&p);REQUIRE(equal_II16(&r,&p));fp=aggregate_abi_call_targets_II16_env_target;r=aggregate_abi_call_targets_II16_loaded(&fp,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_II16(&r,&p));
r=aggregate_abi_call_targets_II16_choose(1,aggregate_abi_call_targets_II16_env_target,aggregate_abi_call_targets_II16_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_II16(&r,&p));REQUIRE(choice==1);r=aggregate_abi_call_targets_II16_choose(0,aggregate_abi_call_targets_II16_env_target,aggregate_abi_call_targets_II16_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_II16(&r,&p));REQUIRE(choice==2);
void*mapping;size_t len;unsigned char*g=guarded(sizeof p,&mapping,&len);memcpy(g,&p,sizeof p);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);r=aggregate_abi_call_targets_II16_env_indirect(aggregate_abi_call_targets_II16_env_target,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_II16(&r,&p));r=aggregate_abi_call_targets_II16_loaded(&fp,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_II16(&r,&p));REQUIRE(equal_II16(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){N16 p;memset(&p,0x5a,sizeof p);uint64_t u0=bits[(n+0)%8];memcpy((char*)&p+0,&u0,4);expected_N16=p;aggregate_abi_call_targets_expected_env=UINT64_C(0xfedcba9876543200)+n;unsigned before=env_seen;
N16(*fp)(N16)=aggregate_abi_call_targets_N16_plain;N16 r=fp(p);REQUIRE(equal_N16(&r,&p));r=aggregate_abi_call_targets_N16_indirect(aggregate_abi_call_targets_N16_echo,&p);REQUIRE(equal_N16(&r,&p));REQUIRE(aggregate_abi_call_targets_N16_send(aggregate_abi_call_targets_N16_check,&p)==1);r=aggregate_abi_call_targets_N16_indirect(fp,&p);REQUIRE(equal_N16(&r,&p));
r=aggregate_abi_call_targets_N16_bridge(p);REQUIRE(equal_N16(&r,&p));REQUIRE(env_seen==before+1);r=aggregate_abi_call_targets_N16_env_direct(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_N16(&r,&p));REQUIRE(env_seen==before+2);r=aggregate_abi_call_targets_N16_module_target(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_N16(&r,&p));REQUIRE(env_seen==before+3);
r=aggregate_abi_call_targets_N16_env_indirect(aggregate_abi_call_targets_N16_env_target,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_N16(&r,&p));r=aggregate_abi_call_targets_N16_alias(aggregate_abi_call_targets_N16_alias_target,&p);REQUIRE(equal_N16(&r,&p));fp=aggregate_abi_call_targets_N16_env_target;r=aggregate_abi_call_targets_N16_loaded(&fp,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_N16(&r,&p));
r=aggregate_abi_call_targets_N16_choose(1,aggregate_abi_call_targets_N16_env_target,aggregate_abi_call_targets_N16_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_N16(&r,&p));REQUIRE(choice==1);r=aggregate_abi_call_targets_N16_choose(0,aggregate_abi_call_targets_N16_env_target,aggregate_abi_call_targets_N16_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_N16(&r,&p));REQUIRE(choice==2);
void*mapping;size_t len;unsigned char*g=guarded(sizeof p,&mapping,&len);memcpy(g,&p,sizeof p);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);r=aggregate_abi_call_targets_N16_env_indirect(aggregate_abi_call_targets_N16_env_target,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_N16(&r,&p));r=aggregate_abi_call_targets_N16_loaded(&fp,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_N16(&r,&p));REQUIRE(equal_N16(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){M23 p;memset(&p,0x5a,sizeof p);uint64_t u0=bits[(n+0)%8];memcpy((char*)&p+0,&u0,1);uint64_t u1=bits[(n+1)%8];memcpy((char*)&p+1,&u1,1);uint64_t u2=bits[(n+2)%8];memcpy((char*)&p+2,&u2,1);uint64_t u3=bits[(n+3)%8];memcpy((char*)&p+3,&u3,1);uint64_t u4=bits[(n+4)%8];memcpy((char*)&p+4,&u4,1);uint64_t u5=bits[(n+5)%8];memcpy((char*)&p+5,&u5,1);uint64_t u6=bits[(n+6)%8];memcpy((char*)&p+6,&u6,1);uint64_t u7=bits[(n+7)%8];memcpy((char*)&p+7,&u7,1);uint64_t u8=bits[(n+8)%8];memcpy((char*)&p+8,&u8,1);uint64_t u9=bits[(n+9)%8];memcpy((char*)&p+9,&u9,1);uint64_t u10=bits[(n+10)%8];memcpy((char*)&p+10,&u10,1);uint64_t u11=bits[(n+11)%8];memcpy((char*)&p+11,&u11,1);uint64_t u12=bits[(n+12)%8];memcpy((char*)&p+12,&u12,1);uint64_t u13=bits[(n+13)%8];memcpy((char*)&p+13,&u13,1);uint64_t u14=bits[(n+14)%8];memcpy((char*)&p+14,&u14,1);uint64_t u15=bits[(n+15)%8];memcpy((char*)&p+15,&u15,1);uint64_t u16=bits[(n+16)%8];memcpy((char*)&p+16,&u16,1);uint64_t u17=bits[(n+17)%8];memcpy((char*)&p+17,&u17,1);uint64_t u18=bits[(n+18)%8];memcpy((char*)&p+18,&u18,1);uint64_t u19=bits[(n+19)%8];memcpy((char*)&p+19,&u19,1);uint64_t u20=bits[(n+20)%8];memcpy((char*)&p+20,&u20,1);uint64_t u21=bits[(n+21)%8];memcpy((char*)&p+21,&u21,1);uint64_t u22=bits[(n+22)%8];memcpy((char*)&p+22,&u22,1);expected_M23=p;aggregate_abi_call_targets_expected_env=UINT64_C(0xfedcba9876543200)+n;unsigned before=env_seen;
M23(*fp)(M23)=aggregate_abi_call_targets_M23_plain;M23 r=fp(p);REQUIRE(equal_M23(&r,&p));r=aggregate_abi_call_targets_M23_indirect(aggregate_abi_call_targets_M23_echo,&p);REQUIRE(equal_M23(&r,&p));REQUIRE(aggregate_abi_call_targets_M23_send(aggregate_abi_call_targets_M23_check,&p)==1);r=aggregate_abi_call_targets_M23_indirect(fp,&p);REQUIRE(equal_M23(&r,&p));
r=aggregate_abi_call_targets_M23_bridge(p);REQUIRE(equal_M23(&r,&p));REQUIRE(env_seen==before+1);r=aggregate_abi_call_targets_M23_env_direct(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_M23(&r,&p));REQUIRE(env_seen==before+2);r=aggregate_abi_call_targets_M23_module_target(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_M23(&r,&p));REQUIRE(env_seen==before+3);
r=aggregate_abi_call_targets_M23_env_indirect(aggregate_abi_call_targets_M23_env_target,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_M23(&r,&p));r=aggregate_abi_call_targets_M23_alias(aggregate_abi_call_targets_M23_alias_target,&p);REQUIRE(equal_M23(&r,&p));fp=aggregate_abi_call_targets_M23_env_target;r=aggregate_abi_call_targets_M23_loaded(&fp,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_M23(&r,&p));
r=aggregate_abi_call_targets_M23_choose(1,aggregate_abi_call_targets_M23_env_target,aggregate_abi_call_targets_M23_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_M23(&r,&p));REQUIRE(choice==1);r=aggregate_abi_call_targets_M23_choose(0,aggregate_abi_call_targets_M23_env_target,aggregate_abi_call_targets_M23_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_M23(&r,&p));REQUIRE(choice==2);
void*mapping;size_t len;unsigned char*g=guarded(sizeof p,&mapping,&len);memcpy(g,&p,sizeof p);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);r=aggregate_abi_call_targets_M23_env_indirect(aggregate_abi_call_targets_M23_env_target,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_M23(&r,&p));r=aggregate_abi_call_targets_M23_loaded(&fp,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_M23(&r,&p));REQUIRE(equal_M23(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){A32 p;memset(&p,0x5a,sizeof p);uint64_t u0=bits[(n+0)%8];memcpy((char*)&p+0,&u0,8);uint64_t u1=bits[(n+1)%8];memcpy((char*)&p+8,&u1,8);uint64_t u2=bits[(n+2)%8];memcpy((char*)&p+16,&u2,8);uint64_t u3=bits[(n+3)%8];memcpy((char*)&p+24,&u3,8);expected_A32=p;aggregate_abi_call_targets_expected_env=UINT64_C(0xfedcba9876543200)+n;unsigned before=env_seen;
A32(*fp)(A32)=aggregate_abi_call_targets_A32_plain;A32 r=fp(p);REQUIRE(equal_A32(&r,&p));r=aggregate_abi_call_targets_A32_indirect(aggregate_abi_call_targets_A32_echo,&p);REQUIRE(equal_A32(&r,&p));REQUIRE(aggregate_abi_call_targets_A32_send(aggregate_abi_call_targets_A32_check,&p)==1);r=aggregate_abi_call_targets_A32_indirect(fp,&p);REQUIRE(equal_A32(&r,&p));
r=aggregate_abi_call_targets_A32_bridge(p);REQUIRE(equal_A32(&r,&p));REQUIRE(env_seen==before+1);r=aggregate_abi_call_targets_A32_env_direct(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_A32(&r,&p));REQUIRE(env_seen==before+2);r=aggregate_abi_call_targets_A32_module_target(&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_A32(&r,&p));REQUIRE(env_seen==before+3);
r=aggregate_abi_call_targets_A32_env_indirect(aggregate_abi_call_targets_A32_env_target,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_A32(&r,&p));r=aggregate_abi_call_targets_A32_alias(aggregate_abi_call_targets_A32_alias_target,&p);REQUIRE(equal_A32(&r,&p));fp=aggregate_abi_call_targets_A32_env_target;r=aggregate_abi_call_targets_A32_loaded(&fp,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_A32(&r,&p));
r=aggregate_abi_call_targets_A32_choose(1,aggregate_abi_call_targets_A32_env_target,aggregate_abi_call_targets_A32_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_A32(&r,&p));REQUIRE(choice==1);r=aggregate_abi_call_targets_A32_choose(0,aggregate_abi_call_targets_A32_env_target,aggregate_abi_call_targets_A32_env_alt,&p,aggregate_abi_call_targets_expected_env);REQUIRE(equal_A32(&r,&p));REQUIRE(choice==2);
void*mapping;size_t len;unsigned char*g=guarded(sizeof p,&mapping,&len);memcpy(g,&p,sizeof p);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);r=aggregate_abi_call_targets_A32_env_indirect(aggregate_abi_call_targets_A32_env_target,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_A32(&r,&p));r=aggregate_abi_call_targets_A32_loaded(&fp,g,aggregate_abi_call_targets_expected_env);REQUIRE(equal_A32(&r,&p));REQUIRE(equal_A32(g,&p));REQUIRE(munmap(mapping,len)==0);}

printf("aggregate call targets %u independent assertions passed\n",checks);return 0;}
