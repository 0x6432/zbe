#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
extern int provider_marker(void), provider_guards(void), provider_probe(unsigned, ...);
extern void *provider_list(void), *provider_box_list(void);
extern uint64_t got_va_start(uint32_t, ...), got_va_address(void);
#define CHECK(x) do { if (!(x)) { dprintf(2, "FAIL line %d: %s\n", __LINE__, #x); return 1; } } while (0)
#define PROBE() provider_probe(42u, (uint32_t)7, (uint64_t)1000, \
    (uint32_t)19, (uint64_t)2000, (uint32_t)29, (uint64_t)3000, (uint32_t)37, \
    11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0)
int main(int argc, char **argv) {
    CHECK(argc == 2);
    int expected = atoi(argv[1]);
    void *p = dlsym(RTLD_DEFAULT, "n11_vlist");
    CHECK(p && p == provider_list() && p == provider_box_list());
    CHECK(got_va_address() == (uint64_t)(uintptr_t)p);
    CHECK(provider_marker() == expected && provider_guards());
    CHECK(PROBE());
    CHECK(provider_guards());
    CHECK(got_va_start(42u, (uint32_t)7, (uint64_t)1000, 11.0) == 1018);
    /* The descriptor written by got_va_start is now stale: check only its
     * guards, then reinitialize it before any further descriptor access. */
    CHECK(provider_guards());
    CHECK(PROBE());
    CHECK(provider_guards());
    puts("guarded varargs checks passed");
    return 0;
}
