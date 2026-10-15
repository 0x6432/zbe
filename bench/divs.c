/* integer -> decimal conversion and digit sums: unsigned /10 %10, signed /8 %8 */
#include <stdio.h>

static unsigned utoa(unsigned v, char *b) {
	unsigned n = 0;
	do { b[n++] = '0' + v % 10; v /= 10; } while (v);
	return n;
}

int main(void) {
	char buf[16];
	unsigned long sum = 0;
	unsigned s = 0;
	for (unsigned i = 0; i < 12000000; i++) {
		unsigned n = utoa(i * 2654435761u, buf);
		sum += n + buf[0] + (i % 1000) + (i / 100);
		/* Define the intended 32-bit wrap without signed overflow or an
		   out-of-range unsigned-to-signed conversion. */
		unsigned bits = i * 40503u - 1000000u;
		int x = bits < 0x80000000u ? (int)bits : -1 - (int)~bits;
		s += (unsigned)(x / 8 + x % 8 + x / 64);
	}
	printf("%lu %u\n", sum, s);
	return 0;
}
