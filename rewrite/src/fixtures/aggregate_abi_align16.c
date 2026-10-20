#define _GNU_SOURCE
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
static unsigned checks;
#define REQUIRE(c) do{++checks;if(!(c)){fprintf(stderr,"align16 line%d\n",__LINE__);abort();}}while(0)
static const uint64_t bits[]={UINT64_C(0x8000000080000000),UINT64_C(0x7ff000007f800000),UINT64_C(0xfff00000ff800000),UINT64_C(0x7ff812347fc12345),UINT64_C(0x7ff012347fa12345),UINT64_C(1),UINT64_C(0x3ff000003f800001),UINT64_C(0x7fffffff7fffffff)};
typedef struct{_Alignas(16) float f;}Child;
extern int aggregate_abi_align16_preserved(void(*)(void),const void*,unsigned char*);
static unsigned char* guarded(void**mapping,size_t*len){long pg=sysconf(_SC_PAGESIZE);REQUIRE(pg>=4096);*len=(size_t)pg*3;*mapping=mmap(NULL,*len,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);REQUIRE(*mapping!=MAP_FAILED);REQUIRE(mprotect((char*)*mapping+pg,(size_t)pg,PROT_READ|PROT_WRITE)==0);return (unsigned char*)*mapping+2*pg-16;}

typedef struct{_Alignas(16) uint8_t b;}B;
_Static_assert(sizeof(B)==16 && _Alignof(B)==16,"independent B storage");
_Static_assert(offsetof(B,b)==0,"independent B.b offset");
extern uint32_t aggregate_abi_align16_B_address(B);
static B expected_B;
static int equal_B(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,1)==0;}
uint32_t aggregate_abi_align16_B_check(B p){return equal_B(&p,&expected_B);}
B aggregate_abi_align16_B_make(const void*p){B v;memcpy(&v,p,16);return v;}
extern B aggregate_abi_align16_B_echo(B),aggregate_abi_align16_B_ret(const void*);
extern uint32_t aggregate_abi_align16_B_send(const void*),aggregate_abi_align16_B_roundtrip(const void*),aggregate_abi_align16_B_mutate(B,B);
typedef struct{_Alignas(16) uint16_t h;}H;
_Static_assert(sizeof(H)==16 && _Alignof(H)==16,"independent H storage");
_Static_assert(offsetof(H,h)==0,"independent H.h offset");
extern uint32_t aggregate_abi_align16_H_address(H);
static H expected_H;
static int equal_H(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,2)==0;}
uint32_t aggregate_abi_align16_H_check(H p){return equal_H(&p,&expected_H);}
H aggregate_abi_align16_H_make(const void*p){H v;memcpy(&v,p,16);return v;}
extern H aggregate_abi_align16_H_echo(H),aggregate_abi_align16_H_ret(const void*);
extern uint32_t aggregate_abi_align16_H_send(const void*),aggregate_abi_align16_H_roundtrip(const void*),aggregate_abi_align16_H_mutate(H,H);
typedef struct{_Alignas(16) uint32_t u;float f;}W;
_Static_assert(sizeof(W)==16 && _Alignof(W)==16,"independent W storage");
_Static_assert(offsetof(W,u)==0,"independent W.u offset");
_Static_assert(offsetof(W,f)==4,"independent W.f offset");
extern uint32_t aggregate_abi_align16_W_address(W);
static W expected_W;
static int equal_W(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,4)==0 && memcmp((const char*)a+4,(const char*)b+4,4)==0;}
uint32_t aggregate_abi_align16_W_check(W p){return equal_W(&p,&expected_W);}
W aggregate_abi_align16_W_make(const void*p){W v;memcpy(&v,p,16);return v;}
extern W aggregate_abi_align16_W_echo(W),aggregate_abi_align16_W_ret(const void*);
extern uint32_t aggregate_abi_align16_W_send(const void*),aggregate_abi_align16_W_roundtrip(const void*),aggregate_abi_align16_W_mutate(W,W);
typedef struct{_Alignas(16) uint64_t u;}L;
_Static_assert(sizeof(L)==16 && _Alignof(L)==16,"independent L storage");
_Static_assert(offsetof(L,u)==0,"independent L.u offset");
extern uint32_t aggregate_abi_align16_L_address(L);
static L expected_L;
static int equal_L(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,8)==0;}
uint32_t aggregate_abi_align16_L_check(L p){return equal_L(&p,&expected_L);}
L aggregate_abi_align16_L_make(const void*p){L v;memcpy(&v,p,16);return v;}
extern L aggregate_abi_align16_L_echo(L),aggregate_abi_align16_L_ret(const void*);
extern uint32_t aggregate_abi_align16_L_send(const void*),aggregate_abi_align16_L_roundtrip(const void*),aggregate_abi_align16_L_mutate(L,L);
typedef struct{_Alignas(16) float f;}S;
_Static_assert(sizeof(S)==16 && _Alignof(S)==16,"independent S storage");
_Static_assert(offsetof(S,f)==0,"independent S.f offset");
extern uint32_t aggregate_abi_align16_S_address(S);
static S expected_S;
static int equal_S(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,4)==0;}
uint32_t aggregate_abi_align16_S_check(S p){return equal_S(&p,&expected_S);}
S aggregate_abi_align16_S_make(const void*p){S v;memcpy(&v,p,16);return v;}
extern S aggregate_abi_align16_S_echo(S),aggregate_abi_align16_S_ret(const void*);
extern uint32_t aggregate_abi_align16_S_send(const void*),aggregate_abi_align16_S_roundtrip(const void*),aggregate_abi_align16_S_mutate(S,S);
typedef struct{_Alignas(16) double d;}D;
_Static_assert(sizeof(D)==16 && _Alignof(D)==16,"independent D storage");
_Static_assert(offsetof(D,d)==0,"independent D.d offset");
extern uint32_t aggregate_abi_align16_D_address(D);
static D expected_D;
static int equal_D(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,8)==0;}
uint32_t aggregate_abi_align16_D_check(D p){return equal_D(&p,&expected_D);}
D aggregate_abi_align16_D_make(const void*p){D v;memcpy(&v,p,16);return v;}
extern D aggregate_abi_align16_D_echo(D),aggregate_abi_align16_D_ret(const void*);
extern uint32_t aggregate_abi_align16_D_send(const void*),aggregate_abi_align16_D_roundtrip(const void*),aggregate_abi_align16_D_mutate(D,D);
typedef struct{_Alignas(16) float f[3];}SS3;
_Static_assert(sizeof(SS3)==16 && _Alignof(SS3)==16,"independent SS3 storage");
_Static_assert(offsetof(SS3,f[0])==0,"independent SS3.f[0] offset");
_Static_assert(offsetof(SS3,f[1])==4,"independent SS3.f[1] offset");
_Static_assert(offsetof(SS3,f[2])==8,"independent SS3.f[2] offset");
extern uint32_t aggregate_abi_align16_SS3_address(SS3);
static SS3 expected_SS3;
static int equal_SS3(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,4)==0 && memcmp((const char*)a+4,(const char*)b+4,4)==0 && memcmp((const char*)a+8,(const char*)b+8,4)==0;}
uint32_t aggregate_abi_align16_SS3_check(SS3 p){return equal_SS3(&p,&expected_SS3);}
SS3 aggregate_abi_align16_SS3_make(const void*p){SS3 v;memcpy(&v,p,16);return v;}
extern SS3 aggregate_abi_align16_SS3_echo(SS3),aggregate_abi_align16_SS3_ret(const void*);
extern uint32_t aggregate_abi_align16_SS3_send(const void*),aggregate_abi_align16_SS3_roundtrip(const void*),aggregate_abi_align16_SS3_mutate(SS3,SS3);
typedef struct{_Alignas(16) float f[4];}SS4;
_Static_assert(sizeof(SS4)==16 && _Alignof(SS4)==16,"independent SS4 storage");
_Static_assert(offsetof(SS4,f[0])==0,"independent SS4.f[0] offset");
_Static_assert(offsetof(SS4,f[1])==4,"independent SS4.f[1] offset");
_Static_assert(offsetof(SS4,f[2])==8,"independent SS4.f[2] offset");
_Static_assert(offsetof(SS4,f[3])==12,"independent SS4.f[3] offset");
extern uint32_t aggregate_abi_align16_SS4_address(SS4);
static SS4 expected_SS4;
static int equal_SS4(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,4)==0 && memcmp((const char*)a+4,(const char*)b+4,4)==0 && memcmp((const char*)a+8,(const char*)b+8,4)==0 && memcmp((const char*)a+12,(const char*)b+12,4)==0;}
uint32_t aggregate_abi_align16_SS4_check(SS4 p){return equal_SS4(&p,&expected_SS4);}
SS4 aggregate_abi_align16_SS4_make(const void*p){SS4 v;memcpy(&v,p,16);return v;}
extern SS4 aggregate_abi_align16_SS4_echo(SS4),aggregate_abi_align16_SS4_ret(const void*);
extern uint32_t aggregate_abi_align16_SS4_send(const void*),aggregate_abi_align16_SS4_roundtrip(const void*),aggregate_abi_align16_SS4_mutate(SS4,SS4);
typedef struct{_Alignas(16) double d[2];}DD;
_Static_assert(sizeof(DD)==16 && _Alignof(DD)==16,"independent DD storage");
_Static_assert(offsetof(DD,d[0])==0,"independent DD.d[0] offset");
_Static_assert(offsetof(DD,d[1])==8,"independent DD.d[1] offset");
extern uint32_t aggregate_abi_align16_DD_address(DD);
static DD expected_DD;
static int equal_DD(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,8)==0 && memcmp((const char*)a+8,(const char*)b+8,8)==0;}
uint32_t aggregate_abi_align16_DD_check(DD p){return equal_DD(&p,&expected_DD);}
DD aggregate_abi_align16_DD_make(const void*p){DD v;memcpy(&v,p,16);return v;}
extern DD aggregate_abi_align16_DD_echo(DD),aggregate_abi_align16_DD_ret(const void*);
extern uint32_t aggregate_abi_align16_DD_send(const void*),aggregate_abi_align16_DD_roundtrip(const void*),aggregate_abi_align16_DD_mutate(DD,DD);
typedef struct{_Alignas(16) float f;uint64_t u;}SI;
_Static_assert(sizeof(SI)==16 && _Alignof(SI)==16,"independent SI storage");
_Static_assert(offsetof(SI,f)==0,"independent SI.f offset");
_Static_assert(offsetof(SI,u)==8,"independent SI.u offset");
extern uint32_t aggregate_abi_align16_SI_address(SI);
static SI expected_SI;
static int equal_SI(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,4)==0 && memcmp((const char*)a+8,(const char*)b+8,8)==0;}
uint32_t aggregate_abi_align16_SI_check(SI p){return equal_SI(&p,&expected_SI);}
SI aggregate_abi_align16_SI_make(const void*p){SI v;memcpy(&v,p,16);return v;}
extern SI aggregate_abi_align16_SI_echo(SI),aggregate_abi_align16_SI_ret(const void*);
extern uint32_t aggregate_abi_align16_SI_send(const void*),aggregate_abi_align16_SI_roundtrip(const void*),aggregate_abi_align16_SI_mutate(SI,SI);
typedef struct{_Alignas(16) uint64_t u;float f;}IS;
_Static_assert(sizeof(IS)==16 && _Alignof(IS)==16,"independent IS storage");
_Static_assert(offsetof(IS,u)==0,"independent IS.u offset");
_Static_assert(offsetof(IS,f)==8,"independent IS.f offset");
extern uint32_t aggregate_abi_align16_IS_address(IS);
static IS expected_IS;
static int equal_IS(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,8)==0 && memcmp((const char*)a+8,(const char*)b+8,4)==0;}
uint32_t aggregate_abi_align16_IS_check(IS p){return equal_IS(&p,&expected_IS);}
IS aggregate_abi_align16_IS_make(const void*p){IS v;memcpy(&v,p,16);return v;}
extern IS aggregate_abi_align16_IS_echo(IS),aggregate_abi_align16_IS_ret(const void*);
extern uint32_t aggregate_abi_align16_IS_send(const void*),aggregate_abi_align16_IS_roundtrip(const void*),aggregate_abi_align16_IS_mutate(IS,IS);
typedef struct{_Alignas(16) uint64_t u[2];}II;
_Static_assert(sizeof(II)==16 && _Alignof(II)==16,"independent II storage");
_Static_assert(offsetof(II,u[0])==0,"independent II.u[0] offset");
_Static_assert(offsetof(II,u[1])==8,"independent II.u[1] offset");
extern uint32_t aggregate_abi_align16_II_address(II);
static II expected_II;
static int equal_II(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,8)==0 && memcmp((const char*)a+8,(const char*)b+8,8)==0;}
uint32_t aggregate_abi_align16_II_check(II p){return equal_II(&p,&expected_II);}
II aggregate_abi_align16_II_make(const void*p){II v;memcpy(&v,p,16);return v;}
extern II aggregate_abi_align16_II_echo(II),aggregate_abi_align16_II_ret(const void*);
extern uint32_t aggregate_abi_align16_II_send(const void*),aggregate_abi_align16_II_roundtrip(const void*),aggregate_abi_align16_II_mutate(II,II);
typedef struct{Child child;}N;
_Static_assert(sizeof(N)==16 && _Alignof(N)==16,"independent N storage");
_Static_assert(offsetof(N,child.f)==0,"independent N.child.f offset");
extern uint32_t aggregate_abi_align16_N_address(N);
static N expected_N;
static int equal_N(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,4)==0;}
uint32_t aggregate_abi_align16_N_check(N p){return equal_N(&p,&expected_N);}
N aggregate_abi_align16_N_make(const void*p){N v;memcpy(&v,p,16);return v;}
extern N aggregate_abi_align16_N_echo(N),aggregate_abi_align16_N_ret(const void*);
extern uint32_t aggregate_abi_align16_N_send(const void*),aggregate_abi_align16_N_roundtrip(const void*),aggregate_abi_align16_N_mutate(N,N);
static double frombits(uint64_t u){double d;memcpy(&d,&u,8);return d;}
static uint64_t rawbits(double d){uint64_t u;memcpy(&u,&d,8);return u;}
static uint32_t rawsingle(float f){uint32_t u;memcpy(&u,&f,4);return u;}
extern uint32_t aggregate_abi_align16_pressure_gp(const void*);
extern uint32_t aggregate_abi_align16_pressure_gp_incoming(uint64_t g0,uint64_t g1,uint64_t g2,uint64_t g3,uint64_t g4,uint64_t g5,uint64_t spill,W v,uint64_t final,double after);
uint32_t aggregate_abi_align16_pressure_gp_check(uint64_t g0,uint64_t g1,uint64_t g2,uint64_t g3,uint64_t g4,uint64_t g5,uint64_t spill,W v,uint64_t final,double after){return g0==1 && g1==2 && g2==3 && g3==4 && g4==5 && g5==6 && spill==7 && v.u==287454020 && rawsingle(v.f)==2141266757 && ((uintptr_t)&v%16)==0 && final==99 && rawbits(after)==UINT64_C(9218888453225749180);}
extern uint32_t aggregate_abi_align16_pressure_ione(const void*);
extern uint32_t aggregate_abi_align16_pressure_ione_incoming(uint64_t g0,uint64_t g1,uint64_t g2,uint64_t g3,uint64_t g4,W v,uint64_t final,double after);
uint32_t aggregate_abi_align16_pressure_ione_check(uint64_t g0,uint64_t g1,uint64_t g2,uint64_t g3,uint64_t g4,W v,uint64_t final,double after){return g0==1 && g1==2 && g2==3 && g3==4 && g4==5 && v.u==287454020 && rawsingle(v.f)==2141266757 && ((uintptr_t)&v%16)==0 && final==99 && rawbits(after)==UINT64_C(9218888453225749180);}
extern uint32_t aggregate_abi_align16_pressure_sone(const void*);
extern uint32_t aggregate_abi_align16_pressure_sone_incoming(double d0,double d1,double d2,double d3,double d4,double d5,double d6,S v,double after,uint64_t final);
uint32_t aggregate_abi_align16_pressure_sone_check(double d0,double d1,double d2,double d3,double d4,double d5,double d6,S v,double after,uint64_t final){return rawbits(d0)==UINT64_C(4607182418800017408) && rawbits(d1)==UINT64_C(4607182418800017409) && rawbits(d2)==UINT64_C(4607182418800017410) && rawbits(d3)==UINT64_C(4607182418800017411) && rawbits(d4)==UINT64_C(4607182418800017412) && rawbits(d5)==UINT64_C(4607182418800017413) && rawbits(d6)==UINT64_C(4607182418800017414) && rawsingle(v.f)==2141266757 && ((uintptr_t)&v%16)==0 && rawbits(after)==UINT64_C(9218888453225749180) && final==99;}
extern uint32_t aggregate_abi_align16_pressure_gpfail(const void*);
extern uint32_t aggregate_abi_align16_pressure_gpfail_incoming(uint64_t g0,uint64_t g1,uint64_t g2,uint64_t g3,uint64_t g4,uint64_t g5,SI v,uint64_t final,double after);
uint32_t aggregate_abi_align16_pressure_gpfail_check(uint64_t g0,uint64_t g1,uint64_t g2,uint64_t g3,uint64_t g4,uint64_t g5,SI v,uint64_t final,double after){return g0==1 && g1==2 && g2==3 && g3==4 && g4==5 && g5==6 && v.u==UINT64_C(6153737369425722316) && rawsingle(v.f)==2141266757 && ((uintptr_t)&v%16)==0 && final==99 && rawbits(after)==UINT64_C(9218888453225749180);}
extern uint32_t aggregate_abi_align16_pressure_ssefail(const void*);
extern uint32_t aggregate_abi_align16_pressure_ssefail_incoming(double d0,double d1,double d2,double d3,double d4,double d5,double d6,double d7,IS v,double after,uint64_t final);
uint32_t aggregate_abi_align16_pressure_ssefail_check(double d0,double d1,double d2,double d3,double d4,double d5,double d6,double d7,IS v,double after,uint64_t final){return rawbits(d0)==UINT64_C(4607182418800017408) && rawbits(d1)==UINT64_C(4607182418800017409) && rawbits(d2)==UINT64_C(4607182418800017410) && rawbits(d3)==UINT64_C(4607182418800017411) && rawbits(d4)==UINT64_C(4607182418800017412) && rawbits(d5)==UINT64_C(4607182418800017413) && rawbits(d6)==UINT64_C(4607182418800017414) && rawbits(d7)==UINT64_C(4607182418800017415) && v.u==UINT64_C(6153737369425722316) && rawsingle(v.f)==2141266757 && ((uintptr_t)&v%16)==0 && rawbits(after)==UINT64_C(9218888453225749180) && final==99;}
typedef struct{_Alignas(16) uint64_t u[4];}M;
_Static_assert(sizeof(M)==32 && _Alignof(M)==16,"independent MEMORY32");
extern uint32_t aggregate_abi_align16_loop(const void*);
extern uint32_t aggregate_abi_align16_dynamic(const void*),aggregate_abi_align16_sites(const void*);
extern S aggregate_abi_align16_recurse(S,uint32_t);
extern M aggregate_abi_align16_memory(const void*,S);
extern uint32_t aggregate_abi_align16_memory_roundtrip(const void*,S);
static M expected_M;
M aggregate_abi_align16_memory_make(const void*src,S p){M result;memcpy(&result,src,32);if(!aggregate_abi_align16_S_check(p))abort();return result;}
uint32_t aggregate_abi_align16_memory_check(M p){return memcmp(&p,&expected_M,32)==0 && ((uintptr_t)&p%16)==0;}
int main(void){{W v;memset(&v,0x5a,16);uint32_t f=2141266757;memcpy(&v.f,&f,4);v.u=287454020;REQUIRE(aggregate_abi_align16_pressure_gp(&v)==1);REQUIRE(aggregate_abi_align16_pressure_gp_incoming(1,2,3,4,5,6,7,v,99,frombits(UINT64_C(9218888453225749180)))==1);}{W v;memset(&v,0x5a,16);uint32_t f=2141266757;memcpy(&v.f,&f,4);v.u=287454020;REQUIRE(aggregate_abi_align16_pressure_ione(&v)==1);REQUIRE(aggregate_abi_align16_pressure_ione_incoming(1,2,3,4,5,v,99,frombits(UINT64_C(9218888453225749180)))==1);}{S v;memset(&v,0x5a,16);uint32_t f=2141266757;memcpy(&v.f,&f,4);REQUIRE(aggregate_abi_align16_pressure_sone(&v)==1);REQUIRE(aggregate_abi_align16_pressure_sone_incoming(frombits(UINT64_C(4607182418800017408)),frombits(UINT64_C(4607182418800017409)),frombits(UINT64_C(4607182418800017410)),frombits(UINT64_C(4607182418800017411)),frombits(UINT64_C(4607182418800017412)),frombits(UINT64_C(4607182418800017413)),frombits(UINT64_C(4607182418800017414)),v,frombits(UINT64_C(9218888453225749180)),99)==1);}{SI v;memset(&v,0x5a,16);uint32_t f=2141266757;memcpy(&v.f,&f,4);v.u=UINT64_C(6153737369425722316);REQUIRE(aggregate_abi_align16_pressure_gpfail(&v)==1);REQUIRE(aggregate_abi_align16_pressure_gpfail_incoming(1,2,3,4,5,6,v,99,frombits(UINT64_C(9218888453225749180)))==1);}{IS v;memset(&v,0x5a,16);uint32_t f=2141266757;memcpy(&v.f,&f,4);v.u=UINT64_C(6153737369425722316);REQUIRE(aggregate_abi_align16_pressure_ssefail(&v)==1);REQUIRE(aggregate_abi_align16_pressure_ssefail_incoming(frombits(UINT64_C(4607182418800017408)),frombits(UINT64_C(4607182418800017409)),frombits(UINT64_C(4607182418800017410)),frombits(UINT64_C(4607182418800017411)),frombits(UINT64_C(4607182418800017412)),frombits(UINT64_C(4607182418800017413)),frombits(UINT64_C(4607182418800017414)),frombits(UINT64_C(4607182418800017415)),v,frombits(UINT64_C(9218888453225749180)),99)==1);}
for(unsigned n=0;n<8;++n){B p;memset(&p,0x5a,16);uint64_t v0=bits[(n+0)%8];memcpy((char*)&p+0,&v0,1);expected_B=p;REQUIRE(aggregate_abi_align16_B_address(p)==0);B e=aggregate_abi_align16_B_echo(p);REQUIRE(equal_B(&e,&p));REQUIRE(aggregate_abi_align16_B_send(&p)==1);REQUIRE(aggregate_abi_align16_B_roundtrip(&p)==1);REQUIRE(aggregate_abi_align16_B_mutate(p,p)==1);REQUIRE(equal_B(&p,&expected_B));
unsigned char registers[32],copy[16];memset(copy,0xa5,16);REQUIRE(aggregate_abi_align16_preserved((void(*)(void))aggregate_abi_align16_B_ret,&p,registers)==1);memcpy(copy+0,registers+0,8);REQUIRE(equal_B(copy,&p));
void*mapping;size_t len;unsigned char*g=guarded(&mapping,&len);REQUIRE(((uintptr_t)g%16)==0);memcpy(g,&p,16);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);B gval;memcpy(&gval,g,16);e=aggregate_abi_align16_B_echo(gval);REQUIRE(equal_B(&e,&p));REQUIRE(aggregate_abi_align16_B_send(g)==1);REQUIRE(aggregate_abi_align16_B_roundtrip(g)==1);REQUIRE(aggregate_abi_align16_B_mutate(gval,gval)==1);REQUIRE(equal_B(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){H p;memset(&p,0x5a,16);uint64_t v0=bits[(n+0)%8];memcpy((char*)&p+0,&v0,2);expected_H=p;REQUIRE(aggregate_abi_align16_H_address(p)==0);H e=aggregate_abi_align16_H_echo(p);REQUIRE(equal_H(&e,&p));REQUIRE(aggregate_abi_align16_H_send(&p)==1);REQUIRE(aggregate_abi_align16_H_roundtrip(&p)==1);REQUIRE(aggregate_abi_align16_H_mutate(p,p)==1);REQUIRE(equal_H(&p,&expected_H));
unsigned char registers[32],copy[16];memset(copy,0xa5,16);REQUIRE(aggregate_abi_align16_preserved((void(*)(void))aggregate_abi_align16_H_ret,&p,registers)==1);memcpy(copy+0,registers+0,8);REQUIRE(equal_H(copy,&p));
void*mapping;size_t len;unsigned char*g=guarded(&mapping,&len);REQUIRE(((uintptr_t)g%16)==0);memcpy(g,&p,16);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);H gval;memcpy(&gval,g,16);e=aggregate_abi_align16_H_echo(gval);REQUIRE(equal_H(&e,&p));REQUIRE(aggregate_abi_align16_H_send(g)==1);REQUIRE(aggregate_abi_align16_H_roundtrip(g)==1);REQUIRE(aggregate_abi_align16_H_mutate(gval,gval)==1);REQUIRE(equal_H(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){W p;memset(&p,0x5a,16);uint64_t v0=bits[(n+0)%8];memcpy((char*)&p+0,&v0,4);uint64_t v1=bits[(n+1)%8];memcpy((char*)&p+4,&v1,4);expected_W=p;REQUIRE(aggregate_abi_align16_W_address(p)==0);W e=aggregate_abi_align16_W_echo(p);REQUIRE(equal_W(&e,&p));REQUIRE(aggregate_abi_align16_W_send(&p)==1);REQUIRE(aggregate_abi_align16_W_roundtrip(&p)==1);REQUIRE(aggregate_abi_align16_W_mutate(p,p)==1);REQUIRE(equal_W(&p,&expected_W));
unsigned char registers[32],copy[16];memset(copy,0xa5,16);REQUIRE(aggregate_abi_align16_preserved((void(*)(void))aggregate_abi_align16_W_ret,&p,registers)==1);memcpy(copy+0,registers+0,8);REQUIRE(equal_W(copy,&p));
void*mapping;size_t len;unsigned char*g=guarded(&mapping,&len);REQUIRE(((uintptr_t)g%16)==0);memcpy(g,&p,16);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);W gval;memcpy(&gval,g,16);e=aggregate_abi_align16_W_echo(gval);REQUIRE(equal_W(&e,&p));REQUIRE(aggregate_abi_align16_W_send(g)==1);REQUIRE(aggregate_abi_align16_W_roundtrip(g)==1);REQUIRE(aggregate_abi_align16_W_mutate(gval,gval)==1);REQUIRE(equal_W(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){L p;memset(&p,0x5a,16);uint64_t v0=bits[(n+0)%8];memcpy((char*)&p+0,&v0,8);expected_L=p;REQUIRE(aggregate_abi_align16_L_address(p)==0);L e=aggregate_abi_align16_L_echo(p);REQUIRE(equal_L(&e,&p));REQUIRE(aggregate_abi_align16_L_send(&p)==1);REQUIRE(aggregate_abi_align16_L_roundtrip(&p)==1);REQUIRE(aggregate_abi_align16_L_mutate(p,p)==1);REQUIRE(equal_L(&p,&expected_L));
unsigned char registers[32],copy[16];memset(copy,0xa5,16);REQUIRE(aggregate_abi_align16_preserved((void(*)(void))aggregate_abi_align16_L_ret,&p,registers)==1);memcpy(copy+0,registers+0,8);REQUIRE(equal_L(copy,&p));
void*mapping;size_t len;unsigned char*g=guarded(&mapping,&len);REQUIRE(((uintptr_t)g%16)==0);memcpy(g,&p,16);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);L gval;memcpy(&gval,g,16);e=aggregate_abi_align16_L_echo(gval);REQUIRE(equal_L(&e,&p));REQUIRE(aggregate_abi_align16_L_send(g)==1);REQUIRE(aggregate_abi_align16_L_roundtrip(g)==1);REQUIRE(aggregate_abi_align16_L_mutate(gval,gval)==1);REQUIRE(equal_L(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){S p;memset(&p,0x5a,16);uint64_t v0=bits[(n+0)%8];memcpy((char*)&p+0,&v0,4);expected_S=p;REQUIRE(aggregate_abi_align16_S_address(p)==0);S e=aggregate_abi_align16_S_echo(p);REQUIRE(equal_S(&e,&p));REQUIRE(aggregate_abi_align16_S_send(&p)==1);REQUIRE(aggregate_abi_align16_S_roundtrip(&p)==1);REQUIRE(aggregate_abi_align16_S_mutate(p,p)==1);REQUIRE(equal_S(&p,&expected_S));
unsigned char registers[32],copy[16];memset(copy,0xa5,16);REQUIRE(aggregate_abi_align16_preserved((void(*)(void))aggregate_abi_align16_S_ret,&p,registers)==1);memcpy(copy+0,registers+16,8);REQUIRE(equal_S(copy,&p));
void*mapping;size_t len;unsigned char*g=guarded(&mapping,&len);REQUIRE(((uintptr_t)g%16)==0);memcpy(g,&p,16);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);S gval;memcpy(&gval,g,16);e=aggregate_abi_align16_S_echo(gval);REQUIRE(equal_S(&e,&p));REQUIRE(aggregate_abi_align16_S_send(g)==1);REQUIRE(aggregate_abi_align16_S_roundtrip(g)==1);REQUIRE(aggregate_abi_align16_S_mutate(gval,gval)==1);REQUIRE(equal_S(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){D p;memset(&p,0x5a,16);uint64_t v0=bits[(n+0)%8];memcpy((char*)&p+0,&v0,8);expected_D=p;REQUIRE(aggregate_abi_align16_D_address(p)==0);D e=aggregate_abi_align16_D_echo(p);REQUIRE(equal_D(&e,&p));REQUIRE(aggregate_abi_align16_D_send(&p)==1);REQUIRE(aggregate_abi_align16_D_roundtrip(&p)==1);REQUIRE(aggregate_abi_align16_D_mutate(p,p)==1);REQUIRE(equal_D(&p,&expected_D));
unsigned char registers[32],copy[16];memset(copy,0xa5,16);REQUIRE(aggregate_abi_align16_preserved((void(*)(void))aggregate_abi_align16_D_ret,&p,registers)==1);memcpy(copy+0,registers+16,8);REQUIRE(equal_D(copy,&p));
void*mapping;size_t len;unsigned char*g=guarded(&mapping,&len);REQUIRE(((uintptr_t)g%16)==0);memcpy(g,&p,16);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);D gval;memcpy(&gval,g,16);e=aggregate_abi_align16_D_echo(gval);REQUIRE(equal_D(&e,&p));REQUIRE(aggregate_abi_align16_D_send(g)==1);REQUIRE(aggregate_abi_align16_D_roundtrip(g)==1);REQUIRE(aggregate_abi_align16_D_mutate(gval,gval)==1);REQUIRE(equal_D(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){SS3 p;memset(&p,0x5a,16);uint64_t v0=bits[(n+0)%8];memcpy((char*)&p+0,&v0,4);uint64_t v1=bits[(n+1)%8];memcpy((char*)&p+4,&v1,4);uint64_t v2=bits[(n+2)%8];memcpy((char*)&p+8,&v2,4);expected_SS3=p;REQUIRE(aggregate_abi_align16_SS3_address(p)==0);SS3 e=aggregate_abi_align16_SS3_echo(p);REQUIRE(equal_SS3(&e,&p));REQUIRE(aggregate_abi_align16_SS3_send(&p)==1);REQUIRE(aggregate_abi_align16_SS3_roundtrip(&p)==1);REQUIRE(aggregate_abi_align16_SS3_mutate(p,p)==1);REQUIRE(equal_SS3(&p,&expected_SS3));
unsigned char registers[32],copy[16];memset(copy,0xa5,16);REQUIRE(aggregate_abi_align16_preserved((void(*)(void))aggregate_abi_align16_SS3_ret,&p,registers)==1);memcpy(copy+0,registers+16,8);memcpy(copy+8,registers+24,8);REQUIRE(equal_SS3(copy,&p));
void*mapping;size_t len;unsigned char*g=guarded(&mapping,&len);REQUIRE(((uintptr_t)g%16)==0);memcpy(g,&p,16);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);SS3 gval;memcpy(&gval,g,16);e=aggregate_abi_align16_SS3_echo(gval);REQUIRE(equal_SS3(&e,&p));REQUIRE(aggregate_abi_align16_SS3_send(g)==1);REQUIRE(aggregate_abi_align16_SS3_roundtrip(g)==1);REQUIRE(aggregate_abi_align16_SS3_mutate(gval,gval)==1);REQUIRE(equal_SS3(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){SS4 p;memset(&p,0x5a,16);uint64_t v0=bits[(n+0)%8];memcpy((char*)&p+0,&v0,4);uint64_t v1=bits[(n+1)%8];memcpy((char*)&p+4,&v1,4);uint64_t v2=bits[(n+2)%8];memcpy((char*)&p+8,&v2,4);uint64_t v3=bits[(n+3)%8];memcpy((char*)&p+12,&v3,4);expected_SS4=p;REQUIRE(aggregate_abi_align16_SS4_address(p)==0);SS4 e=aggregate_abi_align16_SS4_echo(p);REQUIRE(equal_SS4(&e,&p));REQUIRE(aggregate_abi_align16_SS4_send(&p)==1);REQUIRE(aggregate_abi_align16_SS4_roundtrip(&p)==1);REQUIRE(aggregate_abi_align16_SS4_mutate(p,p)==1);REQUIRE(equal_SS4(&p,&expected_SS4));
unsigned char registers[32],copy[16];memset(copy,0xa5,16);REQUIRE(aggregate_abi_align16_preserved((void(*)(void))aggregate_abi_align16_SS4_ret,&p,registers)==1);memcpy(copy+0,registers+16,8);memcpy(copy+8,registers+24,8);REQUIRE(equal_SS4(copy,&p));
void*mapping;size_t len;unsigned char*g=guarded(&mapping,&len);REQUIRE(((uintptr_t)g%16)==0);memcpy(g,&p,16);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);SS4 gval;memcpy(&gval,g,16);e=aggregate_abi_align16_SS4_echo(gval);REQUIRE(equal_SS4(&e,&p));REQUIRE(aggregate_abi_align16_SS4_send(g)==1);REQUIRE(aggregate_abi_align16_SS4_roundtrip(g)==1);REQUIRE(aggregate_abi_align16_SS4_mutate(gval,gval)==1);REQUIRE(equal_SS4(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){DD p;memset(&p,0x5a,16);uint64_t v0=bits[(n+0)%8];memcpy((char*)&p+0,&v0,8);uint64_t v1=bits[(n+1)%8];memcpy((char*)&p+8,&v1,8);expected_DD=p;REQUIRE(aggregate_abi_align16_DD_address(p)==0);DD e=aggregate_abi_align16_DD_echo(p);REQUIRE(equal_DD(&e,&p));REQUIRE(aggregate_abi_align16_DD_send(&p)==1);REQUIRE(aggregate_abi_align16_DD_roundtrip(&p)==1);REQUIRE(aggregate_abi_align16_DD_mutate(p,p)==1);REQUIRE(equal_DD(&p,&expected_DD));
unsigned char registers[32],copy[16];memset(copy,0xa5,16);REQUIRE(aggregate_abi_align16_preserved((void(*)(void))aggregate_abi_align16_DD_ret,&p,registers)==1);memcpy(copy+0,registers+16,8);memcpy(copy+8,registers+24,8);REQUIRE(equal_DD(copy,&p));
void*mapping;size_t len;unsigned char*g=guarded(&mapping,&len);REQUIRE(((uintptr_t)g%16)==0);memcpy(g,&p,16);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);DD gval;memcpy(&gval,g,16);e=aggregate_abi_align16_DD_echo(gval);REQUIRE(equal_DD(&e,&p));REQUIRE(aggregate_abi_align16_DD_send(g)==1);REQUIRE(aggregate_abi_align16_DD_roundtrip(g)==1);REQUIRE(aggregate_abi_align16_DD_mutate(gval,gval)==1);REQUIRE(equal_DD(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){SI p;memset(&p,0x5a,16);uint64_t v0=bits[(n+0)%8];memcpy((char*)&p+0,&v0,4);uint64_t v1=bits[(n+1)%8];memcpy((char*)&p+8,&v1,8);expected_SI=p;REQUIRE(aggregate_abi_align16_SI_address(p)==0);SI e=aggregate_abi_align16_SI_echo(p);REQUIRE(equal_SI(&e,&p));REQUIRE(aggregate_abi_align16_SI_send(&p)==1);REQUIRE(aggregate_abi_align16_SI_roundtrip(&p)==1);REQUIRE(aggregate_abi_align16_SI_mutate(p,p)==1);REQUIRE(equal_SI(&p,&expected_SI));
unsigned char registers[32],copy[16];memset(copy,0xa5,16);REQUIRE(aggregate_abi_align16_preserved((void(*)(void))aggregate_abi_align16_SI_ret,&p,registers)==1);memcpy(copy+0,registers+16,8);memcpy(copy+8,registers+0,8);REQUIRE(equal_SI(copy,&p));
void*mapping;size_t len;unsigned char*g=guarded(&mapping,&len);REQUIRE(((uintptr_t)g%16)==0);memcpy(g,&p,16);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);SI gval;memcpy(&gval,g,16);e=aggregate_abi_align16_SI_echo(gval);REQUIRE(equal_SI(&e,&p));REQUIRE(aggregate_abi_align16_SI_send(g)==1);REQUIRE(aggregate_abi_align16_SI_roundtrip(g)==1);REQUIRE(aggregate_abi_align16_SI_mutate(gval,gval)==1);REQUIRE(equal_SI(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){IS p;memset(&p,0x5a,16);uint64_t v0=bits[(n+0)%8];memcpy((char*)&p+0,&v0,8);uint64_t v1=bits[(n+1)%8];memcpy((char*)&p+8,&v1,4);expected_IS=p;REQUIRE(aggregate_abi_align16_IS_address(p)==0);IS e=aggregate_abi_align16_IS_echo(p);REQUIRE(equal_IS(&e,&p));REQUIRE(aggregate_abi_align16_IS_send(&p)==1);REQUIRE(aggregate_abi_align16_IS_roundtrip(&p)==1);REQUIRE(aggregate_abi_align16_IS_mutate(p,p)==1);REQUIRE(equal_IS(&p,&expected_IS));
unsigned char registers[32],copy[16];memset(copy,0xa5,16);REQUIRE(aggregate_abi_align16_preserved((void(*)(void))aggregate_abi_align16_IS_ret,&p,registers)==1);memcpy(copy+0,registers+0,8);memcpy(copy+8,registers+16,8);REQUIRE(equal_IS(copy,&p));
void*mapping;size_t len;unsigned char*g=guarded(&mapping,&len);REQUIRE(((uintptr_t)g%16)==0);memcpy(g,&p,16);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);IS gval;memcpy(&gval,g,16);e=aggregate_abi_align16_IS_echo(gval);REQUIRE(equal_IS(&e,&p));REQUIRE(aggregate_abi_align16_IS_send(g)==1);REQUIRE(aggregate_abi_align16_IS_roundtrip(g)==1);REQUIRE(aggregate_abi_align16_IS_mutate(gval,gval)==1);REQUIRE(equal_IS(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){II p;memset(&p,0x5a,16);uint64_t v0=bits[(n+0)%8];memcpy((char*)&p+0,&v0,8);uint64_t v1=bits[(n+1)%8];memcpy((char*)&p+8,&v1,8);expected_II=p;REQUIRE(aggregate_abi_align16_II_address(p)==0);II e=aggregate_abi_align16_II_echo(p);REQUIRE(equal_II(&e,&p));REQUIRE(aggregate_abi_align16_II_send(&p)==1);REQUIRE(aggregate_abi_align16_II_roundtrip(&p)==1);REQUIRE(aggregate_abi_align16_II_mutate(p,p)==1);REQUIRE(equal_II(&p,&expected_II));
unsigned char registers[32],copy[16];memset(copy,0xa5,16);REQUIRE(aggregate_abi_align16_preserved((void(*)(void))aggregate_abi_align16_II_ret,&p,registers)==1);memcpy(copy+0,registers+0,8);memcpy(copy+8,registers+8,8);REQUIRE(equal_II(copy,&p));
void*mapping;size_t len;unsigned char*g=guarded(&mapping,&len);REQUIRE(((uintptr_t)g%16)==0);memcpy(g,&p,16);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);II gval;memcpy(&gval,g,16);e=aggregate_abi_align16_II_echo(gval);REQUIRE(equal_II(&e,&p));REQUIRE(aggregate_abi_align16_II_send(g)==1);REQUIRE(aggregate_abi_align16_II_roundtrip(g)==1);REQUIRE(aggregate_abi_align16_II_mutate(gval,gval)==1);REQUIRE(equal_II(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){N p;memset(&p,0x5a,16);uint64_t v0=bits[(n+0)%8];memcpy((char*)&p+0,&v0,4);expected_N=p;REQUIRE(aggregate_abi_align16_N_address(p)==0);N e=aggregate_abi_align16_N_echo(p);REQUIRE(equal_N(&e,&p));REQUIRE(aggregate_abi_align16_N_send(&p)==1);REQUIRE(aggregate_abi_align16_N_roundtrip(&p)==1);REQUIRE(aggregate_abi_align16_N_mutate(p,p)==1);REQUIRE(equal_N(&p,&expected_N));
unsigned char registers[32],copy[16];memset(copy,0xa5,16);REQUIRE(aggregate_abi_align16_preserved((void(*)(void))aggregate_abi_align16_N_ret,&p,registers)==1);memcpy(copy+0,registers+16,8);REQUIRE(equal_N(copy,&p));
void*mapping;size_t len;unsigned char*g=guarded(&mapping,&len);REQUIRE(((uintptr_t)g%16)==0);memcpy(g,&p,16);REQUIRE(mprotect((char*)mapping+len/3,len/3,PROT_READ)==0);N gval;memcpy(&gval,g,16);e=aggregate_abi_align16_N_echo(gval);REQUIRE(equal_N(&e,&p));REQUIRE(aggregate_abi_align16_N_send(g)==1);REQUIRE(aggregate_abi_align16_N_roundtrip(g)==1);REQUIRE(aggregate_abi_align16_N_mutate(gval,gval)==1);REQUIRE(equal_N(g,&p));REQUIRE(munmap(mapping,len)==0);}

for(unsigned n=0;n<8;++n){S p;memset(&p,0x5a,16);uint32_t b=(uint32_t)bits[n];memcpy(&p.f,&b,4);expected_S=p;REQUIRE(aggregate_abi_align16_dynamic(&p)==1);REQUIRE(aggregate_abi_align16_loop(&p)==1);REQUIRE(aggregate_abi_align16_sites(&p)==1);S r=aggregate_abi_align16_recurse(p,9);REQUIRE(equal_S(&r,&p));M source={{1,2,3,4}};expected_M=source;M result=aggregate_abi_align16_memory(&source,p);REQUIRE(memcmp(&result,&source,32)==0);REQUIRE(aggregate_abi_align16_memory_roundtrip(&source,p)==1);}
printf("align16 %u independent assertions passed\n",checks);return 0;}
