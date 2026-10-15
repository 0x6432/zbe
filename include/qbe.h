/* qbe (Zig port) as a library: link with -lqbe (zig-out/lib/libqbe.a) and libc.
 *
 * Not thread-safe. Input errors are printed to stderr and returned as 3.
 * Internal invariant failures still abort.
 */
#ifndef QBE_H
#define QBE_H
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Compile `len` bytes of IL. target: NULL = compiler default (query CLI -t ?);
 * opt: 0 = patched-C-reference-identical output, 1, 2 (recommended).
 * On success returns 0; *out is a NUL-terminated assembly text to release
 * with qbe_free, *outlen (if non-NULL) its length.
 * Returns 1 for an unknown target, 2 if output allocation fails, 3 for invalid
 * input. Internal allocation/invariant failures can still abort. */
int qbe_compile(const char *text, size_t len, const char *target, int opt,
                char **out, size_t *outlen);
void qbe_free(char *out);

/* i-th target name (list order does not select the host default);
 * returns 1 when i is past the end. */
int qbe_target(int i, const char **name);
const char *qbe_version(void);

#ifdef __cplusplus
}
#endif
#endif
