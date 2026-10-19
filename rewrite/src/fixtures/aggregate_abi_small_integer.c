#define _GNU_SOURCE
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdarg.h>
static unsigned checks;
#define REQUIRE(x) do{++checks;if(!(x)){fprintf(stderr,"small INTEGER check %u line%d failed\n",checks,__LINE__);abort();}}while(0)
static unsigned char pattern(size_t i,size_t n){return (unsigned char)(37+i*13+n);}
typedef struct{unsigned char b[1];} I1;
_Static_assert(sizeof(I1)==1 && _Alignof(I1)==1,"independent I1 layout");
extern I1 aggregate_abi_small_integer_echo1(I1),aggregate_abi_small_integer_ret1(const void*);
extern uint32_t aggregate_abi_small_integer_send1(const void*),aggregate_abi_small_integer_roundtrip1(const void*),aggregate_abi_small_integer_mutate1(I1,I1);
uint32_t aggregate_abi_small_integer_check1(I1 a){for(size_t i=0;i<1;++i)if(a.b[i]!=pattern(i,1))return 0;return 1;}
I1 aggregate_abi_small_integer_cmake1(const void* p){I1 r;memcpy(&r,p,1);return r;}
typedef struct{unsigned char b[2];} I2;
_Static_assert(sizeof(I2)==2 && _Alignof(I2)==1,"independent I2 layout");
extern I2 aggregate_abi_small_integer_echo2(I2),aggregate_abi_small_integer_ret2(const void*);
extern uint32_t aggregate_abi_small_integer_send2(const void*),aggregate_abi_small_integer_roundtrip2(const void*),aggregate_abi_small_integer_mutate2(I2,I2);
uint32_t aggregate_abi_small_integer_check2(I2 a){for(size_t i=0;i<2;++i)if(a.b[i]!=pattern(i,2))return 0;return 1;}
I2 aggregate_abi_small_integer_cmake2(const void* p){I2 r;memcpy(&r,p,2);return r;}
typedef struct{unsigned char b[3];} I3;
_Static_assert(sizeof(I3)==3 && _Alignof(I3)==1,"independent I3 layout");
extern I3 aggregate_abi_small_integer_echo3(I3),aggregate_abi_small_integer_ret3(const void*);
extern uint32_t aggregate_abi_small_integer_send3(const void*),aggregate_abi_small_integer_roundtrip3(const void*),aggregate_abi_small_integer_mutate3(I3,I3);
uint32_t aggregate_abi_small_integer_check3(I3 a){for(size_t i=0;i<3;++i)if(a.b[i]!=pattern(i,3))return 0;return 1;}
I3 aggregate_abi_small_integer_cmake3(const void* p){I3 r;memcpy(&r,p,3);return r;}
typedef struct{unsigned char b[4];} I4;
_Static_assert(sizeof(I4)==4 && _Alignof(I4)==1,"independent I4 layout");
extern I4 aggregate_abi_small_integer_echo4(I4),aggregate_abi_small_integer_ret4(const void*);
extern uint32_t aggregate_abi_small_integer_send4(const void*),aggregate_abi_small_integer_roundtrip4(const void*),aggregate_abi_small_integer_mutate4(I4,I4);
uint32_t aggregate_abi_small_integer_check4(I4 a){for(size_t i=0;i<4;++i)if(a.b[i]!=pattern(i,4))return 0;return 1;}
I4 aggregate_abi_small_integer_cmake4(const void* p){I4 r;memcpy(&r,p,4);return r;}
typedef struct{unsigned char b[5];} I5;
_Static_assert(sizeof(I5)==5 && _Alignof(I5)==1,"independent I5 layout");
extern I5 aggregate_abi_small_integer_echo5(I5),aggregate_abi_small_integer_ret5(const void*);
extern uint32_t aggregate_abi_small_integer_send5(const void*),aggregate_abi_small_integer_roundtrip5(const void*),aggregate_abi_small_integer_mutate5(I5,I5);
uint32_t aggregate_abi_small_integer_check5(I5 a){for(size_t i=0;i<5;++i)if(a.b[i]!=pattern(i,5))return 0;return 1;}
I5 aggregate_abi_small_integer_cmake5(const void* p){I5 r;memcpy(&r,p,5);return r;}
typedef struct{unsigned char b[6];} I6;
_Static_assert(sizeof(I6)==6 && _Alignof(I6)==1,"independent I6 layout");
extern I6 aggregate_abi_small_integer_echo6(I6),aggregate_abi_small_integer_ret6(const void*);
extern uint32_t aggregate_abi_small_integer_send6(const void*),aggregate_abi_small_integer_roundtrip6(const void*),aggregate_abi_small_integer_mutate6(I6,I6);
uint32_t aggregate_abi_small_integer_check6(I6 a){for(size_t i=0;i<6;++i)if(a.b[i]!=pattern(i,6))return 0;return 1;}
I6 aggregate_abi_small_integer_cmake6(const void* p){I6 r;memcpy(&r,p,6);return r;}
typedef struct{unsigned char b[7];} I7;
_Static_assert(sizeof(I7)==7 && _Alignof(I7)==1,"independent I7 layout");
extern I7 aggregate_abi_small_integer_echo7(I7),aggregate_abi_small_integer_ret7(const void*);
extern uint32_t aggregate_abi_small_integer_send7(const void*),aggregate_abi_small_integer_roundtrip7(const void*),aggregate_abi_small_integer_mutate7(I7,I7);
uint32_t aggregate_abi_small_integer_check7(I7 a){for(size_t i=0;i<7;++i)if(a.b[i]!=pattern(i,7))return 0;return 1;}
I7 aggregate_abi_small_integer_cmake7(const void* p){I7 r;memcpy(&r,p,7);return r;}
typedef struct{unsigned char b[8];} I8;
_Static_assert(sizeof(I8)==8 && _Alignof(I8)==1,"independent I8 layout");
extern I8 aggregate_abi_small_integer_echo8(I8),aggregate_abi_small_integer_ret8(const void*);
extern uint32_t aggregate_abi_small_integer_send8(const void*),aggregate_abi_small_integer_roundtrip8(const void*),aggregate_abi_small_integer_mutate8(I8,I8);
uint32_t aggregate_abi_small_integer_check8(I8 a){for(size_t i=0;i<8;++i)if(a.b[i]!=pattern(i,8))return 0;return 1;}
I8 aggregate_abi_small_integer_cmake8(const void* p){I8 r;memcpy(&r,p,8);return r;}
typedef struct{unsigned char b[9];} I9;
_Static_assert(sizeof(I9)==9 && _Alignof(I9)==1,"independent I9 layout");
extern I9 aggregate_abi_small_integer_echo9(I9),aggregate_abi_small_integer_ret9(const void*);
extern uint32_t aggregate_abi_small_integer_send9(const void*),aggregate_abi_small_integer_roundtrip9(const void*),aggregate_abi_small_integer_mutate9(I9,I9);
uint32_t aggregate_abi_small_integer_check9(I9 a){for(size_t i=0;i<9;++i)if(a.b[i]!=pattern(i,9))return 0;return 1;}
I9 aggregate_abi_small_integer_cmake9(const void* p){I9 r;memcpy(&r,p,9);return r;}
typedef struct{unsigned char b[10];} I10;
_Static_assert(sizeof(I10)==10 && _Alignof(I10)==1,"independent I10 layout");
extern I10 aggregate_abi_small_integer_echo10(I10),aggregate_abi_small_integer_ret10(const void*);
extern uint32_t aggregate_abi_small_integer_send10(const void*),aggregate_abi_small_integer_roundtrip10(const void*),aggregate_abi_small_integer_mutate10(I10,I10);
uint32_t aggregate_abi_small_integer_check10(I10 a){for(size_t i=0;i<10;++i)if(a.b[i]!=pattern(i,10))return 0;return 1;}
I10 aggregate_abi_small_integer_cmake10(const void* p){I10 r;memcpy(&r,p,10);return r;}
typedef struct{unsigned char b[11];} I11;
_Static_assert(sizeof(I11)==11 && _Alignof(I11)==1,"independent I11 layout");
extern I11 aggregate_abi_small_integer_echo11(I11),aggregate_abi_small_integer_ret11(const void*);
extern uint32_t aggregate_abi_small_integer_send11(const void*),aggregate_abi_small_integer_roundtrip11(const void*),aggregate_abi_small_integer_mutate11(I11,I11);
uint32_t aggregate_abi_small_integer_check11(I11 a){for(size_t i=0;i<11;++i)if(a.b[i]!=pattern(i,11))return 0;return 1;}
I11 aggregate_abi_small_integer_cmake11(const void* p){I11 r;memcpy(&r,p,11);return r;}
typedef struct{unsigned char b[12];} I12;
_Static_assert(sizeof(I12)==12 && _Alignof(I12)==1,"independent I12 layout");
extern I12 aggregate_abi_small_integer_echo12(I12),aggregate_abi_small_integer_ret12(const void*);
extern uint32_t aggregate_abi_small_integer_send12(const void*),aggregate_abi_small_integer_roundtrip12(const void*),aggregate_abi_small_integer_mutate12(I12,I12);
uint32_t aggregate_abi_small_integer_check12(I12 a){for(size_t i=0;i<12;++i)if(a.b[i]!=pattern(i,12))return 0;return 1;}
I12 aggregate_abi_small_integer_cmake12(const void* p){I12 r;memcpy(&r,p,12);return r;}
typedef struct{unsigned char b[13];} I13;
_Static_assert(sizeof(I13)==13 && _Alignof(I13)==1,"independent I13 layout");
extern I13 aggregate_abi_small_integer_echo13(I13),aggregate_abi_small_integer_ret13(const void*);
extern uint32_t aggregate_abi_small_integer_send13(const void*),aggregate_abi_small_integer_roundtrip13(const void*),aggregate_abi_small_integer_mutate13(I13,I13);
uint32_t aggregate_abi_small_integer_check13(I13 a){for(size_t i=0;i<13;++i)if(a.b[i]!=pattern(i,13))return 0;return 1;}
I13 aggregate_abi_small_integer_cmake13(const void* p){I13 r;memcpy(&r,p,13);return r;}
typedef struct{unsigned char b[14];} I14;
_Static_assert(sizeof(I14)==14 && _Alignof(I14)==1,"independent I14 layout");
extern I14 aggregate_abi_small_integer_echo14(I14),aggregate_abi_small_integer_ret14(const void*);
extern uint32_t aggregate_abi_small_integer_send14(const void*),aggregate_abi_small_integer_roundtrip14(const void*),aggregate_abi_small_integer_mutate14(I14,I14);
uint32_t aggregate_abi_small_integer_check14(I14 a){for(size_t i=0;i<14;++i)if(a.b[i]!=pattern(i,14))return 0;return 1;}
I14 aggregate_abi_small_integer_cmake14(const void* p){I14 r;memcpy(&r,p,14);return r;}
typedef struct{unsigned char b[15];} I15;
_Static_assert(sizeof(I15)==15 && _Alignof(I15)==1,"independent I15 layout");
extern I15 aggregate_abi_small_integer_echo15(I15),aggregate_abi_small_integer_ret15(const void*);
extern uint32_t aggregate_abi_small_integer_send15(const void*),aggregate_abi_small_integer_roundtrip15(const void*),aggregate_abi_small_integer_mutate15(I15,I15);
uint32_t aggregate_abi_small_integer_check15(I15 a){for(size_t i=0;i<15;++i)if(a.b[i]!=pattern(i,15))return 0;return 1;}
I15 aggregate_abi_small_integer_cmake15(const void* p){I15 r;memcpy(&r,p,15);return r;}
typedef struct{unsigned char b[16];} I16;
_Static_assert(sizeof(I16)==16 && _Alignof(I16)==1,"independent I16 layout");
extern I16 aggregate_abi_small_integer_echo16(I16),aggregate_abi_small_integer_ret16(const void*);
extern uint32_t aggregate_abi_small_integer_send16(const void*),aggregate_abi_small_integer_roundtrip16(const void*),aggregate_abi_small_integer_mutate16(I16,I16);
uint32_t aggregate_abi_small_integer_check16(I16 a){for(size_t i=0;i<16;++i)if(a.b[i]!=pattern(i,16))return 0;return 1;}
I16 aggregate_abi_small_integer_cmake16(const void* p){I16 r;memcpy(&r,p,16);return r;}
typedef struct{unsigned char b[17];} M;
_Static_assert(sizeof(M)==17 && _Alignof(M)==1,"independent MEMORY mix layout");
typedef struct{uint16_t h;uint8_t b;} N;
typedef struct{N n[2];uint64_t value;} Nested;
_Static_assert(sizeof(N)==4 && _Alignof(N)==2 && offsetof(N,b)==2,"independent child layout");
_Static_assert(sizeof(Nested)==16 && _Alignof(Nested)==8 && offsetof(Nested,value)==8,"independent nested layout");
extern Nested aggregate_abi_small_integer_nested(Nested);
extern M aggregate_abi_small_integer_memory_mix(uint64_t l0,uint64_t l1,uint64_t l2,uint64_t l3,I9 a,uint64_t after,I1 b,double d0,double d1,double d2,double d3,double d4,double d5,double d6,double d7,double d8);
extern I9 aggregate_abi_small_integer_integer_mix(uint64_t l0,uint64_t l1,uint64_t l2,uint64_t l3,I9 a,uint64_t after,I1 b,double d0,double d1,double d2,double d3,double d4,double d5,double d6,double d7,double d8);
uint32_t aggregate_abi_small_integer_verify(uint64_t l0,uint64_t l1,uint64_t l2,uint64_t l3,I9 a,uint64_t after,I1 b,double d0,double d1,double d2,double d3,double d4,double d5,double d6,double d7,double d8){return l0==11 && l1==22 && l2==33 && l3==44 && after==55 && a.b[0]==46 && a.b[8]==150 && b.b[0]==38 && d0==1. && d1==2. && d2==3. && d3==4. && d4==5. && d5==6. && d6==7. && d7==8. && d8==9.;}
M aggregate_abi_small_integer_mmake(uint32_t value){M r;memset(&r,(unsigned char)value,sizeof r);return r;}
M aggregate_abi_small_integer_cmemory_mix(uint64_t l0,uint64_t l1,uint64_t l2,uint64_t l3,I9 a,uint64_t after,I1 b,double d0,double d1,double d2,double d3,double d4,double d5,double d6,double d7,double d8){REQUIRE(aggregate_abi_small_integer_verify(l0,l1,l2,l3,a,after,b,d0,d1,d2,d3,d4,d5,d6,d7,d8));return aggregate_abi_small_integer_mmake(209);}
I9 aggregate_abi_small_integer_cinteger_mix(uint64_t l0,uint64_t l1,uint64_t l2,uint64_t l3,I9 a,uint64_t after,I1 b,double d0,double d1,double d2,double d3,double d4,double d5,double d6,double d7,double d8){REQUIRE(aggregate_abi_small_integer_verify(l0,l1,l2,l3,a,after,b,d0,d1,d2,d3,d4,d5,d6,d7,d8));return a;}
extern uint32_t aggregate_abi_small_integer_call_memory_mix(const void*,const void*),aggregate_abi_small_integer_call_integer_mix(const void*,const void*),aggregate_abi_small_integer_call_memory_probe(const void*,const void*),aggregate_abi_small_integer_call_integer_probe(const void*,const void*);
extern uint32_t aggregate_abi_small_integer_sites(void),aggregate_abi_small_integer_loop(uint32_t),aggregate_abi_small_integer_varcaller(const void*,...),aggregate_abi_small_integer_envbridge(const void*);
extern I9 aggregate_abi_small_integer_recurse(I9,uint32_t),aggregate_abi_small_integer_dynamic(const void*,const void*),aggregate_abi_small_integer_scalarindirect(I9,uint32_t(*)(uint32_t));
I9 aggregate_abi_small_integer_make(uint32_t value){I9 r;memset(&r,(unsigned char)value,sizeof r);return r;}
static const void* observed;
uint32_t aggregate_abi_small_integer_observe(const void* p,uint32_t i){if(!i)observed=p;return p==observed && *(const unsigned char*)p==(unsigned char)i;}
uint32_t aggregate_abi_small_integer_varcheck(uint32_t n,...){va_list ap;va_start(ap,n);unsigned a=va_arg(ap,unsigned);double d=va_arg(ap,double);va_end(ap);return n==1 && a==9 && d==2.;}
static uint32_t indirect(uint32_t value){return value+35;}
static uint64_t raw(double d){uint64_t bits;memcpy(&bits,&d,8);return bits;}
extern uint32_t aggregate_abi_small_integer_bits(const void*);
extern I9 aggregate_abi_small_integer_bitreceiver(I9,double,double,double,double,double,double,double,double,double);
I9 aggregate_abi_small_integer_cbits(I9 a,double z,double n,double d2,double d3,double d4,double d5,double d6,double d7,double last){REQUIRE(raw(z)==UINT64_C(0x8000000000000000));REQUIRE(raw(n)==UINT64_C(0x7ff8000000001234));REQUIRE(raw(last)==UINT64_C(0x7ff8000000005678));REQUIRE(d2==3.&&d3==4.&&d4==5.&&d5==6.&&d6==7.&&d7==8.);a.b[0]=245;return a;}
extern I9 aggregate_abi_small_integer_subincoming(int8_t,uint8_t,int16_t,uint16_t,int8_t,uint8_t,I9);
extern uint32_t aggregate_abi_small_integer_suboutgoing(const void*);
uint32_t aggregate_abi_small_integer_normalized(int32_t a,uint32_t b,int32_t c,uint32_t d,int32_t e,uint32_t f){return a==-128 && b==255 && c==-32768 && d==65535 && e==-1 && f==254;}
I9 aggregate_abi_small_integer_csub(int8_t a,uint8_t b,int16_t c,uint16_t d,int8_t e,uint8_t f,I9 p){REQUIRE(aggregate_abi_small_integer_normalized(a,b,c,d,e,f));REQUIRE(p.b[0]==46);p.b[0]=247;return p;}
static unsigned char* guarded(size_t n,void** mapping,size_t* total){long pg=sysconf(_SC_PAGESIZE);REQUIRE(pg>16);*total=(size_t)pg*3;void* base=mmap(NULL,*total,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);REQUIRE(base!=MAP_FAILED);REQUIRE(mprotect((char*)base+pg,(size_t)pg,PROT_READ|PROT_WRITE)==0);*mapping=base;return (unsigned char*)base+2*pg-n;}
extern I9 aggregate_abi_small_integer_poison_incoming(const void*);
extern uint32_t aggregate_abi_small_integer_poison_capture(const void*);
extern uint32_t aggregate_abi_small_integer_preserved(void (*)(void),const void*,unsigned char[16]);
int main(void){
{I1 a;for(size_t i=0;i<1;++i)a.b[i]=pattern(i,1);I1 r=aggregate_abi_small_integer_echo1(a);REQUIRE(memcmp(&r,&a,1)==0);REQUIRE(aggregate_abi_small_integer_mutate1(a,a)==a.b[0]);REQUIRE(a.b[0]==pattern(0,1));
void* m;size_t length;unsigned char* p=guarded(1,&m,&length);memcpy(p,&a,1);REQUIRE(mprotect((char*)m+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
r=aggregate_abi_small_integer_ret1(p);REQUIRE(memcmp(&r,&a,1)==0);unsigned char captured[16];memset(captured,0xcc,16);REQUIRE(aggregate_abi_small_integer_preserved((void(*)(void))aggregate_abi_small_integer_ret1,p,captured)==1);REQUIRE(memcmp(captured,&a,1)==0);REQUIRE(aggregate_abi_small_integer_send1(p)==1);REQUIRE(aggregate_abi_small_integer_roundtrip1(p)==1);REQUIRE(memcmp(p,&a,1)==0);REQUIRE(munmap(m,length)==0);}
{I2 a;for(size_t i=0;i<2;++i)a.b[i]=pattern(i,2);I2 r=aggregate_abi_small_integer_echo2(a);REQUIRE(memcmp(&r,&a,2)==0);REQUIRE(aggregate_abi_small_integer_mutate2(a,a)==a.b[0]);REQUIRE(a.b[0]==pattern(0,2));
void* m;size_t length;unsigned char* p=guarded(2,&m,&length);memcpy(p,&a,2);REQUIRE(mprotect((char*)m+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
r=aggregate_abi_small_integer_ret2(p);REQUIRE(memcmp(&r,&a,2)==0);unsigned char captured[16];memset(captured,0xcc,16);REQUIRE(aggregate_abi_small_integer_preserved((void(*)(void))aggregate_abi_small_integer_ret2,p,captured)==1);REQUIRE(memcmp(captured,&a,2)==0);REQUIRE(aggregate_abi_small_integer_send2(p)==1);REQUIRE(aggregate_abi_small_integer_roundtrip2(p)==1);REQUIRE(memcmp(p,&a,2)==0);REQUIRE(munmap(m,length)==0);}
{I3 a;for(size_t i=0;i<3;++i)a.b[i]=pattern(i,3);I3 r=aggregate_abi_small_integer_echo3(a);REQUIRE(memcmp(&r,&a,3)==0);REQUIRE(aggregate_abi_small_integer_mutate3(a,a)==a.b[0]);REQUIRE(a.b[0]==pattern(0,3));
void* m;size_t length;unsigned char* p=guarded(3,&m,&length);memcpy(p,&a,3);REQUIRE(mprotect((char*)m+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
r=aggregate_abi_small_integer_ret3(p);REQUIRE(memcmp(&r,&a,3)==0);unsigned char captured[16];memset(captured,0xcc,16);REQUIRE(aggregate_abi_small_integer_preserved((void(*)(void))aggregate_abi_small_integer_ret3,p,captured)==1);REQUIRE(memcmp(captured,&a,3)==0);REQUIRE(aggregate_abi_small_integer_send3(p)==1);REQUIRE(aggregate_abi_small_integer_roundtrip3(p)==1);REQUIRE(memcmp(p,&a,3)==0);REQUIRE(munmap(m,length)==0);}
{I4 a;for(size_t i=0;i<4;++i)a.b[i]=pattern(i,4);I4 r=aggregate_abi_small_integer_echo4(a);REQUIRE(memcmp(&r,&a,4)==0);REQUIRE(aggregate_abi_small_integer_mutate4(a,a)==a.b[0]);REQUIRE(a.b[0]==pattern(0,4));
void* m;size_t length;unsigned char* p=guarded(4,&m,&length);memcpy(p,&a,4);REQUIRE(mprotect((char*)m+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
r=aggregate_abi_small_integer_ret4(p);REQUIRE(memcmp(&r,&a,4)==0);unsigned char captured[16];memset(captured,0xcc,16);REQUIRE(aggregate_abi_small_integer_preserved((void(*)(void))aggregate_abi_small_integer_ret4,p,captured)==1);REQUIRE(memcmp(captured,&a,4)==0);REQUIRE(aggregate_abi_small_integer_send4(p)==1);REQUIRE(aggregate_abi_small_integer_roundtrip4(p)==1);REQUIRE(memcmp(p,&a,4)==0);REQUIRE(munmap(m,length)==0);}
{I5 a;for(size_t i=0;i<5;++i)a.b[i]=pattern(i,5);I5 r=aggregate_abi_small_integer_echo5(a);REQUIRE(memcmp(&r,&a,5)==0);REQUIRE(aggregate_abi_small_integer_mutate5(a,a)==a.b[0]);REQUIRE(a.b[0]==pattern(0,5));
void* m;size_t length;unsigned char* p=guarded(5,&m,&length);memcpy(p,&a,5);REQUIRE(mprotect((char*)m+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
r=aggregate_abi_small_integer_ret5(p);REQUIRE(memcmp(&r,&a,5)==0);unsigned char captured[16];memset(captured,0xcc,16);REQUIRE(aggregate_abi_small_integer_preserved((void(*)(void))aggregate_abi_small_integer_ret5,p,captured)==1);REQUIRE(memcmp(captured,&a,5)==0);REQUIRE(aggregate_abi_small_integer_send5(p)==1);REQUIRE(aggregate_abi_small_integer_roundtrip5(p)==1);REQUIRE(memcmp(p,&a,5)==0);REQUIRE(munmap(m,length)==0);}
{I6 a;for(size_t i=0;i<6;++i)a.b[i]=pattern(i,6);I6 r=aggregate_abi_small_integer_echo6(a);REQUIRE(memcmp(&r,&a,6)==0);REQUIRE(aggregate_abi_small_integer_mutate6(a,a)==a.b[0]);REQUIRE(a.b[0]==pattern(0,6));
void* m;size_t length;unsigned char* p=guarded(6,&m,&length);memcpy(p,&a,6);REQUIRE(mprotect((char*)m+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
r=aggregate_abi_small_integer_ret6(p);REQUIRE(memcmp(&r,&a,6)==0);unsigned char captured[16];memset(captured,0xcc,16);REQUIRE(aggregate_abi_small_integer_preserved((void(*)(void))aggregate_abi_small_integer_ret6,p,captured)==1);REQUIRE(memcmp(captured,&a,6)==0);REQUIRE(aggregate_abi_small_integer_send6(p)==1);REQUIRE(aggregate_abi_small_integer_roundtrip6(p)==1);REQUIRE(memcmp(p,&a,6)==0);REQUIRE(munmap(m,length)==0);}
{I7 a;for(size_t i=0;i<7;++i)a.b[i]=pattern(i,7);I7 r=aggregate_abi_small_integer_echo7(a);REQUIRE(memcmp(&r,&a,7)==0);REQUIRE(aggregate_abi_small_integer_mutate7(a,a)==a.b[0]);REQUIRE(a.b[0]==pattern(0,7));
void* m;size_t length;unsigned char* p=guarded(7,&m,&length);memcpy(p,&a,7);REQUIRE(mprotect((char*)m+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
r=aggregate_abi_small_integer_ret7(p);REQUIRE(memcmp(&r,&a,7)==0);unsigned char captured[16];memset(captured,0xcc,16);REQUIRE(aggregate_abi_small_integer_preserved((void(*)(void))aggregate_abi_small_integer_ret7,p,captured)==1);REQUIRE(memcmp(captured,&a,7)==0);REQUIRE(aggregate_abi_small_integer_send7(p)==1);REQUIRE(aggregate_abi_small_integer_roundtrip7(p)==1);REQUIRE(memcmp(p,&a,7)==0);REQUIRE(munmap(m,length)==0);}
{I8 a;for(size_t i=0;i<8;++i)a.b[i]=pattern(i,8);I8 r=aggregate_abi_small_integer_echo8(a);REQUIRE(memcmp(&r,&a,8)==0);REQUIRE(aggregate_abi_small_integer_mutate8(a,a)==a.b[0]);REQUIRE(a.b[0]==pattern(0,8));
void* m;size_t length;unsigned char* p=guarded(8,&m,&length);memcpy(p,&a,8);REQUIRE(mprotect((char*)m+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
r=aggregate_abi_small_integer_ret8(p);REQUIRE(memcmp(&r,&a,8)==0);unsigned char captured[16];memset(captured,0xcc,16);REQUIRE(aggregate_abi_small_integer_preserved((void(*)(void))aggregate_abi_small_integer_ret8,p,captured)==1);REQUIRE(memcmp(captured,&a,8)==0);REQUIRE(aggregate_abi_small_integer_send8(p)==1);REQUIRE(aggregate_abi_small_integer_roundtrip8(p)==1);REQUIRE(memcmp(p,&a,8)==0);REQUIRE(munmap(m,length)==0);}
{I9 a;for(size_t i=0;i<9;++i)a.b[i]=pattern(i,9);I9 r=aggregate_abi_small_integer_echo9(a);REQUIRE(memcmp(&r,&a,9)==0);REQUIRE(aggregate_abi_small_integer_mutate9(a,a)==a.b[0]);REQUIRE(a.b[0]==pattern(0,9));
void* m;size_t length;unsigned char* p=guarded(9,&m,&length);memcpy(p,&a,9);REQUIRE(mprotect((char*)m+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
r=aggregate_abi_small_integer_ret9(p);REQUIRE(memcmp(&r,&a,9)==0);unsigned char captured[16];memset(captured,0xcc,16);REQUIRE(aggregate_abi_small_integer_preserved((void(*)(void))aggregate_abi_small_integer_ret9,p,captured)==1);REQUIRE(memcmp(captured,&a,9)==0);REQUIRE(aggregate_abi_small_integer_send9(p)==1);REQUIRE(aggregate_abi_small_integer_roundtrip9(p)==1);REQUIRE(memcmp(p,&a,9)==0);REQUIRE(munmap(m,length)==0);}
{I10 a;for(size_t i=0;i<10;++i)a.b[i]=pattern(i,10);I10 r=aggregate_abi_small_integer_echo10(a);REQUIRE(memcmp(&r,&a,10)==0);REQUIRE(aggregate_abi_small_integer_mutate10(a,a)==a.b[0]);REQUIRE(a.b[0]==pattern(0,10));
void* m;size_t length;unsigned char* p=guarded(10,&m,&length);memcpy(p,&a,10);REQUIRE(mprotect((char*)m+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
r=aggregate_abi_small_integer_ret10(p);REQUIRE(memcmp(&r,&a,10)==0);unsigned char captured[16];memset(captured,0xcc,16);REQUIRE(aggregate_abi_small_integer_preserved((void(*)(void))aggregate_abi_small_integer_ret10,p,captured)==1);REQUIRE(memcmp(captured,&a,10)==0);REQUIRE(aggregate_abi_small_integer_send10(p)==1);REQUIRE(aggregate_abi_small_integer_roundtrip10(p)==1);REQUIRE(memcmp(p,&a,10)==0);REQUIRE(munmap(m,length)==0);}
{I11 a;for(size_t i=0;i<11;++i)a.b[i]=pattern(i,11);I11 r=aggregate_abi_small_integer_echo11(a);REQUIRE(memcmp(&r,&a,11)==0);REQUIRE(aggregate_abi_small_integer_mutate11(a,a)==a.b[0]);REQUIRE(a.b[0]==pattern(0,11));
void* m;size_t length;unsigned char* p=guarded(11,&m,&length);memcpy(p,&a,11);REQUIRE(mprotect((char*)m+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
r=aggregate_abi_small_integer_ret11(p);REQUIRE(memcmp(&r,&a,11)==0);unsigned char captured[16];memset(captured,0xcc,16);REQUIRE(aggregate_abi_small_integer_preserved((void(*)(void))aggregate_abi_small_integer_ret11,p,captured)==1);REQUIRE(memcmp(captured,&a,11)==0);REQUIRE(aggregate_abi_small_integer_send11(p)==1);REQUIRE(aggregate_abi_small_integer_roundtrip11(p)==1);REQUIRE(memcmp(p,&a,11)==0);REQUIRE(munmap(m,length)==0);}
{I12 a;for(size_t i=0;i<12;++i)a.b[i]=pattern(i,12);I12 r=aggregate_abi_small_integer_echo12(a);REQUIRE(memcmp(&r,&a,12)==0);REQUIRE(aggregate_abi_small_integer_mutate12(a,a)==a.b[0]);REQUIRE(a.b[0]==pattern(0,12));
void* m;size_t length;unsigned char* p=guarded(12,&m,&length);memcpy(p,&a,12);REQUIRE(mprotect((char*)m+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
r=aggregate_abi_small_integer_ret12(p);REQUIRE(memcmp(&r,&a,12)==0);unsigned char captured[16];memset(captured,0xcc,16);REQUIRE(aggregate_abi_small_integer_preserved((void(*)(void))aggregate_abi_small_integer_ret12,p,captured)==1);REQUIRE(memcmp(captured,&a,12)==0);REQUIRE(aggregate_abi_small_integer_send12(p)==1);REQUIRE(aggregate_abi_small_integer_roundtrip12(p)==1);REQUIRE(memcmp(p,&a,12)==0);REQUIRE(munmap(m,length)==0);}
{I13 a;for(size_t i=0;i<13;++i)a.b[i]=pattern(i,13);I13 r=aggregate_abi_small_integer_echo13(a);REQUIRE(memcmp(&r,&a,13)==0);REQUIRE(aggregate_abi_small_integer_mutate13(a,a)==a.b[0]);REQUIRE(a.b[0]==pattern(0,13));
void* m;size_t length;unsigned char* p=guarded(13,&m,&length);memcpy(p,&a,13);REQUIRE(mprotect((char*)m+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
r=aggregate_abi_small_integer_ret13(p);REQUIRE(memcmp(&r,&a,13)==0);unsigned char captured[16];memset(captured,0xcc,16);REQUIRE(aggregate_abi_small_integer_preserved((void(*)(void))aggregate_abi_small_integer_ret13,p,captured)==1);REQUIRE(memcmp(captured,&a,13)==0);REQUIRE(aggregate_abi_small_integer_send13(p)==1);REQUIRE(aggregate_abi_small_integer_roundtrip13(p)==1);REQUIRE(memcmp(p,&a,13)==0);REQUIRE(munmap(m,length)==0);}
{I14 a;for(size_t i=0;i<14;++i)a.b[i]=pattern(i,14);I14 r=aggregate_abi_small_integer_echo14(a);REQUIRE(memcmp(&r,&a,14)==0);REQUIRE(aggregate_abi_small_integer_mutate14(a,a)==a.b[0]);REQUIRE(a.b[0]==pattern(0,14));
void* m;size_t length;unsigned char* p=guarded(14,&m,&length);memcpy(p,&a,14);REQUIRE(mprotect((char*)m+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
r=aggregate_abi_small_integer_ret14(p);REQUIRE(memcmp(&r,&a,14)==0);unsigned char captured[16];memset(captured,0xcc,16);REQUIRE(aggregate_abi_small_integer_preserved((void(*)(void))aggregate_abi_small_integer_ret14,p,captured)==1);REQUIRE(memcmp(captured,&a,14)==0);REQUIRE(aggregate_abi_small_integer_send14(p)==1);REQUIRE(aggregate_abi_small_integer_roundtrip14(p)==1);REQUIRE(memcmp(p,&a,14)==0);REQUIRE(munmap(m,length)==0);}
{I15 a;for(size_t i=0;i<15;++i)a.b[i]=pattern(i,15);I15 r=aggregate_abi_small_integer_echo15(a);REQUIRE(memcmp(&r,&a,15)==0);REQUIRE(aggregate_abi_small_integer_mutate15(a,a)==a.b[0]);REQUIRE(a.b[0]==pattern(0,15));
void* m;size_t length;unsigned char* p=guarded(15,&m,&length);memcpy(p,&a,15);REQUIRE(mprotect((char*)m+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
r=aggregate_abi_small_integer_ret15(p);REQUIRE(memcmp(&r,&a,15)==0);unsigned char captured[16];memset(captured,0xcc,16);REQUIRE(aggregate_abi_small_integer_preserved((void(*)(void))aggregate_abi_small_integer_ret15,p,captured)==1);REQUIRE(memcmp(captured,&a,15)==0);REQUIRE(aggregate_abi_small_integer_send15(p)==1);REQUIRE(aggregate_abi_small_integer_roundtrip15(p)==1);REQUIRE(memcmp(p,&a,15)==0);REQUIRE(munmap(m,length)==0);}
{I16 a;for(size_t i=0;i<16;++i)a.b[i]=pattern(i,16);I16 r=aggregate_abi_small_integer_echo16(a);REQUIRE(memcmp(&r,&a,16)==0);REQUIRE(aggregate_abi_small_integer_mutate16(a,a)==a.b[0]);REQUIRE(a.b[0]==pattern(0,16));
void* m;size_t length;unsigned char* p=guarded(16,&m,&length);memcpy(p,&a,16);REQUIRE(mprotect((char*)m+sysconf(_SC_PAGESIZE),(size_t)sysconf(_SC_PAGESIZE),PROT_READ)==0);
r=aggregate_abi_small_integer_ret16(p);REQUIRE(memcmp(&r,&a,16)==0);unsigned char captured[16];memset(captured,0xcc,16);REQUIRE(aggregate_abi_small_integer_preserved((void(*)(void))aggregate_abi_small_integer_ret16,p,captured)==1);REQUIRE(memcmp(captured,&a,16)==0);REQUIRE(aggregate_abi_small_integer_send16(p)==1);REQUIRE(aggregate_abi_small_integer_roundtrip16(p)==1);REQUIRE(memcmp(p,&a,16)==0);REQUIRE(munmap(m,length)==0);}
I9 a;for(size_t i=0;i<9;++i)a.b[i]=pattern(i,9);I1 b={{38}};I9 copy=a;I9 poison=aggregate_abi_small_integer_poison_incoming(&a);REQUIRE(memcmp(&poison,&a,9)==0);REQUIRE(aggregate_abi_small_integer_poison_capture(&a)==1);
M m=aggregate_abi_small_integer_memory_mix(11,22,33,44,a,55,b,1.,2.,3.,4.,5.,6.,7.,8.,9.);for(size_t i=0;i<17;++i)REQUIRE(m.b[i]==209);
I9 v=aggregate_abi_small_integer_integer_mix(11,22,33,44,a,55,b,1.,2.,3.,4.,5.,6.,7.,8.,9.);REQUIRE(memcmp(&v,&a,9)==0);
REQUIRE(aggregate_abi_small_integer_call_memory_mix(&a,&b)==209);REQUIRE(aggregate_abi_small_integer_call_integer_mix(&a,&b)==46);
REQUIRE(aggregate_abi_small_integer_call_memory_probe(&a,&b)==209);REQUIRE(aggregate_abi_small_integer_call_integer_probe(&a,&b)==46);
Nested nested;memset(&nested,0,sizeof nested);nested.n[0].h=0x1234;nested.n[0].b=17;nested.n[1].h=0xabcd;nested.n[1].b=91;nested.value=UINT64_C(0x8877665544332211);Nested nr=aggregate_abi_small_integer_nested(nested);REQUIRE(nr.n[0].h==nested.n[0].h&&nr.n[0].b==17&&nr.n[1].h==nested.n[1].h&&nr.n[1].b==91&&nr.value==nested.value);
REQUIRE(aggregate_abi_small_integer_sites()==33);REQUIRE(aggregate_abi_small_integer_loop(9)==1);
v=aggregate_abi_small_integer_recurse(a,9);REQUIRE(memcmp(&v,&a,9)==0);v=aggregate_abi_small_integer_dynamic(&a,&b);REQUIRE(memcmp(&v,&a,9)==0);
REQUIRE(aggregate_abi_small_integer_varcaller(&a,UINT64_C(9))==a.b[0]+9u);REQUIRE(aggregate_abi_small_integer_envbridge(&a)==a.b[0]+7u);
v=aggregate_abi_small_integer_scalarindirect(a,indirect);REQUIRE(v.b[0]==51);REQUIRE(memcmp(&copy,&a,9)==0);
REQUIRE(aggregate_abi_small_integer_bits(&a)==245);uint64_t zb=UINT64_C(0x8000000000000000),nb=UINT64_C(0x7ff8000000001234),lb=UINT64_C(0x7ff8000000005678);double z,n,last;memcpy(&z,&zb,8);memcpy(&n,&nb,8);memcpy(&last,&lb,8);v=aggregate_abi_small_integer_bitreceiver(a,z,n,3.,4.,5.,6.,7.,8.,last);REQUIRE(v.b[0]==245);
v=aggregate_abi_small_integer_subincoming(-128,255,-32768,65535,-1,254,a);REQUIRE(v.b[0]==246);REQUIRE(aggregate_abi_small_integer_suboutgoing(&a)==247);
printf("%u independent small INTEGER checks passed\n",checks);return 0;}
