#include <stdio.h>
long f14(int, int, long);
long f13(int, long);
long f12(long);
long f11(long, int, long, long);
long f10(long, long);
long f9(long, int);
long f8(long, long, long, long);
long f7(int, long);
long f6(int);
long f5(int, long);
long f4(long, int, long);
long f3(long);
long f2(long, int, int, int);
long f1(int);
long f0(long, long, int, int);
int main(void) { int bad = 0;
	if ((unsigned long)f0((long)458367763LL, (long)-29LL, (int)-1LL, (int)-1622617344LL) != 12394705990021507087UL) { printf("f0 mismatch\n"); bad++; }
	if ((unsigned long)f1((int)603918760LL) != 17291495319133480UL) { printf("f1 mismatch\n"); bad++; }
	if ((unsigned long)f2((long)-24LL, (int)32LL, (int)1289972073LL, (int)-471204446LL) != 17457748778902595203UL) { printf("f2 mismatch\n"); bad++; }
	if ((unsigned long)f3((long)-32LL) != 18446744073680207264UL) { printf("f3 mismatch\n"); bad++; }
	if ((unsigned long)f4((long)-1773677758LL, (int)20LL, (long)-1537366248LL) != 10160813705376569737UL) { printf("f4 mismatch\n"); bad++; }
	if ((unsigned long)f5((int)6LL, (long)-2110583891LL) != 7029394495908366190UL) { printf("f5 mismatch\n"); bad++; }
	if ((unsigned long)f6((int)2135247182LL) != 6278056484729787079UL) { printf("f6 mismatch\n"); bad++; }
	if ((unsigned long)f7((int)33LL, (long)-50LL) != 18446744072809027058UL) { printf("f7 mismatch\n"); bad++; }
	if ((unsigned long)f8((long)-1526001851LL, (long)-249847341LL, (long)14LL, (long)-21LL) != 3754982089000878630UL) { printf("f8 mismatch\n"); bad++; }
	if ((unsigned long)f9((long)-17LL, (int)-46LL) != 5664950310457759866UL) { printf("f9 mismatch\n"); bad++; }
	if ((unsigned long)f10((long)-348076823LL, (long)41LL) != 16610794002745888926UL) { printf("f10 mismatch\n"); bad++; }
	if ((unsigned long)f11((long)-370642405LL, (int)1769849190LL, (long)132609135LL, (long)-1686113630LL) != 16475567452546514210UL) { printf("f11 mismatch\n"); bad++; }
	if ((unsigned long)f12((long)-2097080633LL) != 3344194131995031695UL) { printf("f12 mismatch\n"); bad++; }
	if ((unsigned long)f13((int)-519232650LL, (long)-39LL) != 1304977134517420202UL) { printf("f13 mismatch\n"); bad++; }
	if ((unsigned long)f14((int)-1988586949LL, (int)18LL, (long)1883711465LL) != 10853579330629634159UL) { printf("f14 mismatch\n"); bad++; }
	return bad != 0;
}
