#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* This fixture requires the Linux x86-64 SysV va_list ABI. The alias exposes
 * precisely the descriptor, with guard words immediately before and after. */
struct guarded { uint64_t before; va_list ap; uint64_t after; };
_Static_assert(sizeof(va_list) == 24 && offsetof(struct guarded, ap) == 8 &&
               offsetof(struct guarded, after) == 32, "SysV descriptor required");
struct guarded n11_box = {
    .before = UINT64_C(0x1122334455667788),
    .after = UINT64_C(0x8877665544332211)
};
__asm__(".globl n11_vlist\n.type n11_vlist,@object\n"
        ".set n11_vlist,n11_box+8\n.size n11_vlist,24\n");
extern va_list n11_vlist;
extern uint32_t got_va_word(void);
extern uint64_t got_va_long(void);
extern double got_va_double(void);

int provider_marker(void) { return MARKER; }
int provider_guards(void) {
    return n11_box.before == UINT64_C(0x1122334455667788) &&
           n11_box.after == UINT64_C(0x8877665544332211);
}
void *provider_list(void) { return n11_vlist; }
void *provider_box_list(void) { return n11_box.ap; }

/* Both descriptors refer to a live C variadic frame. The C cursor is an
 * independent ABI oracle; no fabricated descriptor or aggregate is executed. */
int provider_probe(unsigned tag, ...) {
    va_list reference;
    va_start(n11_vlist, tag);
    va_copy(reference, n11_vlist);
    int ok = 1;
#define CHECK_ARG(type, function, expected) do { \
    type c = va_arg(reference, type), actual = function(); \
    if (c != (expected) || actual != c) { \
        fprintf(stderr, "vararg mismatch at line %d\n", __LINE__); ok = 0; \
    } \
} while (0)
    CHECK_ARG(uint32_t, got_va_word, 7u);
    CHECK_ARG(uint64_t, got_va_long, UINT64_C(1000));
    CHECK_ARG(uint32_t, got_va_word, 19u);
    CHECK_ARG(uint64_t, got_va_long, UINT64_C(2000));
    CHECK_ARG(uint32_t, got_va_word, 29u);
    CHECK_ARG(uint64_t, got_va_long, UINT64_C(3000));
    CHECK_ARG(uint32_t, got_va_word, 37u);
    CHECK_ARG(double, got_va_double, 11.0);
    CHECK_ARG(double, got_va_double, 12.0);
    CHECK_ARG(double, got_va_double, 13.0);
    CHECK_ARG(double, got_va_double, 14.0);
    CHECK_ARG(double, got_va_double, 15.0);
    CHECK_ARG(double, got_va_double, 16.0);
    CHECK_ARG(double, got_va_double, 17.0);
    CHECK_ARG(double, got_va_double, 18.0);
    CHECK_ARG(double, got_va_double, 19.0);
    CHECK_ARG(double, got_va_double, 20.0);
#undef CHECK_ARG
    if (memcmp(n11_vlist, reference, sizeof(va_list)) != 0 || !provider_guards()) {
        fprintf(stderr, "descriptor cursor or guards differ\n"); ok = 0;
    }
    va_end(reference);
    va_end(n11_vlist);
    return ok;
}
