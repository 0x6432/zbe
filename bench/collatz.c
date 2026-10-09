/* longest Collatz chain: signed /2, %2 and *3 */
#include <stdio.h>

int main(void) {
	long best = 0, arg = 0;
	for (long n = 1; n < 1500000; n++) {
		long x = n, len = 0;
		while (x != 1) {
			if (x % 2 == 0) x = x / 2;
			else x = 3 * x + 1;
			len++;
		}
		if (len > best) { best = len; arg = n; }
	}
	printf("%ld %ld\n", arg, best);
	return 0;
}
