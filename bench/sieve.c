/* sieve of Eratosthenes, repeated */
#include <stdio.h>
#include <string.h>

#define N 2000000
static char comp[N + 1];

int main(void) {
	long total = 0;
	for (int r = 0; r < 12; r++) {
		memset(comp, 0, sizeof comp);
		long cnt = 0;
		for (long i = 2; i <= N; i++) {
			if (comp[i]) continue;
			cnt++;
			for (long j = i * i; j <= N; j += i) comp[j] = 1;
		}
		total += cnt;
	}
	printf("%ld\n", total);
	return 0;
}
