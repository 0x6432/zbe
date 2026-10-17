# Owned byte strings in data definitions

Byte (`b`) data groups accept quoted strings mixed with numeric byte items.
Strings expand to their exact decoded bytes: **no automatic NUL terminator**, no
per-string padding, no Unicode conversion or normalization. Append an explicit
`b 0` when a native API needs a C string. Empty strings occupy zero bytes and
promise neither uniqueness nor readable storage. Raw nonescape source bytes,
including UTF-8, are preserved; raw CR/LF and unescaped internal quotes are invalid.

```text
export data $message = { b "hello world", b 0 }
data $bytes = { b "A\000B" 255 "\x41", h 8755 }
```

## Explicit bounded escape syntax

- `\"` and `\\` produce quote and backslash.
- `\a`, `\b`, `\f`, `\n`, `\r`, `\t`, `\v` produce their ASCII control bytes.
- One through three octal digits produce one byte; values above255 are rejected.
  Digits after the third are ordinary subsequent bytes. `\0` is a zero byte.
- `\x` requires **exactly two** hexadecimal digits for one byte. Following input
  starts another byte: `\x414` is `A` then `4`, not a variable-width hex escape.

Unknown/truncated/out-of-range escapes, escaped physical line breaks and Unicode
escape forms are rejected with `invalid_string`. This deliberately documented
subset is not a promise to reproduce C/GNU assembler string-recovery or all QBE
spellings. Quoted global names, string operands inside functions and strings in
half/word/long/single/double/zero groups remain unsupported.

## Ownership, bounds and safe emission

`data.Item.bytes` is a byte slice whose published contents belong to its Data
owner. `Data.append` **copies** a caller's byte item; it does not borrow the input
or transfer arbitrary ownership. Copy and item-table reservations complete before
the item/length is published. A table-allocation failure frees the new copy.
Data.deinit frees every published byte item before freeing the item table. As with
other public IR, manual mutations must preserve ownership; do not replace an owned
slice with borrowed or already-freed memory, shallow-copy owners, or bypass deinit.

The frontend's two-pass decoder validates/counts before allocation and checks the
remaining16MiB object budget. It decodes into a temporary owned slice, appends a
copy, then frees the temporary on success/error. This is explicit transient memory,
not hidden borrowing or a performance claim. DATA.md's16MiB/object and64MiB/module
payload limits include decoded bytes. They still exclude allocator metadata and
assembly/source/token allocations. Empty strings may still consume item metadata.

AMD64 emission writes bounded-width numeric `.byte` lines only, never raw `.ascii`
source or escape spellings. Quotes, backslashes, newlines, comment markers and
assembler-like payload bytes cannot become directives/symbol definitions. The
existing checked data-name policy, writable `.data`/zero-only `.bss` (DATA-BSS.md),
alignment, exact ELF sizes
and PIE/non-PIE executable contracts remain unchanged. This does not implement a
sandbox, memory permissions model, full data language or shared-object policy.

Definitions do not create implicit interpreter globals: by default a reached symbol returns
`UnsupportedSymbolAddress`, including Image/stack-enabled evaluation. No host
pointer conversion, Image initialization/growth or native fallback is added.

## Independent checks

`generate_data_string_oracle.py --check` reproduces eight objects and358 expected
bytes independently from explicit Python byte values, not parser/assembler output.
It covers every byte0..255, UTF-8, embedded zeros, empty strings, mixed fields,
control/octal/exact-hex escapes and assembler-like content. The older numeric
oracle/generators and fixtures remain unchanged.

Six new unit tests cover independent exact bytes, source/caller lifetime, copy/
table failure atomicity and retry, decoded payload caps, invalid escapes/classes,
interpreter refusal/Image preservation and exhaustive allocation-failure cleanup
through the decoder, owned Data, parser and emitter.

`native_string_check.py` accepts the existing three flags and checks **1,455
non-PIE +1,463 PIE** byte/address/mutation/call results per combination. Whole
objects are compared before/after C and compiled writes, including all256 bytes.
It additionally checks **16** ELF size/binding/alignment records, **2** linked
injection exclusions, **2** data-only links and **48** rejection/output-preservation
cases. Only obsolete b-string negatives in existing tests/harnesses were changed
to unsupported h-string forms; their counts/assertions remain intact. Actual
full matrix/CI results are recorded in HANDOFF.md, not assumed here.

## Explicit module-global evaluation

Opt-in initialized numeric/zero/string globals use a separate owned synthetic
model (INTERPRETER-GLOBALS.md). Defaults still refuse symbols; symbolic initializers
and function/external addresses remain unsupported. Image ownership and native
linker/stack behavior do not change.
