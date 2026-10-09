/* insertion + shell sort on pseudo-random ints (branches, loads/stores) */
#include <stdio.h>

#define N 300000
static int v[N];

int main(void) {
	unsigned s = 12345;
	long chk = 0;
	for (int r = 0; r < 4; r++) {
		for (int i = 0; i < N; i++) { s = s * 1103515245u + 12345u; v[i] = (int)(s >> 1); }
		for (int gap = N / 2; gap > 0; gap /= 2)
			for (int i = gap; i < N; i++) {
				int t = v[i], j = i;
				while (j >= gap && v[j - gap] > t) { v[j] = v[j - gap]; j -= gap; }
				v[j] = t;
			}
		chk += v[0] / 4 + v[N / 2] % 1000 + v[N - 1] / 1024;
	}
	printf("%ld\n", chk);
	return 0;
}
