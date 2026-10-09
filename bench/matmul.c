/* integer matrix multiply */
#include <stdio.h>

#define N 200
static long a[N][N], b[N][N], c[N][N];

int main(void) {
	for (int i = 0; i < N; i++)
		for (int j = 0; j < N; j++) { a[i][j] = (i * 7 + j) % 13; b[i][j] = (i + j * 3) % 11; }
	long s = 0;
	for (int r = 0; r < 6; r++) {
		for (int i = 0; i < N; i++)
			for (int j = 0; j < N; j++) {
				long t = 0;
				for (int k = 0; k < N; k++) t += a[i][k] * b[k][j];
				c[i][j] = t;
			}
		s += c[r][r] + c[N - 1 - r][r];
		a[r][r] += 1;
	}
	printf("%ld\n", s);
	return 0;
}
