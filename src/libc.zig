//! Minimal hand-written libc bindings used by the one-to-one translation.
const std = @import("std");

pub const FILE = opaque {};
pub const VaList = std.builtin.VaList;

pub extern var stdin: *FILE;
pub extern var stdout: *FILE;
pub extern var stderr: *FILE;
pub extern var optarg: [*c]u8;
pub extern var optind: c_int;

pub extern fn fprintf(f: *FILE, fmt: [*c]const u8, ...) c_int;
pub extern fn printf(fmt: [*c]const u8, ...) c_int;
pub extern fn vfprintf(f: *FILE, fmt: [*c]const u8, ap: VaList) c_int;
pub extern fn vsnprintf(s: [*c]u8, n: usize, fmt: [*c]const u8, ap: VaList) c_int;
pub extern fn snprintf(s: [*c]u8, n: usize, fmt: [*c]const u8, ...) c_int;
pub extern fn sprintf(s: [*c]u8, fmt: [*c]const u8, ...) c_int;
pub extern fn fputs(s: [*c]const u8, f: *FILE) c_int;
pub extern fn puts(s: [*c]const u8) c_int;
pub extern fn fputc(c: c_int, f: *FILE) c_int;
pub extern fn putc(c: c_int, f: *FILE) c_int;
pub extern fn fgetc(f: *FILE) c_int;
pub extern fn getc(f: *FILE) c_int;
pub extern fn ungetc(c: c_int, f: *FILE) c_int;
pub extern fn fopen(path: [*c]const u8, mode: [*c]const u8) ?*FILE;
pub extern fn fclose(f: *FILE) c_int;
pub extern fn fwrite(p: ?*const anyopaque, sz: usize, n: usize, f: *FILE) usize;

pub extern fn exit(code: c_int) noreturn;
pub extern fn abort() noreturn;
pub extern fn calloc(n: usize, sz: usize) ?*anyopaque;
pub extern fn malloc(sz: usize) ?*anyopaque;
pub extern fn realloc(p: ?*anyopaque, sz: usize) ?*anyopaque;
pub extern fn free(p: ?*anyopaque) void;
pub extern fn qsort(base: ?*anyopaque, n: usize, sz: usize, cmp: *const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int) void;

pub extern fn memcpy(d: ?*anyopaque, s: ?*const anyopaque, n: usize) ?*anyopaque;
pub extern fn memmove(d: ?*anyopaque, s: ?*const anyopaque, n: usize) ?*anyopaque;
pub extern fn memset(d: ?*anyopaque, c: c_int, n: usize) ?*anyopaque;
pub extern fn memcmp(a: ?*const anyopaque, b: ?*const anyopaque, n: usize) c_int;
pub extern fn strcmp(a: [*c]const u8, b: [*c]const u8) c_int;
pub extern fn strncmp(a: [*c]const u8, b: [*c]const u8, n: usize) c_int;
pub extern fn strlen(s: [*c]const u8) usize;
pub extern fn strcpy(d: [*c]u8, s: [*c]const u8) [*c]u8;
pub extern fn strncpy(d: [*c]u8, s: [*c]const u8, n: usize) [*c]u8;
pub extern fn strchr(s: [*c]const u8, c: c_int) [*c]u8;
pub extern fn strtod(s: [*c]const u8, end: [*c][*c]u8) f64;
pub extern fn strtof(s: [*c]const u8, end: [*c][*c]u8) f32;
pub extern fn strtoll(s: [*c]const u8, end: [*c][*c]u8, base: c_int) c_longlong;
pub extern fn getopt(argc: c_int, argv: [*c]const [*c]u8, opts: [*c]const u8) c_int;

pub extern fn isalpha(c: c_int) c_int;
pub extern fn isdigit(c: c_int) c_int;
pub extern fn isspace(c: c_int) c_int;
pub extern fn toupper(c: c_int) c_int;
pub extern fn fscanf(f: *FILE, fmt: [*c]const u8, ...) c_int;
pub extern fn isblank(c: c_int) c_int;
pub const EOF: c_int = -1;
