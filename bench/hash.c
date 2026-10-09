/* FNV-1a and multiply-shift hashing over a buffer, with power-of-two buckets */
#include <stdio.h>

static unsigned char data[1 << 16];
static unsigned buckets[1024];

int main(void) {
	for (unsigned i = 0; i < sizeof data; i++) data[i] = (unsigned char)(i * 131u + (i >> 5));
	unsigned long acc = 0;
	for (int r = 0; r < 300; r++) {
		unsigned h = 2166136261u;
		for (unsigned i = 0; i < sizeof data; i++) {
			h ^= data[i];
			h *= 16777619u;
			unsigned long m = (unsigned long)h * 8 + (unsigned long)i * 1;
			buckets[(m >> 3) % 1024]++;
		}
		acc += h + buckets[r % 1024];
	}
	printf("%lu\n", acc);
	return 0;
}
