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
#define REQUIRE(c) do{++checks;if(!(c)){fprintf(stderr,"variadic record line%d\n",__LINE__);abort();}}while(0)
static const uint64_t bits[]={UINT64_C(0x8000000080000000),UINT64_C(0x7ff000007f800000),UINT64_C(0xfff00000ff800000),UINT64_C(0x7ff812347fc12345),UINT64_C(0x7ff012347fa12345),UINT64_C(1),UINT64_C(0x3ff000003f800001),UINT64_C(0x7fffffff7fffffff)};
void aggregate_abi_variadic_scalar_check(uint32_t tag,uint64_t n,double d){REQUIRE(tag==77);REQUIRE(n==99);uint64_t b;memcpy(&b,&d,8);REQUIRE(b==UINT64_C(0x3ff0000000000000));}
void aggregate_abi_variadic_after(uint64_t n){REQUIRE(n==101);}
static unsigned char* guarded(size_t size,void**m,size_t*len){long pg=sysconf(_SC_PAGESIZE);REQUIRE(pg>=4096);*len=pg*3;*m=mmap(0,*len,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);REQUIRE(*m!=MAP_FAILED);REQUIRE(mprotect((char*)*m+pg,pg,PROT_READ|PROT_WRITE)==0);return (unsigned char*)*m+pg*2-size;}

typedef struct{unsigned char b[3];}B3;
_Static_assert(sizeof(B3)==3&&_Alignof(B3)==1,"literal B3 layout");
_Static_assert(offsetof(B3,b[0])==0,"literal B3.b[0] offset");
_Static_assert(offsetof(B3,b[1])==1,"literal B3.b[1] offset");
_Static_assert(offsetof(B3,b[2])==2,"literal B3.b[2] offset");
static B3 expected_B3;
static int equal_B3(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,1)==0 && memcmp((const char*)a+1,(const char*)b+1,1)==0 && memcmp((const char*)a+2,(const char*)b+2,1)==0;}
B3 aggregate_abi_variadic_B3_read(uint32_t tag,...){va_list ap;va_start(ap,tag);B3 v=va_arg(ap,B3);uint64_t n=va_arg(ap,uint64_t);double d=va_arg(ap,double);va_end(ap);aggregate_abi_variadic_scalar_check(tag,n,d);REQUIRE(equal_B3(&v,&expected_B3));return v;}
uint32_t aggregate_abi_variadic_B3_consume(void*raw){va_list*ap=(va_list*)raw;B3 v=va_arg(*ap,B3);uint64_t n=va_arg(*ap,uint64_t);double d=va_arg(*ap,double);aggregate_abi_variadic_scalar_check(77,n,d);REQUIRE(equal_B3(&v,&expected_B3));return 1;}
extern B3 aggregate_abi_variadic_B3_al(uint32_t,...),aggregate_abi_variadic_B3_definition(B3,uint32_t,...),aggregate_abi_variadic_B3_tail(B3,uint32_t,...),aggregate_abi_variadic_B3_direct(const void*),aggregate_abi_variadic_B3_indirect(void*,const void*);
typedef struct{unsigned char b[13];}I13;
_Static_assert(sizeof(I13)==13&&_Alignof(I13)==1,"literal I13 layout");
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
I13 aggregate_abi_variadic_I13_read(uint32_t tag,...){va_list ap;va_start(ap,tag);I13 v=va_arg(ap,I13);uint64_t n=va_arg(ap,uint64_t);double d=va_arg(ap,double);va_end(ap);aggregate_abi_variadic_scalar_check(tag,n,d);REQUIRE(equal_I13(&v,&expected_I13));return v;}
uint32_t aggregate_abi_variadic_I13_consume(void*raw){va_list*ap=(va_list*)raw;I13 v=va_arg(*ap,I13);uint64_t n=va_arg(*ap,uint64_t);double d=va_arg(*ap,double);aggregate_abi_variadic_scalar_check(77,n,d);REQUIRE(equal_I13(&v,&expected_I13));return 1;}
extern I13 aggregate_abi_variadic_I13_al(uint32_t,...),aggregate_abi_variadic_I13_definition(I13,uint32_t,...),aggregate_abi_variadic_I13_tail(I13,uint32_t,...),aggregate_abi_variadic_I13_direct(const void*),aggregate_abi_variadic_I13_indirect(void*,const void*);
typedef struct{uint32_t u;float f;}W8;
_Static_assert(sizeof(W8)==8&&_Alignof(W8)==4,"literal W8 layout");
_Static_assert(offsetof(W8,u)==0,"literal W8.u offset");
_Static_assert(offsetof(W8,f)==4,"literal W8.f offset");
static W8 expected_W8;
static int equal_W8(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,4)==0 && memcmp((const char*)a+4,(const char*)b+4,4)==0;}
W8 aggregate_abi_variadic_W8_read(uint32_t tag,...){va_list ap;va_start(ap,tag);W8 v=va_arg(ap,W8);uint64_t n=va_arg(ap,uint64_t);double d=va_arg(ap,double);va_end(ap);aggregate_abi_variadic_scalar_check(tag,n,d);REQUIRE(equal_W8(&v,&expected_W8));return v;}
uint32_t aggregate_abi_variadic_W8_consume(void*raw){va_list*ap=(va_list*)raw;W8 v=va_arg(*ap,W8);uint64_t n=va_arg(*ap,uint64_t);double d=va_arg(*ap,double);aggregate_abi_variadic_scalar_check(77,n,d);REQUIRE(equal_W8(&v,&expected_W8));return 1;}
extern W8 aggregate_abi_variadic_W8_al(uint32_t,...),aggregate_abi_variadic_W8_definition(W8,uint32_t,...),aggregate_abi_variadic_W8_tail(W8,uint32_t,...),aggregate_abi_variadic_W8_direct(const void*),aggregate_abi_variadic_W8_indirect(void*,const void*);
typedef struct{float f;}S4;
_Static_assert(sizeof(S4)==4&&_Alignof(S4)==4,"literal S4 layout");
_Static_assert(offsetof(S4,f)==0,"literal S4.f offset");
static S4 expected_S4;
static int equal_S4(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,4)==0;}
S4 aggregate_abi_variadic_S4_read(uint32_t tag,...){va_list ap;va_start(ap,tag);S4 v=va_arg(ap,S4);uint64_t n=va_arg(ap,uint64_t);double d=va_arg(ap,double);va_end(ap);aggregate_abi_variadic_scalar_check(tag,n,d);REQUIRE(equal_S4(&v,&expected_S4));return v;}
uint32_t aggregate_abi_variadic_S4_consume(void*raw){va_list*ap=(va_list*)raw;S4 v=va_arg(*ap,S4);uint64_t n=va_arg(*ap,uint64_t);double d=va_arg(*ap,double);aggregate_abi_variadic_scalar_check(77,n,d);REQUIRE(equal_S4(&v,&expected_S4));return 1;}
extern S4 aggregate_abi_variadic_S4_al(uint32_t,...),aggregate_abi_variadic_S4_definition(S4,uint32_t,...),aggregate_abi_variadic_S4_tail(S4,uint32_t,...),aggregate_abi_variadic_S4_direct(const void*),aggregate_abi_variadic_S4_indirect(void*,const void*);
typedef struct{double d;}D8;
_Static_assert(sizeof(D8)==8&&_Alignof(D8)==8,"literal D8 layout");
_Static_assert(offsetof(D8,d)==0,"literal D8.d offset");
static D8 expected_D8;
static int equal_D8(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,8)==0;}
D8 aggregate_abi_variadic_D8_read(uint32_t tag,...){va_list ap;va_start(ap,tag);D8 v=va_arg(ap,D8);uint64_t n=va_arg(ap,uint64_t);double d=va_arg(ap,double);va_end(ap);aggregate_abi_variadic_scalar_check(tag,n,d);REQUIRE(equal_D8(&v,&expected_D8));return v;}
uint32_t aggregate_abi_variadic_D8_consume(void*raw){va_list*ap=(va_list*)raw;D8 v=va_arg(*ap,D8);uint64_t n=va_arg(*ap,uint64_t);double d=va_arg(*ap,double);aggregate_abi_variadic_scalar_check(77,n,d);REQUIRE(equal_D8(&v,&expected_D8));return 1;}
extern D8 aggregate_abi_variadic_D8_al(uint32_t,...),aggregate_abi_variadic_D8_definition(D8,uint32_t,...),aggregate_abi_variadic_D8_tail(D8,uint32_t,...),aggregate_abi_variadic_D8_direct(const void*),aggregate_abi_variadic_D8_indirect(void*,const void*);
typedef struct{float f[3];}SS12;
_Static_assert(sizeof(SS12)==12&&_Alignof(SS12)==4,"literal SS12 layout");
_Static_assert(offsetof(SS12,f[0])==0,"literal SS12.f[0] offset");
_Static_assert(offsetof(SS12,f[1])==4,"literal SS12.f[1] offset");
_Static_assert(offsetof(SS12,f[2])==8,"literal SS12.f[2] offset");
static SS12 expected_SS12;
static int equal_SS12(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,4)==0 && memcmp((const char*)a+4,(const char*)b+4,4)==0 && memcmp((const char*)a+8,(const char*)b+8,4)==0;}
SS12 aggregate_abi_variadic_SS12_read(uint32_t tag,...){va_list ap;va_start(ap,tag);SS12 v=va_arg(ap,SS12);uint64_t n=va_arg(ap,uint64_t);double d=va_arg(ap,double);va_end(ap);aggregate_abi_variadic_scalar_check(tag,n,d);REQUIRE(equal_SS12(&v,&expected_SS12));return v;}
uint32_t aggregate_abi_variadic_SS12_consume(void*raw){va_list*ap=(va_list*)raw;SS12 v=va_arg(*ap,SS12);uint64_t n=va_arg(*ap,uint64_t);double d=va_arg(*ap,double);aggregate_abi_variadic_scalar_check(77,n,d);REQUIRE(equal_SS12(&v,&expected_SS12));return 1;}
extern SS12 aggregate_abi_variadic_SS12_al(uint32_t,...),aggregate_abi_variadic_SS12_definition(SS12,uint32_t,...),aggregate_abi_variadic_SS12_tail(SS12,uint32_t,...),aggregate_abi_variadic_SS12_direct(const void*),aggregate_abi_variadic_SS12_indirect(void*,const void*);
typedef struct{double d[2];}DD16;
_Static_assert(sizeof(DD16)==16&&_Alignof(DD16)==8,"literal DD16 layout");
_Static_assert(offsetof(DD16,d[0])==0,"literal DD16.d[0] offset");
_Static_assert(offsetof(DD16,d[1])==8,"literal DD16.d[1] offset");
static DD16 expected_DD16;
static int equal_DD16(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,8)==0 && memcmp((const char*)a+8,(const char*)b+8,8)==0;}
DD16 aggregate_abi_variadic_DD16_read(uint32_t tag,...){va_list ap;va_start(ap,tag);DD16 v=va_arg(ap,DD16);uint64_t n=va_arg(ap,uint64_t);double d=va_arg(ap,double);va_end(ap);aggregate_abi_variadic_scalar_check(tag,n,d);REQUIRE(equal_DD16(&v,&expected_DD16));return v;}
uint32_t aggregate_abi_variadic_DD16_consume(void*raw){va_list*ap=(va_list*)raw;DD16 v=va_arg(*ap,DD16);uint64_t n=va_arg(*ap,uint64_t);double d=va_arg(*ap,double);aggregate_abi_variadic_scalar_check(77,n,d);REQUIRE(equal_DD16(&v,&expected_DD16));return 1;}
extern DD16 aggregate_abi_variadic_DD16_al(uint32_t,...),aggregate_abi_variadic_DD16_definition(DD16,uint32_t,...),aggregate_abi_variadic_DD16_tail(DD16,uint32_t,...),aggregate_abi_variadic_DD16_direct(const void*),aggregate_abi_variadic_DD16_indirect(void*,const void*);
typedef struct{uint64_t u;float f;}IS16;
_Static_assert(sizeof(IS16)==16&&_Alignof(IS16)==8,"literal IS16 layout");
_Static_assert(offsetof(IS16,u)==0,"literal IS16.u offset");
_Static_assert(offsetof(IS16,f)==8,"literal IS16.f offset");
static IS16 expected_IS16;
static int equal_IS16(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,8)==0 && memcmp((const char*)a+8,(const char*)b+8,4)==0;}
IS16 aggregate_abi_variadic_IS16_read(uint32_t tag,...){va_list ap;va_start(ap,tag);IS16 v=va_arg(ap,IS16);uint64_t n=va_arg(ap,uint64_t);double d=va_arg(ap,double);va_end(ap);aggregate_abi_variadic_scalar_check(tag,n,d);REQUIRE(equal_IS16(&v,&expected_IS16));return v;}
uint32_t aggregate_abi_variadic_IS16_consume(void*raw){va_list*ap=(va_list*)raw;IS16 v=va_arg(*ap,IS16);uint64_t n=va_arg(*ap,uint64_t);double d=va_arg(*ap,double);aggregate_abi_variadic_scalar_check(77,n,d);REQUIRE(equal_IS16(&v,&expected_IS16));return 1;}
extern IS16 aggregate_abi_variadic_IS16_al(uint32_t,...),aggregate_abi_variadic_IS16_definition(IS16,uint32_t,...),aggregate_abi_variadic_IS16_tail(IS16,uint32_t,...),aggregate_abi_variadic_IS16_direct(const void*),aggregate_abi_variadic_IS16_indirect(void*,const void*);
typedef struct{float f;uint64_t u;}SI16;
_Static_assert(sizeof(SI16)==16&&_Alignof(SI16)==8,"literal SI16 layout");
_Static_assert(offsetof(SI16,f)==0,"literal SI16.f offset");
_Static_assert(offsetof(SI16,u)==8,"literal SI16.u offset");
static SI16 expected_SI16;
static int equal_SI16(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,4)==0 && memcmp((const char*)a+8,(const char*)b+8,8)==0;}
SI16 aggregate_abi_variadic_SI16_read(uint32_t tag,...){va_list ap;va_start(ap,tag);SI16 v=va_arg(ap,SI16);uint64_t n=va_arg(ap,uint64_t);double d=va_arg(ap,double);va_end(ap);aggregate_abi_variadic_scalar_check(tag,n,d);REQUIRE(equal_SI16(&v,&expected_SI16));return v;}
uint32_t aggregate_abi_variadic_SI16_consume(void*raw){va_list*ap=(va_list*)raw;SI16 v=va_arg(*ap,SI16);uint64_t n=va_arg(*ap,uint64_t);double d=va_arg(*ap,double);aggregate_abi_variadic_scalar_check(77,n,d);REQUIRE(equal_SI16(&v,&expected_SI16));return 1;}
extern SI16 aggregate_abi_variadic_SI16_al(uint32_t,...),aggregate_abi_variadic_SI16_definition(SI16,uint32_t,...),aggregate_abi_variadic_SI16_tail(SI16,uint32_t,...),aggregate_abi_variadic_SI16_direct(const void*),aggregate_abi_variadic_SI16_indirect(void*,const void*);
typedef struct{uint64_t u[2];}II16;
_Static_assert(sizeof(II16)==16&&_Alignof(II16)==8,"literal II16 layout");
_Static_assert(offsetof(II16,u[0])==0,"literal II16.u[0] offset");
_Static_assert(offsetof(II16,u[1])==8,"literal II16.u[1] offset");
static II16 expected_II16;
static int equal_II16(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,8)==0 && memcmp((const char*)a+8,(const char*)b+8,8)==0;}
II16 aggregate_abi_variadic_II16_read(uint32_t tag,...){va_list ap;va_start(ap,tag);II16 v=va_arg(ap,II16);uint64_t n=va_arg(ap,uint64_t);double d=va_arg(ap,double);va_end(ap);aggregate_abi_variadic_scalar_check(tag,n,d);REQUIRE(equal_II16(&v,&expected_II16));return v;}
uint32_t aggregate_abi_variadic_II16_consume(void*raw){va_list*ap=(va_list*)raw;II16 v=va_arg(*ap,II16);uint64_t n=va_arg(*ap,uint64_t);double d=va_arg(*ap,double);aggregate_abi_variadic_scalar_check(77,n,d);REQUIRE(equal_II16(&v,&expected_II16));return 1;}
extern II16 aggregate_abi_variadic_II16_al(uint32_t,...),aggregate_abi_variadic_II16_definition(II16,uint32_t,...),aggregate_abi_variadic_II16_tail(II16,uint32_t,...),aggregate_abi_variadic_II16_direct(const void*),aggregate_abi_variadic_II16_indirect(void*,const void*);
typedef struct{_Alignas(16) float f;}N16;
_Static_assert(sizeof(N16)==16&&_Alignof(N16)==16,"literal N16 layout");
_Static_assert(offsetof(N16,f)==0,"literal N16.f offset");
static N16 expected_N16;
static int equal_N16(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,4)==0;}
N16 aggregate_abi_variadic_N16_read(uint32_t tag,...){va_list ap;va_start(ap,tag);N16 v=va_arg(ap,N16);uint64_t n=va_arg(ap,uint64_t);double d=va_arg(ap,double);va_end(ap);aggregate_abi_variadic_scalar_check(tag,n,d);REQUIRE(equal_N16(&v,&expected_N16));return v;}
uint32_t aggregate_abi_variadic_N16_consume(void*raw){va_list*ap=(va_list*)raw;N16 v=va_arg(*ap,N16);uint64_t n=va_arg(*ap,uint64_t);double d=va_arg(*ap,double);aggregate_abi_variadic_scalar_check(77,n,d);REQUIRE(equal_N16(&v,&expected_N16));return 1;}
extern N16 aggregate_abi_variadic_N16_al(uint32_t,...),aggregate_abi_variadic_N16_definition(N16,uint32_t,...),aggregate_abi_variadic_N16_tail(N16,uint32_t,...),aggregate_abi_variadic_N16_direct(const void*),aggregate_abi_variadic_N16_indirect(void*,const void*);
typedef struct{unsigned char b[23];}M23;
_Static_assert(sizeof(M23)==23&&_Alignof(M23)==1,"literal M23 layout");
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
M23 aggregate_abi_variadic_M23_read(uint32_t tag,...){va_list ap;va_start(ap,tag);M23 v=va_arg(ap,M23);uint64_t n=va_arg(ap,uint64_t);double d=va_arg(ap,double);va_end(ap);aggregate_abi_variadic_scalar_check(tag,n,d);REQUIRE(equal_M23(&v,&expected_M23));return v;}
uint32_t aggregate_abi_variadic_M23_consume(void*raw){va_list*ap=(va_list*)raw;M23 v=va_arg(*ap,M23);uint64_t n=va_arg(*ap,uint64_t);double d=va_arg(*ap,double);aggregate_abi_variadic_scalar_check(77,n,d);REQUIRE(equal_M23(&v,&expected_M23));return 1;}
extern M23 aggregate_abi_variadic_M23_al(uint32_t,...),aggregate_abi_variadic_M23_definition(M23,uint32_t,...),aggregate_abi_variadic_M23_tail(M23,uint32_t,...),aggregate_abi_variadic_M23_direct(const void*),aggregate_abi_variadic_M23_indirect(void*,const void*);
typedef struct{_Alignas(16) uint64_t u[4];}A32;
_Static_assert(sizeof(A32)==32&&_Alignof(A32)==16,"literal A32 layout");
_Static_assert(offsetof(A32,u[0])==0,"literal A32.u[0] offset");
_Static_assert(offsetof(A32,u[1])==8,"literal A32.u[1] offset");
_Static_assert(offsetof(A32,u[2])==16,"literal A32.u[2] offset");
_Static_assert(offsetof(A32,u[3])==24,"literal A32.u[3] offset");
static A32 expected_A32;
static int equal_A32(const void*a,const void*b){return memcmp((const char*)a+0,(const char*)b+0,8)==0 && memcmp((const char*)a+8,(const char*)b+8,8)==0 && memcmp((const char*)a+16,(const char*)b+16,8)==0 && memcmp((const char*)a+24,(const char*)b+24,8)==0;}
A32 aggregate_abi_variadic_A32_read(uint32_t tag,...){va_list ap;va_start(ap,tag);A32 v=va_arg(ap,A32);uint64_t n=va_arg(ap,uint64_t);double d=va_arg(ap,double);va_end(ap);aggregate_abi_variadic_scalar_check(tag,n,d);REQUIRE(equal_A32(&v,&expected_A32));return v;}
uint32_t aggregate_abi_variadic_A32_consume(void*raw){va_list*ap=(va_list*)raw;A32 v=va_arg(*ap,A32);uint64_t n=va_arg(*ap,uint64_t);double d=va_arg(*ap,double);aggregate_abi_variadic_scalar_check(77,n,d);REQUIRE(equal_A32(&v,&expected_A32));return 1;}
extern A32 aggregate_abi_variadic_A32_al(uint32_t,...),aggregate_abi_variadic_A32_definition(A32,uint32_t,...),aggregate_abi_variadic_A32_tail(A32,uint32_t,...),aggregate_abi_variadic_A32_direct(const void*),aggregate_abi_variadic_A32_indirect(void*,const void*);
void aggregate_abi_variadic_check99(uint64_t n){REQUIRE(n==99);}
uint32_t aggregate_abi_variadic_consume_A(void*raw,const SS12*ss,const I13*ii,const M23*m,uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t last){
REQUIRE(a==1&&b==2&&c==3&&d==4&&last==5);REQUIRE(equal_SS12(ss,&expected_SS12)&&equal_I13(ii,&expected_I13)&&equal_M23(m,&expected_M23));va_list*ap=raw;SS12 x=va_arg(*ap,SS12);SI16 y=va_arg(*ap,SI16);double z=va_arg(*ap,double);REQUIRE(equal_SS12(&x,&expected_SS12));REQUIRE(equal_SI16(&y,&expected_SI16));REQUIRE(z==1);return 1;}
M23 aggregate_abi_variadic_pressure_A_c(uint64_t a,uint64_t b,uint64_t c,uint64_t d,SS12 ss,I13 ii,uint64_t last,M23 m,...){va_list ap;va_start(ap,m);aggregate_abi_variadic_consume_A(&ap,&ss,&ii,&m,a,b,c,d,last);aggregate_abi_variadic_check99(va_arg(ap,uint64_t));va_end(ap);return m;}
extern M23 aggregate_abi_variadic_definition_A(uint64_t,uint64_t,uint64_t,uint64_t,SS12,I13,uint64_t,M23,...),aggregate_abi_variadic_pressure_A_bridge(void*,const void*,const void*,const void*,const void*);extern void aggregate_abi_variadic_pressure_A_target(void);
uint32_t aggregate_abi_variadic_consume_B1(void*raw,const M23*m,const N16*n){REQUIRE(equal_M23(m,&expected_M23)&&equal_N16(n,&expected_N16));va_list*ap=raw;uint64_t first=va_arg(*ap,uint64_t);N16 rec=va_arg(*ap,N16);REQUIRE(first==99);REQUIRE(equal_N16(&rec,&expected_N16));return 1;}
M23 aggregate_abi_variadic_pressure_B1_c(uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,double d1,double d2,double d3,double d4,double d5,double d6,double d7,double d8,M23 m,N16 n,uint64_t last,...){REQUIRE(a==1&&b==2&&c==3&&d==4&&e==5&&last==66);REQUIRE(d1==1&&d2==2&&d3==3&&d4==4&&d5==5&&d6==6&&d7==7&&d8==8);va_list ap;va_start(ap,last);aggregate_abi_variadic_consume_B1(&ap,&m,&n);aggregate_abi_variadic_after(va_arg(ap,uint64_t));va_end(ap);return m;}
extern M23 aggregate_abi_variadic_definition_B1(uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,double,double,double,double,double,double,double,double,M23,N16,uint64_t,...),aggregate_abi_variadic_pressure_B1_bridge(void*,const void*,const void*);extern void aggregate_abi_variadic_pressure_B1_target(void);
uint32_t aggregate_abi_variadic_consume_B2(void*raw,const M23*m,const N16*n){REQUIRE(equal_M23(m,&expected_M23)&&equal_N16(n,&expected_N16));va_list*ap=raw;N16 rec=va_arg(*ap,N16);uint64_t first=va_arg(*ap,uint64_t);REQUIRE(first==99);REQUIRE(equal_N16(&rec,&expected_N16));return 1;}
M23 aggregate_abi_variadic_pressure_B2_c(uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,double d1,double d2,double d3,double d4,double d5,double d6,double d7,double d8,M23 m,N16 n,uint64_t last,...){REQUIRE(a==1&&b==2&&c==3&&d==4&&e==5&&last==66);REQUIRE(d1==1&&d2==2&&d3==3&&d4==4&&d5==5&&d6==6&&d7==7&&d8==8);va_list ap;va_start(ap,last);aggregate_abi_variadic_consume_B2(&ap,&m,&n);aggregate_abi_variadic_after(va_arg(ap,uint64_t));va_end(ap);return m;}
extern M23 aggregate_abi_variadic_definition_B2(uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,double,double,double,double,double,double,double,double,M23,N16,uint64_t,...),aggregate_abi_variadic_pressure_B2_bridge(void*,const void*,const void*);extern void aggregate_abi_variadic_pressure_B2_target(void);
static void pressure_tests(void){memset(&expected_I13,0x44,sizeof expected_I13);memset(&expected_M23,0x67,sizeof expected_M23);uint32_t f[3]={0x3f800001,0x7fa12345,0x80000000};memcpy(&expected_SS12,f,12);memset(&expected_SI16,0,sizeof expected_SI16);memcpy(&expected_SI16.f,&f[1],4);expected_SI16.u=UINT64_C(0x9182736455463728);memset(&expected_N16,0x5a,sizeof expected_N16);memcpy(&expected_N16.f,&f[2],4);
M23 out=aggregate_abi_variadic_pressure_A_bridge(aggregate_abi_variadic_pressure_A_target,&expected_SS12,&expected_I13,&expected_M23,&expected_SI16);REQUIRE(equal_M23(&out,&expected_M23));out=aggregate_abi_variadic_definition_A(1,2,3,4,expected_SS12,expected_I13,5,expected_M23,expected_SS12,expected_SI16,1.0,UINT64_C(99));REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_pressure_B1_bridge(aggregate_abi_variadic_pressure_B1_target,&expected_M23,&expected_N16);REQUIRE(equal_M23(&out,&expected_M23));out=aggregate_abi_variadic_definition_B1(1,2,3,4,5,1.,2.,3.,4.,5.,6.,7.,8.,expected_M23,expected_N16,66,UINT64_C(99),expected_N16,UINT64_C(101));REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_pressure_B2_bridge(aggregate_abi_variadic_pressure_B2_target,&expected_M23,&expected_N16);REQUIRE(equal_M23(&out,&expected_M23));out=aggregate_abi_variadic_definition_B2(1,2,3,4,5,1.,2.,3.,4.,5.,6.,7.,8.,expected_M23,expected_N16,66,expected_N16,UINT64_C(99),UINT64_C(101));REQUIRE(equal_M23(&out,&expected_M23));
}

_Static_assert(sizeof(va_list)==24,"native live descriptor width");
void aggregate_abi_variadic_copy_list(void*to,const void*from){memcpy(to,from,sizeof(va_list));__asm__ volatile("pxor %%xmm0,%%xmm0":::"xmm0");}
void aggregate_abi_variadic_consume_count(void*raw,uint32_t count){va_list*ap=raw;for(uint32_t i=1;i<=count;++i){double value=va_arg(*ap,double);REQUIRE(value==(double)i);}}
M23 aggregate_abi_variadic_read_count(M23 m,uint32_t count,...){REQUIRE(equal_M23(&m,&expected_M23));va_list ap;va_start(ap,count);aggregate_abi_variadic_consume_count(&ap,count);va_end(ap);return m;}
extern M23 aggregate_abi_variadic_definition_count(M23,uint32_t,...);
extern M23 aggregate_abi_variadic_count0(const void*);
extern M23 aggregate_abi_variadic_count1(const void*);
extern M23 aggregate_abi_variadic_count2(const void*);
extern M23 aggregate_abi_variadic_count3(const void*);
extern M23 aggregate_abi_variadic_count4(const void*);
extern M23 aggregate_abi_variadic_count5(const void*);
extern M23 aggregate_abi_variadic_count6(const void*);
extern M23 aggregate_abi_variadic_count7(const void*);
extern M23 aggregate_abi_variadic_count8(const void*);
extern M23 aggregate_abi_variadic_count9(const void*);
extern M23 aggregate_abi_variadic_count10(const void*);
static unsigned effects;
static void consume_summary(va_list*ap,uint32_t tag){SS12 v=va_arg(*ap,SS12);uint64_t n=va_arg(*ap,uint64_t);double d=va_arg(*ap,double);aggregate_abi_variadic_scalar_check(tag,n,d);REQUIRE(equal_SS12(&v,&expected_SS12));}
uint32_t aggregate_abi_variadic_read_summary(uint32_t tag,...){va_list ap;va_start(ap,tag);consume_summary(&ap,tag);va_end(ap);return 1;}
double aggregate_abi_variadic_read_double(uint32_t tag,...){va_list ap;va_start(ap,tag);consume_summary(&ap,tag);va_end(ap);uint64_t bits=UINT64_C(0x7ff0123456789abc);double out;memcpy(&out,&bits,8);return out;}
void aggregate_abi_variadic_read_effect(uint32_t tag,...){va_list ap;va_start(ap,tag);consume_summary(&ap,tag);va_end(ap);++effects;}
extern uint32_t aggregate_abi_variadic_summary(const void*);extern double aggregate_abi_variadic_double(const void*);extern void aggregate_abi_variadic_effect(const void*);
static void count_tests(void){M23 out;
out=aggregate_abi_variadic_count0(&expected_M23);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_definition_count(expected_M23,0);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_count1(&expected_M23);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_definition_count(expected_M23,1,1.0);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_count2(&expected_M23);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_definition_count(expected_M23,2,1.0,2.0);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_count3(&expected_M23);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_definition_count(expected_M23,3,1.0,2.0,3.0);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_count4(&expected_M23);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_definition_count(expected_M23,4,1.0,2.0,3.0,4.0);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_count5(&expected_M23);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_definition_count(expected_M23,5,1.0,2.0,3.0,4.0,5.0);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_count6(&expected_M23);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_definition_count(expected_M23,6,1.0,2.0,3.0,4.0,5.0,6.0);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_count7(&expected_M23);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_definition_count(expected_M23,7,1.0,2.0,3.0,4.0,5.0,6.0,7.0);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_count8(&expected_M23);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_definition_count(expected_M23,8,1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_count9(&expected_M23);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_definition_count(expected_M23,9,1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_count10(&expected_M23);REQUIRE(equal_M23(&out,&expected_M23));
out=aggregate_abi_variadic_definition_count(expected_M23,10,1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0);REQUIRE(equal_M23(&out,&expected_M23));
REQUIRE(aggregate_abi_variadic_summary(&expected_SS12)==1);double d=aggregate_abi_variadic_double(&expected_SS12);uint64_t raw;memcpy(&raw,&d,8);REQUIRE(raw==UINT64_C(0x7ff0123456789abc));unsigned before=effects;aggregate_abi_variadic_effect(&expected_SS12);REQUIRE(effects==before+1);
}

extern SS12 aggregate_abi_variadic_recurse(SS12,uint32_t,...);extern M23 aggregate_abi_variadic_loop(void*,const void*,uint32_t);extern uint64_t aggregate_abi_variadic_scalar_caller(void*,const void*,...);
static void lifetime_tests(void){SS12 out=aggregate_abi_variadic_recurse(expected_SS12,20,UINT64_C(99));REQUIRE(equal_SS12(&out,&expected_SS12));M23 m=aggregate_abi_variadic_loop(aggregate_abi_variadic_M23_al,&expected_M23,7);REQUIRE(equal_M23(&m,&expected_M23));REQUIRE(aggregate_abi_variadic_scalar_caller(aggregate_abi_variadic_SS12_al,&expected_SS12,UINT64_C(99),1.0)==(UINT64_C(99)^UINT64_C(0x3ff0000000000000)));}

extern B3 aggregate_abi_variadic_zero(const void*);
B3 aggregate_abi_variadic_zero_read(uint32_t tag,...){REQUIRE(tag==77);va_list ap;va_start(ap,tag);B3 v=va_arg(ap,B3);REQUIRE(equal_B3(&v,&expected_B3));REQUIRE(va_arg(ap,uint64_t)==99);va_end(ap);return v;}
static void zero_test(void){B3 v={{17,29,43}};expected_B3=v;void*m;size_t len;unsigned char*g=guarded(sizeof v,&m,&len);memcpy(g,&v,sizeof v);REQUIRE(mprotect((char*)m+len/3,len/3,PROT_READ)==0);B3 out=aggregate_abi_variadic_zero(g);REQUIRE(equal_B3(&v,&out));REQUIRE(equal_B3(&v,g));REQUIRE(munmap(m,len)==0);}
extern SI16 aggregate_abi_variadic_pressure_C(void*,const void*,const void*);
extern SI16 aggregate_abi_variadic_pressure_C_entry(uint32_t,double,double,double,double,double,double,double,double,...);
SI16 aggregate_abi_variadic_pressure_C_read(uint32_t tag,double d1,double d2,double d3,double d4,double d5,double d6,double d7,double d8,...){REQUIRE(tag==77);REQUIRE(d1==1&&d2==2&&d3==3&&d4==4&&d5==5&&d6==6&&d7==7&&d8==8);va_list ap;va_start(ap,d8);SI16 si=va_arg(ap,SI16);REQUIRE(equal_SI16(&si,&expected_SI16));REQUIRE(va_arg(ap,uint64_t)==99);I13 ii=va_arg(ap,I13);REQUIRE(equal_I13(&ii,&expected_I13));REQUIRE(va_arg(ap,double)==1);va_end(ap);return si;}
extern SS12 aggregate_abi_variadic_quoted_common(void*,const void*),aggregate_abi_variadic_quoted_ordinary(void*,const void*);
static void combination_tests(void){SI16 out=aggregate_abi_variadic_pressure_C(aggregate_abi_variadic_pressure_C_entry,&expected_SI16,&expected_I13);REQUIRE(equal_SI16(&out,&expected_SI16));out=aggregate_abi_variadic_pressure_C(aggregate_abi_variadic_pressure_C_read,&expected_SI16,&expected_I13);REQUIRE(equal_SI16(&out,&expected_SI16));SS12 ss=aggregate_abi_variadic_quoted_common(aggregate_abi_variadic_SS12_al,&expected_SS12);REQUIRE(equal_SS12(&ss,&expected_SS12));ss=aggregate_abi_variadic_quoted_ordinary(aggregate_abi_variadic_SS12_al,&expected_SS12);REQUIRE(equal_SS12(&ss,&expected_SS12));}
extern SS12 aggregate_abi_variadic_SS12_isolation(SS12,...);
void aggregate_abi_variadic_mutate_SS12(void*p){REQUIRE((uintptr_t)p%4==0);REQUIRE(equal_SS12(p,&expected_SS12));uint32_t raw=UINT32_C(0x3f800000);memcpy(p,&raw,4);}
extern N16 aggregate_abi_variadic_N16_isolation(N16,...);
void aggregate_abi_variadic_mutate_N16(void*p){REQUIRE((uintptr_t)p%16==0);REQUIRE(equal_N16(p,&expected_N16));uint32_t raw=UINT32_C(0x3f800000);memcpy(p,&raw,4);}
extern M23 aggregate_abi_variadic_M23_isolation(M23,...);
void aggregate_abi_variadic_mutate_M23(void*p){M23*v=p;REQUIRE(equal_M23(v,&expected_M23));v->b[0]^=0x5a;}
static void isolation_tests(void){{SS12 source=expected_SS12,want=source;uint32_t raw=UINT32_C(0x3f800000);memcpy(&want,&raw,4);void*m;size_t len;unsigned char*g=guarded(sizeof source,&m,&len);memcpy(g,&source,sizeof source);REQUIRE(mprotect((char*)m+len/3,len/3,PROT_READ)==0);SS12 out=aggregate_abi_variadic_SS12_isolation(*(const SS12*)g,UINT64_C(99));REQUIRE(equal_SS12(&out,&want));REQUIRE(equal_SS12(g,&source));REQUIRE(equal_SS12(&expected_SS12,&source));REQUIRE(munmap(m,len)==0);}{N16 source=expected_N16,want=source;uint32_t raw=UINT32_C(0x3f800000);memcpy(&want,&raw,4);void*m;size_t len;unsigned char*g=guarded(sizeof source,&m,&len);memcpy(g,&source,sizeof source);REQUIRE(mprotect((char*)m+len/3,len/3,PROT_READ)==0);N16 out=aggregate_abi_variadic_N16_isolation(*(const N16*)g,UINT64_C(99));REQUIRE(equal_N16(&out,&want));REQUIRE(equal_N16(g,&source));REQUIRE(equal_N16(&expected_N16,&source));REQUIRE(munmap(m,len)==0);}{M23 source=expected_M23,want=source;want.b[0]^=0x5a;void*m;size_t len;unsigned char*g=guarded(sizeof source,&m,&len);memcpy(g,&source,sizeof source);REQUIRE(mprotect((char*)m+len/3,len/3,PROT_READ)==0);M23 out=aggregate_abi_variadic_M23_isolation(*(const M23*)g,UINT64_C(99));REQUIRE(equal_M23(&out,&want));REQUIRE(equal_M23(g,&source));REQUIRE(equal_M23(&expected_M23,&source));REQUIRE(munmap(m,len)==0);}}
int main(void){unsigned old_mxcsr,probe_mxcsr;__asm__ volatile("stmxcsr %0":"=m"(old_mxcsr));probe_mxcsr=(old_mxcsr|0x1f80u)&~0x3fu;__asm__ volatile("ldmxcsr %0"::"m"(probe_mxcsr));pressure_tests();count_tests();lifetime_tests();zero_test();combination_tests();isolation_tests();
for(unsigned n=0;n<8;++n){B3 v;memset(&v,0x5a,sizeof v);uint64_t b0=bits[(n+0)%8];memcpy((char*)&v+0,&b0,1);uint64_t b1=bits[(n+1)%8];memcpy((char*)&v+1,&b1,1);uint64_t b2=bits[(n+2)%8];memcpy((char*)&v+2,&b2,1);expected_B3=v;B3 out=aggregate_abi_variadic_B3_direct(&v);REQUIRE(equal_B3(&v,&out));out=aggregate_abi_variadic_B3_indirect(aggregate_abi_variadic_B3_al,&v);REQUIRE(equal_B3(&v,&out));out=aggregate_abi_variadic_B3_indirect(aggregate_abi_variadic_B3_read,&v);REQUIRE(equal_B3(&v,&out));out=aggregate_abi_variadic_B3_definition(v,77,UINT64_C(99),1.0);REQUIRE(equal_B3(&v,&out));out=aggregate_abi_variadic_B3_tail(v,77,v,UINT64_C(99),1.0,UINT64_C(101));REQUIRE(equal_B3(&v,&out));void*m;size_t len;unsigned char*g=guarded(sizeof v,&m,&len);memcpy(g,&v,sizeof v);REQUIRE(mprotect((char*)m+len/3,len/3,PROT_READ)==0);out=aggregate_abi_variadic_B3_indirect(aggregate_abi_variadic_B3_al,g);REQUIRE(equal_B3(&v,&out));REQUIRE(equal_B3(&v,g));REQUIRE(munmap(m,len)==0);}
for(unsigned n=0;n<8;++n){I13 v;memset(&v,0x5a,sizeof v);uint64_t b0=bits[(n+0)%8];memcpy((char*)&v+0,&b0,1);uint64_t b1=bits[(n+1)%8];memcpy((char*)&v+1,&b1,1);uint64_t b2=bits[(n+2)%8];memcpy((char*)&v+2,&b2,1);uint64_t b3=bits[(n+3)%8];memcpy((char*)&v+3,&b3,1);uint64_t b4=bits[(n+4)%8];memcpy((char*)&v+4,&b4,1);uint64_t b5=bits[(n+5)%8];memcpy((char*)&v+5,&b5,1);uint64_t b6=bits[(n+6)%8];memcpy((char*)&v+6,&b6,1);uint64_t b7=bits[(n+7)%8];memcpy((char*)&v+7,&b7,1);uint64_t b8=bits[(n+8)%8];memcpy((char*)&v+8,&b8,1);uint64_t b9=bits[(n+9)%8];memcpy((char*)&v+9,&b9,1);uint64_t b10=bits[(n+10)%8];memcpy((char*)&v+10,&b10,1);uint64_t b11=bits[(n+11)%8];memcpy((char*)&v+11,&b11,1);uint64_t b12=bits[(n+12)%8];memcpy((char*)&v+12,&b12,1);expected_I13=v;I13 out=aggregate_abi_variadic_I13_direct(&v);REQUIRE(equal_I13(&v,&out));out=aggregate_abi_variadic_I13_indirect(aggregate_abi_variadic_I13_al,&v);REQUIRE(equal_I13(&v,&out));out=aggregate_abi_variadic_I13_indirect(aggregate_abi_variadic_I13_read,&v);REQUIRE(equal_I13(&v,&out));out=aggregate_abi_variadic_I13_definition(v,77,UINT64_C(99),1.0);REQUIRE(equal_I13(&v,&out));out=aggregate_abi_variadic_I13_tail(v,77,v,UINT64_C(99),1.0,UINT64_C(101));REQUIRE(equal_I13(&v,&out));void*m;size_t len;unsigned char*g=guarded(sizeof v,&m,&len);memcpy(g,&v,sizeof v);REQUIRE(mprotect((char*)m+len/3,len/3,PROT_READ)==0);out=aggregate_abi_variadic_I13_indirect(aggregate_abi_variadic_I13_al,g);REQUIRE(equal_I13(&v,&out));REQUIRE(equal_I13(&v,g));REQUIRE(munmap(m,len)==0);}
for(unsigned n=0;n<8;++n){W8 v;memset(&v,0x5a,sizeof v);uint64_t b0=bits[(n+0)%8];memcpy((char*)&v+0,&b0,4);uint64_t b1=bits[(n+1)%8];memcpy((char*)&v+4,&b1,4);expected_W8=v;W8 out=aggregate_abi_variadic_W8_direct(&v);REQUIRE(equal_W8(&v,&out));out=aggregate_abi_variadic_W8_indirect(aggregate_abi_variadic_W8_al,&v);REQUIRE(equal_W8(&v,&out));out=aggregate_abi_variadic_W8_indirect(aggregate_abi_variadic_W8_read,&v);REQUIRE(equal_W8(&v,&out));out=aggregate_abi_variadic_W8_definition(v,77,UINT64_C(99),1.0);REQUIRE(equal_W8(&v,&out));out=aggregate_abi_variadic_W8_tail(v,77,v,UINT64_C(99),1.0,UINT64_C(101));REQUIRE(equal_W8(&v,&out));void*m;size_t len;unsigned char*g=guarded(sizeof v,&m,&len);memcpy(g,&v,sizeof v);REQUIRE(mprotect((char*)m+len/3,len/3,PROT_READ)==0);out=aggregate_abi_variadic_W8_indirect(aggregate_abi_variadic_W8_al,g);REQUIRE(equal_W8(&v,&out));REQUIRE(equal_W8(&v,g));REQUIRE(munmap(m,len)==0);}
for(unsigned n=0;n<8;++n){S4 v;memset(&v,0x5a,sizeof v);uint64_t b0=bits[(n+0)%8];memcpy((char*)&v+0,&b0,4);expected_S4=v;S4 out=aggregate_abi_variadic_S4_direct(&v);REQUIRE(equal_S4(&v,&out));out=aggregate_abi_variadic_S4_indirect(aggregate_abi_variadic_S4_al,&v);REQUIRE(equal_S4(&v,&out));out=aggregate_abi_variadic_S4_indirect(aggregate_abi_variadic_S4_read,&v);REQUIRE(equal_S4(&v,&out));out=aggregate_abi_variadic_S4_definition(v,77,UINT64_C(99),1.0);REQUIRE(equal_S4(&v,&out));out=aggregate_abi_variadic_S4_tail(v,77,v,UINT64_C(99),1.0,UINT64_C(101));REQUIRE(equal_S4(&v,&out));void*m;size_t len;unsigned char*g=guarded(sizeof v,&m,&len);memcpy(g,&v,sizeof v);REQUIRE(mprotect((char*)m+len/3,len/3,PROT_READ)==0);out=aggregate_abi_variadic_S4_indirect(aggregate_abi_variadic_S4_al,g);REQUIRE(equal_S4(&v,&out));REQUIRE(equal_S4(&v,g));REQUIRE(munmap(m,len)==0);}
for(unsigned n=0;n<8;++n){D8 v;memset(&v,0x5a,sizeof v);uint64_t b0=bits[(n+0)%8];memcpy((char*)&v+0,&b0,8);expected_D8=v;D8 out=aggregate_abi_variadic_D8_direct(&v);REQUIRE(equal_D8(&v,&out));out=aggregate_abi_variadic_D8_indirect(aggregate_abi_variadic_D8_al,&v);REQUIRE(equal_D8(&v,&out));out=aggregate_abi_variadic_D8_indirect(aggregate_abi_variadic_D8_read,&v);REQUIRE(equal_D8(&v,&out));out=aggregate_abi_variadic_D8_definition(v,77,UINT64_C(99),1.0);REQUIRE(equal_D8(&v,&out));out=aggregate_abi_variadic_D8_tail(v,77,v,UINT64_C(99),1.0,UINT64_C(101));REQUIRE(equal_D8(&v,&out));void*m;size_t len;unsigned char*g=guarded(sizeof v,&m,&len);memcpy(g,&v,sizeof v);REQUIRE(mprotect((char*)m+len/3,len/3,PROT_READ)==0);out=aggregate_abi_variadic_D8_indirect(aggregate_abi_variadic_D8_al,g);REQUIRE(equal_D8(&v,&out));REQUIRE(equal_D8(&v,g));REQUIRE(munmap(m,len)==0);}
for(unsigned n=0;n<8;++n){SS12 v;memset(&v,0x5a,sizeof v);uint64_t b0=bits[(n+0)%8];memcpy((char*)&v+0,&b0,4);uint64_t b1=bits[(n+1)%8];memcpy((char*)&v+4,&b1,4);uint64_t b2=bits[(n+2)%8];memcpy((char*)&v+8,&b2,4);expected_SS12=v;SS12 out=aggregate_abi_variadic_SS12_direct(&v);REQUIRE(equal_SS12(&v,&out));out=aggregate_abi_variadic_SS12_indirect(aggregate_abi_variadic_SS12_al,&v);REQUIRE(equal_SS12(&v,&out));out=aggregate_abi_variadic_SS12_indirect(aggregate_abi_variadic_SS12_read,&v);REQUIRE(equal_SS12(&v,&out));out=aggregate_abi_variadic_SS12_definition(v,77,UINT64_C(99),1.0);REQUIRE(equal_SS12(&v,&out));out=aggregate_abi_variadic_SS12_tail(v,77,v,UINT64_C(99),1.0,UINT64_C(101));REQUIRE(equal_SS12(&v,&out));void*m;size_t len;unsigned char*g=guarded(sizeof v,&m,&len);memcpy(g,&v,sizeof v);REQUIRE(mprotect((char*)m+len/3,len/3,PROT_READ)==0);out=aggregate_abi_variadic_SS12_indirect(aggregate_abi_variadic_SS12_al,g);REQUIRE(equal_SS12(&v,&out));REQUIRE(equal_SS12(&v,g));REQUIRE(munmap(m,len)==0);}
for(unsigned n=0;n<8;++n){DD16 v;memset(&v,0x5a,sizeof v);uint64_t b0=bits[(n+0)%8];memcpy((char*)&v+0,&b0,8);uint64_t b1=bits[(n+1)%8];memcpy((char*)&v+8,&b1,8);expected_DD16=v;DD16 out=aggregate_abi_variadic_DD16_direct(&v);REQUIRE(equal_DD16(&v,&out));out=aggregate_abi_variadic_DD16_indirect(aggregate_abi_variadic_DD16_al,&v);REQUIRE(equal_DD16(&v,&out));out=aggregate_abi_variadic_DD16_indirect(aggregate_abi_variadic_DD16_read,&v);REQUIRE(equal_DD16(&v,&out));out=aggregate_abi_variadic_DD16_definition(v,77,UINT64_C(99),1.0);REQUIRE(equal_DD16(&v,&out));out=aggregate_abi_variadic_DD16_tail(v,77,v,UINT64_C(99),1.0,UINT64_C(101));REQUIRE(equal_DD16(&v,&out));void*m;size_t len;unsigned char*g=guarded(sizeof v,&m,&len);memcpy(g,&v,sizeof v);REQUIRE(mprotect((char*)m+len/3,len/3,PROT_READ)==0);out=aggregate_abi_variadic_DD16_indirect(aggregate_abi_variadic_DD16_al,g);REQUIRE(equal_DD16(&v,&out));REQUIRE(equal_DD16(&v,g));REQUIRE(munmap(m,len)==0);}
for(unsigned n=0;n<8;++n){IS16 v;memset(&v,0x5a,sizeof v);uint64_t b0=bits[(n+0)%8];memcpy((char*)&v+0,&b0,8);uint64_t b1=bits[(n+1)%8];memcpy((char*)&v+8,&b1,4);expected_IS16=v;IS16 out=aggregate_abi_variadic_IS16_direct(&v);REQUIRE(equal_IS16(&v,&out));out=aggregate_abi_variadic_IS16_indirect(aggregate_abi_variadic_IS16_al,&v);REQUIRE(equal_IS16(&v,&out));out=aggregate_abi_variadic_IS16_indirect(aggregate_abi_variadic_IS16_read,&v);REQUIRE(equal_IS16(&v,&out));out=aggregate_abi_variadic_IS16_definition(v,77,UINT64_C(99),1.0);REQUIRE(equal_IS16(&v,&out));out=aggregate_abi_variadic_IS16_tail(v,77,v,UINT64_C(99),1.0,UINT64_C(101));REQUIRE(equal_IS16(&v,&out));void*m;size_t len;unsigned char*g=guarded(sizeof v,&m,&len);memcpy(g,&v,sizeof v);REQUIRE(mprotect((char*)m+len/3,len/3,PROT_READ)==0);out=aggregate_abi_variadic_IS16_indirect(aggregate_abi_variadic_IS16_al,g);REQUIRE(equal_IS16(&v,&out));REQUIRE(equal_IS16(&v,g));REQUIRE(munmap(m,len)==0);}
for(unsigned n=0;n<8;++n){SI16 v;memset(&v,0x5a,sizeof v);uint64_t b0=bits[(n+0)%8];memcpy((char*)&v+0,&b0,4);uint64_t b1=bits[(n+1)%8];memcpy((char*)&v+8,&b1,8);expected_SI16=v;SI16 out=aggregate_abi_variadic_SI16_direct(&v);REQUIRE(equal_SI16(&v,&out));out=aggregate_abi_variadic_SI16_indirect(aggregate_abi_variadic_SI16_al,&v);REQUIRE(equal_SI16(&v,&out));out=aggregate_abi_variadic_SI16_indirect(aggregate_abi_variadic_SI16_read,&v);REQUIRE(equal_SI16(&v,&out));out=aggregate_abi_variadic_SI16_definition(v,77,UINT64_C(99),1.0);REQUIRE(equal_SI16(&v,&out));out=aggregate_abi_variadic_SI16_tail(v,77,v,UINT64_C(99),1.0,UINT64_C(101));REQUIRE(equal_SI16(&v,&out));void*m;size_t len;unsigned char*g=guarded(sizeof v,&m,&len);memcpy(g,&v,sizeof v);REQUIRE(mprotect((char*)m+len/3,len/3,PROT_READ)==0);out=aggregate_abi_variadic_SI16_indirect(aggregate_abi_variadic_SI16_al,g);REQUIRE(equal_SI16(&v,&out));REQUIRE(equal_SI16(&v,g));REQUIRE(munmap(m,len)==0);}
for(unsigned n=0;n<8;++n){II16 v;memset(&v,0x5a,sizeof v);uint64_t b0=bits[(n+0)%8];memcpy((char*)&v+0,&b0,8);uint64_t b1=bits[(n+1)%8];memcpy((char*)&v+8,&b1,8);expected_II16=v;II16 out=aggregate_abi_variadic_II16_direct(&v);REQUIRE(equal_II16(&v,&out));out=aggregate_abi_variadic_II16_indirect(aggregate_abi_variadic_II16_al,&v);REQUIRE(equal_II16(&v,&out));out=aggregate_abi_variadic_II16_indirect(aggregate_abi_variadic_II16_read,&v);REQUIRE(equal_II16(&v,&out));out=aggregate_abi_variadic_II16_definition(v,77,UINT64_C(99),1.0);REQUIRE(equal_II16(&v,&out));out=aggregate_abi_variadic_II16_tail(v,77,v,UINT64_C(99),1.0,UINT64_C(101));REQUIRE(equal_II16(&v,&out));void*m;size_t len;unsigned char*g=guarded(sizeof v,&m,&len);memcpy(g,&v,sizeof v);REQUIRE(mprotect((char*)m+len/3,len/3,PROT_READ)==0);out=aggregate_abi_variadic_II16_indirect(aggregate_abi_variadic_II16_al,g);REQUIRE(equal_II16(&v,&out));REQUIRE(equal_II16(&v,g));REQUIRE(munmap(m,len)==0);}
for(unsigned n=0;n<8;++n){N16 v;memset(&v,0x5a,sizeof v);uint64_t b0=bits[(n+0)%8];memcpy((char*)&v+0,&b0,4);expected_N16=v;N16 out=aggregate_abi_variadic_N16_direct(&v);REQUIRE(equal_N16(&v,&out));out=aggregate_abi_variadic_N16_indirect(aggregate_abi_variadic_N16_al,&v);REQUIRE(equal_N16(&v,&out));out=aggregate_abi_variadic_N16_indirect(aggregate_abi_variadic_N16_read,&v);REQUIRE(equal_N16(&v,&out));out=aggregate_abi_variadic_N16_definition(v,77,UINT64_C(99),1.0);REQUIRE(equal_N16(&v,&out));out=aggregate_abi_variadic_N16_tail(v,77,v,UINT64_C(99),1.0,UINT64_C(101));REQUIRE(equal_N16(&v,&out));void*m;size_t len;unsigned char*g=guarded(sizeof v,&m,&len);memcpy(g,&v,sizeof v);REQUIRE(mprotect((char*)m+len/3,len/3,PROT_READ)==0);out=aggregate_abi_variadic_N16_indirect(aggregate_abi_variadic_N16_al,g);REQUIRE(equal_N16(&v,&out));REQUIRE(equal_N16(&v,g));REQUIRE(munmap(m,len)==0);}
for(unsigned n=0;n<8;++n){M23 v;memset(&v,0x5a,sizeof v);uint64_t b0=bits[(n+0)%8];memcpy((char*)&v+0,&b0,1);uint64_t b1=bits[(n+1)%8];memcpy((char*)&v+1,&b1,1);uint64_t b2=bits[(n+2)%8];memcpy((char*)&v+2,&b2,1);uint64_t b3=bits[(n+3)%8];memcpy((char*)&v+3,&b3,1);uint64_t b4=bits[(n+4)%8];memcpy((char*)&v+4,&b4,1);uint64_t b5=bits[(n+5)%8];memcpy((char*)&v+5,&b5,1);uint64_t b6=bits[(n+6)%8];memcpy((char*)&v+6,&b6,1);uint64_t b7=bits[(n+7)%8];memcpy((char*)&v+7,&b7,1);uint64_t b8=bits[(n+8)%8];memcpy((char*)&v+8,&b8,1);uint64_t b9=bits[(n+9)%8];memcpy((char*)&v+9,&b9,1);uint64_t b10=bits[(n+10)%8];memcpy((char*)&v+10,&b10,1);uint64_t b11=bits[(n+11)%8];memcpy((char*)&v+11,&b11,1);uint64_t b12=bits[(n+12)%8];memcpy((char*)&v+12,&b12,1);uint64_t b13=bits[(n+13)%8];memcpy((char*)&v+13,&b13,1);uint64_t b14=bits[(n+14)%8];memcpy((char*)&v+14,&b14,1);uint64_t b15=bits[(n+15)%8];memcpy((char*)&v+15,&b15,1);uint64_t b16=bits[(n+16)%8];memcpy((char*)&v+16,&b16,1);uint64_t b17=bits[(n+17)%8];memcpy((char*)&v+17,&b17,1);uint64_t b18=bits[(n+18)%8];memcpy((char*)&v+18,&b18,1);uint64_t b19=bits[(n+19)%8];memcpy((char*)&v+19,&b19,1);uint64_t b20=bits[(n+20)%8];memcpy((char*)&v+20,&b20,1);uint64_t b21=bits[(n+21)%8];memcpy((char*)&v+21,&b21,1);uint64_t b22=bits[(n+22)%8];memcpy((char*)&v+22,&b22,1);expected_M23=v;M23 out=aggregate_abi_variadic_M23_direct(&v);REQUIRE(equal_M23(&v,&out));out=aggregate_abi_variadic_M23_indirect(aggregate_abi_variadic_M23_al,&v);REQUIRE(equal_M23(&v,&out));out=aggregate_abi_variadic_M23_indirect(aggregate_abi_variadic_M23_read,&v);REQUIRE(equal_M23(&v,&out));out=aggregate_abi_variadic_M23_definition(v,77,UINT64_C(99),1.0);REQUIRE(equal_M23(&v,&out));out=aggregate_abi_variadic_M23_tail(v,77,v,UINT64_C(99),1.0,UINT64_C(101));REQUIRE(equal_M23(&v,&out));void*m;size_t len;unsigned char*g=guarded(sizeof v,&m,&len);memcpy(g,&v,sizeof v);REQUIRE(mprotect((char*)m+len/3,len/3,PROT_READ)==0);out=aggregate_abi_variadic_M23_indirect(aggregate_abi_variadic_M23_al,g);REQUIRE(equal_M23(&v,&out));REQUIRE(equal_M23(&v,g));REQUIRE(munmap(m,len)==0);}
for(unsigned n=0;n<8;++n){A32 v;memset(&v,0x5a,sizeof v);uint64_t b0=bits[(n+0)%8];memcpy((char*)&v+0,&b0,8);uint64_t b1=bits[(n+1)%8];memcpy((char*)&v+8,&b1,8);uint64_t b2=bits[(n+2)%8];memcpy((char*)&v+16,&b2,8);uint64_t b3=bits[(n+3)%8];memcpy((char*)&v+24,&b3,8);expected_A32=v;A32 out=aggregate_abi_variadic_A32_direct(&v);REQUIRE(equal_A32(&v,&out));out=aggregate_abi_variadic_A32_indirect(aggregate_abi_variadic_A32_al,&v);REQUIRE(equal_A32(&v,&out));out=aggregate_abi_variadic_A32_indirect(aggregate_abi_variadic_A32_read,&v);REQUIRE(equal_A32(&v,&out));out=aggregate_abi_variadic_A32_definition(v,77,UINT64_C(99),1.0);REQUIRE(equal_A32(&v,&out));out=aggregate_abi_variadic_A32_tail(v,77,v,UINT64_C(99),1.0,UINT64_C(101));REQUIRE(equal_A32(&v,&out));void*m;size_t len;unsigned char*g=guarded(sizeof v,&m,&len);memcpy(g,&v,sizeof v);REQUIRE(mprotect((char*)m+len/3,len/3,PROT_READ)==0);out=aggregate_abi_variadic_A32_indirect(aggregate_abi_variadic_A32_al,g);REQUIRE(equal_A32(&v,&out));REQUIRE(equal_A32(&v,g));REQUIRE(munmap(m,len)==0);}
unsigned after_mxcsr;__asm__ volatile("stmxcsr %0":"=m"(after_mxcsr));REQUIRE(after_mxcsr==probe_mxcsr);__asm__ volatile("ldmxcsr %0"::"m"(old_mxcsr));printf("aggregate variadic %u independent assertions passed\n",checks);return 0;}
