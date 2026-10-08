#!/bin/sh
# Edge-case CLI / parser / codegen tests: run C qbe and Zig qbe on each case
# and require identical stdout, exit status and (binary-name-normalised) stderr.
# Usage: sh tools/edge.sh            (needs /data/qbe-c/qbe or QBEREF)
cd "$(dirname "$0")/.."
REF=${QBEREF:-/data/qbe-c/qbe}
ZIG=$PWD/zig-out/bin/qbe
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
pass=0; fail=0

# run NAME ARGS... ; stdin from $W/in if present
run() {
  name=$1; shift
  for side in c z; do
    if [ $side = c ]; then b=$REF; else b=$ZIG; fi
    ( cd "$W" && "$b" "$@" < "$W/in" > "$W/$side.out" 2> "$W/$side.err"; echo $? > "$W/$side.rc" )
    sed -e "s#$b#qbe#g" -e 's#^[^ :]*qbe:#qbe:#' "$W/$side.err" > "$W/$side.errn"
    sed -i "s#$b#qbe#g" "$W/$side.out"
    if [ -f "$W/o.s" ]; then mv "$W/o.s" "$W/$side.o"; else : > "$W/$side.o"; fi
  done
  if cmp -s "$W/c.out" "$W/z.out" && cmp -s "$W/c.rc" "$W/z.rc" \
     && cmp -s "$W/c.errn" "$W/z.errn" && cmp -s "$W/c.o" "$W/z.o"; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); echo "FAIL: $name (rc c=$(cat $W/c.rc) z=$(cat $W/z.rc))"
    diff "$W/c.errn" "$W/z.errn" | head -5
    diff "$W/c.out" "$W/z.out" | head -5
  fi
}

# case NAME 'ssa text' [extra args]  -- run source through all targets
case_() {
  cname=$1; src=$2; shift 2
  printf '%s\n' "$src" > "$W/t.ssa"; : > "$W/in"
  for t in amd64_sysv amd64_apple amd64_win arm64 arm64_apple rv64; do
    run "$cname[$t]" -t $t "$@" t.ssa
  done
}

: > "$W/in"
# ---- command line ----
run help -h
run no_args_stdin_empty -
run unknown_target -t nope x.ssa
run missing_t_arg -t
run missing_o_arg -o
run missing_d_arg -d
run unknown_option -z
run missing_file does_not_exist.ssa
run double_dash_stdin -- -
printf 'function w $f() {\n@s\n\tret 0\n}\n' > "$W/in"
run stdin_program -
run stdin_default
run output_file -o o.s -
run output_dash -o - -
run target_list_help -t help
for d in P M N C F A I L S R; do run "dump_$d" -d $d -; done
run dump_all -d PMNCFAILSR -
printf 'function w $f() {\n@s\n\tret 0\n}\n' > "$W/a.ssa"
printf 'function w $g() {\n@s\n\tret 1\n}\n' > "$W/b.ssa"
: > "$W/in"
run two_files a.ssa b.ssa
run file_then_missing a.ssa missing.ssa

# ---- lexer / parser edge cases ----
case_ empty ''
case_ only_comments '# nothing here
# at all'
case_ only_whitespace '

	   
'
case_ no_trailing_newline 'function $f() {
@s
	ret
}'
case_ unknown_keyword 'functoin $f() {
@s
	ret
}'
case_ unterminated_string 'data $d = { b "abc }'
case_ string_escapes 'data $d = { b "a\\n\\t\\"\\\\z", b 0 }'
case_ utf8_string 'data $d = { b "héllo ✓", b 0 }'
case_ missing_ret 'function $f() {
@s
}'
case_ missing_block_label 'function $f() {
	ret
}'
case_ duplicate_label 'function $f() {
@a
	jmp @a
@a
	ret
}'
case_ undefined_label 'function $f() {
@s
	jmp @nope
}'
case_ undefined_type 'function :nope $f() {
@s
	ret
}'
case_ bad_class 'function q $f() {
@s
	ret 0
}'
case_ class_mismatch 'function w $f() {
@s
	%x =w add 1, 2
	ret %x
}
function w $g() {
@s
	%y =l copy 1
	%z =w add %y, 2
	ret %z
}'
case_ tmp_used_undefined 'function w $f() {
@s
	ret %u
}'
case_ huge_constants 'function l $f() {
@s
	%a =l add 9223372036854775807, 1
	%b =l sub -9223372036854775808, 1
	%c =l add %a, 18446744073709551615
	%d =l xor %b, %c
	ret %d
}'
case_ float_constants 'function d $f() {
@s
	%a =d add d_0, d_-0
	%b =d mul %a, d_1e308
	%c =s copy s_3.4e38
	%e =d exts %c
	%g =d add %b, %e
	ret %g
}'
case_ long_identifier "function \$$(printf 'x%.0s' $(seq 1 300))() {
@s
	ret
}"
case_ quoted_symbol 'export function $"weird name"() {
@s
	ret
}'

# ---- data definitions ----
case_ data_empty 'data $d = { }'
case_ data_zero 'data $d = { z 0 }'
case_ data_mixed 'data $d = align 16 { b 1, h 2, w 3, l 4, s s_1.5, d d_2.5, z 7, l $d + 8 }'
case_ data_thread 'thread data $t = { w 42 }'
case_ data_section 'section ".mysec" "aw" data $d = { w 1 }'
case_ data_export_common 'export data $d = { z 16 }'

# ---- aggregate types ----
case_ type_empty 'type :e = { }
function $f(:e %p) {
@s
	ret
}'
case_ type_nested 'type :in = { w, s }
type :out = align 16 { b 3, :in, l 2 }
function :out $f(:out %p) {
@s
	ret %p
}'
case_ type_union 'type :u = { { w } { d } { b 12 } }
function :u $f(:u %p, w %x) {
@s
	ret %p
}'
case_ type_opaque 'type :o = align 32 { 64 }
function $f(:o %p) {
@s
	ret
}'

# ---- control flow / ssa ----
case_ unreachable_blocks 'function w $f(w %x) {
@s
	ret 1
@dead
	%y =w add %x, 1
	jmp @dead
}'
case_ infinite_loop 'function $f() {
@s
	jmp @s
}'
case_ hlt 'function $f() {
@s
	hlt
}'
case_ jnz_same_target 'function w $f(w %c) {
@s
	jnz %c, @a, @a
@a
	ret %c
}'
case_ phi_many 'function w $f(w %n) {
@s
@loop
	%i =w phi @s 0, @loop %i1
	%a =w phi @s 1, @loop %b
	%b =w phi @s 2, @loop %a
	%i1 =w add %i, 1
	%c =w csltw %i1, %n
	jnz %c, @loop, @end
@end
	%r =w add %a, %b
	ret %r
}'
case_ many_live_values "function l \$f(l %x) {
@s
$(for i in $(seq 1 60); do echo "	%v$i =l add %x, $i"; done)
$(echo "	%s0 =l copy 0"; for i in $(seq 1 60); do echo "	%s$i =l add %s$((i-1)), %v$i"; done)
	ret %s60
}"
case_ div_by_const 'function w $f(w %x) {
@s
	%a =w div %x, 0
	%b =w rem %x, -1
	%c =w udiv %x, 1
	%d =w add %a, %b
	%e =w add %d, %c
	ret %e
}'
case_ shift_wide 'function l $f(l %x) {
@s
	%a =l shl %x, 64
	%b =l sar %a, 63
	%c =w shr 1, 33
	%d =l extuw %c
	%e =l add %b, %d
	ret %e
}'
case_ calls_varargs 'function w $f(l %fmt, ...) {
@s
	%ap =l alloc8 32
	vastart %ap
	%a =w vaarg %ap
	ret %a
}
function w $g() {
@s
	%r =w call $f(l 0, ..., w 1, d d_2, l 3)
	ret %r
}'
case_ call_many_args "function l \$g() {
@s
	%r =l call \$h($(for i in $(seq 1 20); do printf 'l %d, ' $i; done; for i in $(seq 1 12); do printf 'd d_%d, ' $i; done)w 0)
	ret %r
}"
case_ alloc_dyn 'function l $f(l %n) {
@s
	%p =l alloc16 %n
	storel 1, %p
	%v =l loadl %p
	ret %v
}'
case_ blit 'function $f(l %a, l %b) {
@s
	blit %a, %b, 37
	ret
}'
case_ env_param 'function w $f(env %e, w %x) {
@s
	ret %x
}'
case_ dbgloc 'dbgfile "a.c"
function w $f() {
@s
	dbgloc 3
	dbgloc 4, 7
	ret 0
}'

printf 'edge: %d passed, %d failed\n' $pass $fail
[ $fail -eq 0 ]
