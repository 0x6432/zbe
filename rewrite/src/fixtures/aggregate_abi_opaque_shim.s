.text
.globl opaque_forward
.type opaque_forward,@function
opaque_forward:
movq %rdi,%r11
movq %rsi,%rdi
movq %rdx,%rsi
movq %rcx,%rdx
movq %r8,%rcx
jmp *%r11
.size opaque_forward,.-opaque_forward
.globl opaque_B1_recurse
.type opaque_B1_recurse,@function
opaque_B1_recurse:
movq $3,%r8
jmp opaque_B1_recursive
.size opaque_B1_recurse,.-opaque_B1_recurse
.globl opaque_B1_invoke
.type opaque_B1_invoke,@function
opaque_B1_invoke:
pushq %rbp
movq %rsp,%rbp
subq $48,%rsp
movq %rdi,-8(%rbp)
movq %rsi,-16(%rbp)
movq %rdx,%rsi
movq %rsp,%rdi
movq $1,%rcx
rep movsb
movq -16(%rbp),%rdi
movq $77,%rsi
movabsq $4607182418800017408,%rax
movq %rax,%xmm0
call *-8(%rbp)
leave
ret
.size opaque_B1_invoke,.-opaque_B1_invoke
.globl opaque_B1_asm
.type opaque_B1_asm,@function
opaque_B1_asm:
pushq %rbp
movq %rsp,%rbp
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $1,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_B1_asm,.-opaque_B1_asm
.globl opaque_B1_env
.type opaque_B1_env,@function
opaque_B1_env:
pushq %rbp
movq %rsp,%rbp
cmpq $2748,%rax
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $1,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_B1_env,.-opaque_B1_env
.globl opaque_B1_al
.type opaque_B1_al,@function
opaque_B1_al:
pushq %rbp
movq %rsp,%rbp
cmpb $1,%al
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $1,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_B1_al,.-opaque_B1_al
.globl opaque_A1_recurse
.type opaque_A1_recurse,@function
opaque_A1_recurse:
movq $3,%r8
jmp opaque_A1_recursive
.size opaque_A1_recurse,.-opaque_A1_recurse
.globl opaque_A1_invoke
.type opaque_A1_invoke,@function
opaque_A1_invoke:
pushq %rbp
movq %rsp,%rbp
subq $48,%rsp
movq %rdi,-8(%rbp)
movq %rsi,-16(%rbp)
movq %rdx,%rsi
movq %rsp,%rdi
movq $1,%rcx
rep movsb
movq -16(%rbp),%rdi
movq $77,%rsi
movabsq $4607182418800017408,%rax
movq %rax,%xmm0
call *-8(%rbp)
leave
ret
.size opaque_A1_invoke,.-opaque_A1_invoke
.globl opaque_A1_asm
.type opaque_A1_asm,@function
opaque_A1_asm:
pushq %rbp
movq %rsp,%rbp
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $1,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A1_asm,.-opaque_A1_asm
.globl opaque_A1_env
.type opaque_A1_env,@function
opaque_A1_env:
pushq %rbp
movq %rsp,%rbp
cmpq $2748,%rax
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $1,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A1_env,.-opaque_A1_env
.globl opaque_A1_al
.type opaque_A1_al,@function
opaque_A1_al:
pushq %rbp
movq %rsp,%rbp
cmpb $1,%al
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $1,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A1_al,.-opaque_A1_al
.globl opaque_B3_recurse
.type opaque_B3_recurse,@function
opaque_B3_recurse:
movq $3,%r8
jmp opaque_B3_recursive
.size opaque_B3_recurse,.-opaque_B3_recurse
.globl opaque_B3_invoke
.type opaque_B3_invoke,@function
opaque_B3_invoke:
pushq %rbp
movq %rsp,%rbp
subq $48,%rsp
movq %rdi,-8(%rbp)
movq %rsi,-16(%rbp)
movq %rdx,%rsi
movq %rsp,%rdi
movq $3,%rcx
rep movsb
movq -16(%rbp),%rdi
movq $77,%rsi
movabsq $4607182418800017408,%rax
movq %rax,%xmm0
call *-8(%rbp)
leave
ret
.size opaque_B3_invoke,.-opaque_B3_invoke
.globl opaque_B3_asm
.type opaque_B3_asm,@function
opaque_B3_asm:
pushq %rbp
movq %rsp,%rbp
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $3,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_B3_asm,.-opaque_B3_asm
.globl opaque_B3_env
.type opaque_B3_env,@function
opaque_B3_env:
pushq %rbp
movq %rsp,%rbp
cmpq $2748,%rax
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $3,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_B3_env,.-opaque_B3_env
.globl opaque_B3_al
.type opaque_B3_al,@function
opaque_B3_al:
pushq %rbp
movq %rsp,%rbp
cmpb $1,%al
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $3,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_B3_al,.-opaque_B3_al
.globl opaque_A8_recurse
.type opaque_A8_recurse,@function
opaque_A8_recurse:
movq $3,%r8
jmp opaque_A8_recursive
.size opaque_A8_recurse,.-opaque_A8_recurse
.globl opaque_A8_invoke
.type opaque_A8_invoke,@function
opaque_A8_invoke:
pushq %rbp
movq %rsp,%rbp
subq $48,%rsp
movq %rdi,-8(%rbp)
movq %rsi,-16(%rbp)
movq %rdx,%rsi
movq %rsp,%rdi
movq $8,%rcx
rep movsb
movq -16(%rbp),%rdi
movq $77,%rsi
movabsq $4607182418800017408,%rax
movq %rax,%xmm0
call *-8(%rbp)
leave
ret
.size opaque_A8_invoke,.-opaque_A8_invoke
.globl opaque_A8_asm
.type opaque_A8_asm,@function
opaque_A8_asm:
pushq %rbp
movq %rsp,%rbp
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $8,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A8_asm,.-opaque_A8_asm
.globl opaque_A8_env
.type opaque_A8_env,@function
opaque_A8_env:
pushq %rbp
movq %rsp,%rbp
cmpq $2748,%rax
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $8,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A8_env,.-opaque_A8_env
.globl opaque_A8_al
.type opaque_A8_al,@function
opaque_A8_al:
pushq %rbp
movq %rsp,%rbp
cmpb $1,%al
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $8,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A8_al,.-opaque_A8_al
.globl opaque_B9_recurse
.type opaque_B9_recurse,@function
opaque_B9_recurse:
movq $3,%r8
jmp opaque_B9_recursive
.size opaque_B9_recurse,.-opaque_B9_recurse
.globl opaque_B9_invoke
.type opaque_B9_invoke,@function
opaque_B9_invoke:
pushq %rbp
movq %rsp,%rbp
subq $48,%rsp
movq %rdi,-8(%rbp)
movq %rsi,-16(%rbp)
movq %rdx,%rsi
movq %rsp,%rdi
movq $9,%rcx
rep movsb
movq -16(%rbp),%rdi
movq $77,%rsi
movabsq $4607182418800017408,%rax
movq %rax,%xmm0
call *-8(%rbp)
leave
ret
.size opaque_B9_invoke,.-opaque_B9_invoke
.globl opaque_B9_asm
.type opaque_B9_asm,@function
opaque_B9_asm:
pushq %rbp
movq %rsp,%rbp
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $9,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_B9_asm,.-opaque_B9_asm
.globl opaque_B9_env
.type opaque_B9_env,@function
opaque_B9_env:
pushq %rbp
movq %rsp,%rbp
cmpq $2748,%rax
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $9,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_B9_env,.-opaque_B9_env
.globl opaque_B9_al
.type opaque_B9_al,@function
opaque_B9_al:
pushq %rbp
movq %rsp,%rbp
cmpb $1,%al
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $9,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_B9_al,.-opaque_B9_al
.globl opaque_A13_recurse
.type opaque_A13_recurse,@function
opaque_A13_recurse:
movq $3,%r8
jmp opaque_A13_recursive
.size opaque_A13_recurse,.-opaque_A13_recurse
.globl opaque_A13_invoke
.type opaque_A13_invoke,@function
opaque_A13_invoke:
pushq %rbp
movq %rsp,%rbp
subq $48,%rsp
movq %rdi,-8(%rbp)
movq %rsi,-16(%rbp)
movq %rdx,%rsi
movq %rsp,%rdi
movq $13,%rcx
rep movsb
movq -16(%rbp),%rdi
movq $77,%rsi
movabsq $4607182418800017408,%rax
movq %rax,%xmm0
call *-8(%rbp)
leave
ret
.size opaque_A13_invoke,.-opaque_A13_invoke
.globl opaque_A13_asm
.type opaque_A13_asm,@function
opaque_A13_asm:
pushq %rbp
movq %rsp,%rbp
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $13,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A13_asm,.-opaque_A13_asm
.globl opaque_A13_env
.type opaque_A13_env,@function
opaque_A13_env:
pushq %rbp
movq %rsp,%rbp
cmpq $2748,%rax
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $13,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A13_env,.-opaque_A13_env
.globl opaque_A13_al
.type opaque_A13_al,@function
opaque_A13_al:
pushq %rbp
movq %rsp,%rbp
cmpb $1,%al
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $13,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A13_al,.-opaque_A13_al
.globl opaque_A16_recurse
.type opaque_A16_recurse,@function
opaque_A16_recurse:
movq $3,%r8
jmp opaque_A16_recursive
.size opaque_A16_recurse,.-opaque_A16_recurse
.globl opaque_A16_invoke
.type opaque_A16_invoke,@function
opaque_A16_invoke:
pushq %rbp
movq %rsp,%rbp
subq $48,%rsp
movq %rdi,-8(%rbp)
movq %rsi,-16(%rbp)
movq %rdx,%rsi
movq %rsp,%rdi
movq $16,%rcx
rep movsb
movq -16(%rbp),%rdi
movq $77,%rsi
movabsq $4607182418800017408,%rax
movq %rax,%xmm0
call *-8(%rbp)
leave
ret
.size opaque_A16_invoke,.-opaque_A16_invoke
.globl opaque_A16_asm
.type opaque_A16_asm,@function
opaque_A16_asm:
pushq %rbp
movq %rsp,%rbp
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $16,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A16_asm,.-opaque_A16_asm
.globl opaque_A16_env
.type opaque_A16_env,@function
opaque_A16_env:
pushq %rbp
movq %rsp,%rbp
cmpq $2748,%rax
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $16,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A16_env,.-opaque_A16_env
.globl opaque_A16_al
.type opaque_A16_al,@function
opaque_A16_al:
pushq %rbp
movq %rsp,%rbp
cmpb $1,%al
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $16,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A16_al,.-opaque_A16_al
.globl opaque_B17_recurse
.type opaque_B17_recurse,@function
opaque_B17_recurse:
movq $3,%r8
jmp opaque_B17_recursive
.size opaque_B17_recurse,.-opaque_B17_recurse
.globl opaque_B17_invoke
.type opaque_B17_invoke,@function
opaque_B17_invoke:
pushq %rbp
movq %rsp,%rbp
subq $64,%rsp
movq %rdi,-8(%rbp)
movq %rsi,-16(%rbp)
movq %rdx,%rsi
movq %rsp,%rdi
movq $17,%rcx
rep movsb
movq -16(%rbp),%rdi
movq $77,%rsi
movabsq $4607182418800017408,%rax
movq %rax,%xmm0
call *-8(%rbp)
leave
ret
.size opaque_B17_invoke,.-opaque_B17_invoke
.globl opaque_B17_asm
.type opaque_B17_asm,@function
opaque_B17_asm:
pushq %rbp
movq %rsp,%rbp
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $17,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_B17_asm,.-opaque_B17_asm
.globl opaque_B17_env
.type opaque_B17_env,@function
opaque_B17_env:
pushq %rbp
movq %rsp,%rbp
cmpq $2748,%rax
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $17,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_B17_env,.-opaque_B17_env
.globl opaque_B17_al
.type opaque_B17_al,@function
opaque_B17_al:
pushq %rbp
movq %rsp,%rbp
cmpb $1,%al
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $17,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_B17_al,.-opaque_B17_al
.globl opaque_A17_recurse
.type opaque_A17_recurse,@function
opaque_A17_recurse:
movq $3,%r8
jmp opaque_A17_recursive
.size opaque_A17_recurse,.-opaque_A17_recurse
.globl opaque_A17_invoke
.type opaque_A17_invoke,@function
opaque_A17_invoke:
pushq %rbp
movq %rsp,%rbp
subq $64,%rsp
movq %rdi,-8(%rbp)
movq %rsi,-16(%rbp)
movq %rdx,%rsi
movq %rsp,%rdi
movq $17,%rcx
rep movsb
movq -16(%rbp),%rdi
movq $77,%rsi
movabsq $4607182418800017408,%rax
movq %rax,%xmm0
call *-8(%rbp)
leave
ret
.size opaque_A17_invoke,.-opaque_A17_invoke
.globl opaque_A17_asm
.type opaque_A17_asm,@function
opaque_A17_asm:
pushq %rbp
movq %rsp,%rbp
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $17,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A17_asm,.-opaque_A17_asm
.globl opaque_A17_env
.type opaque_A17_env,@function
opaque_A17_env:
pushq %rbp
movq %rsp,%rbp
cmpq $2748,%rax
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $17,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A17_env,.-opaque_A17_env
.globl opaque_A17_al
.type opaque_A17_al,@function
opaque_A17_al:
pushq %rbp
movq %rsp,%rbp
cmpb $1,%al
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $17,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A17_al,.-opaque_A17_al
.globl opaque_A32_recurse
.type opaque_A32_recurse,@function
opaque_A32_recurse:
movq $3,%r8
jmp opaque_A32_recursive
.size opaque_A32_recurse,.-opaque_A32_recurse
.globl opaque_A32_invoke
.type opaque_A32_invoke,@function
opaque_A32_invoke:
pushq %rbp
movq %rsp,%rbp
subq $64,%rsp
movq %rdi,-8(%rbp)
movq %rsi,-16(%rbp)
movq %rdx,%rsi
movq %rsp,%rdi
movq $32,%rcx
rep movsb
movq -16(%rbp),%rdi
movq $77,%rsi
movabsq $4607182418800017408,%rax
movq %rax,%xmm0
call *-8(%rbp)
leave
ret
.size opaque_A32_invoke,.-opaque_A32_invoke
.globl opaque_A32_asm
.type opaque_A32_asm,@function
opaque_A32_asm:
pushq %rbp
movq %rsp,%rbp
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $32,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A32_asm,.-opaque_A32_asm
.globl opaque_A32_env
.type opaque_A32_env,@function
opaque_A32_env:
pushq %rbp
movq %rsp,%rbp
cmpq $2748,%rax
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $32,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A32_env,.-opaque_A32_env
.globl opaque_A32_al
.type opaque_A32_al,@function
opaque_A32_al:
pushq %rbp
movq %rsp,%rbp
cmpb $1,%al
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $32,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A32_al,.-opaque_A32_al
.globl opaque_A4096_recurse
.type opaque_A4096_recurse,@function
opaque_A4096_recurse:
movq $3,%r8
jmp opaque_A4096_recursive
.size opaque_A4096_recurse,.-opaque_A4096_recurse
.globl opaque_A4096_invoke
.type opaque_A4096_invoke,@function
opaque_A4096_invoke:
pushq %rbp
movq %rsp,%rbp
subq $4128,%rsp
movq %rdi,-8(%rbp)
movq %rsi,-16(%rbp)
movq %rdx,%rsi
movq %rsp,%rdi
movq $4096,%rcx
rep movsb
movq -16(%rbp),%rdi
movq $77,%rsi
movabsq $4607182418800017408,%rax
movq %rax,%xmm0
call *-8(%rbp)
leave
ret
.size opaque_A4096_invoke,.-opaque_A4096_invoke
.globl opaque_A4096_asm
.type opaque_A4096_asm,@function
opaque_A4096_asm:
pushq %rbp
movq %rsp,%rbp
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $4096,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A4096_asm,.-opaque_A4096_asm
.globl opaque_A4096_env
.type opaque_A4096_env,@function
opaque_A4096_env:
pushq %rbp
movq %rsp,%rbp
cmpq $2748,%rax
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $4096,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A4096_env,.-opaque_A4096_env
.globl opaque_A4096_al
.type opaque_A4096_al,@function
opaque_A4096_al:
pushq %rbp
movq %rsp,%rbp
cmpb $1,%al
jne opaque_bad
cmpq $77,%rsi
jne opaque_bad
movq %xmm0,%r10
movabsq $4607182418800017408,%r11
cmpq %r10,%r11
jne opaque_bad
leaq 16(%rbp),%rsi
cmpq opaque_source(%rip),%rsi
je opaque_bad
cmpq %rdi,%rsi
je opaque_bad
cmpq opaque_source(%rip),%rdi
je opaque_bad
movq %rdi,%rax
movq $4096,%rcx
rep movsb
movq $-1,%rdi
movq $-2,%rsi
movq $-3,%rdx
movq $-4,%rcx
movq $-5,%r8
movq $-6,%r9
movq $-7,%r10
movq $-8,%r11
pxor %xmm0,%xmm0
leave
ret
.size opaque_A4096_al,.-opaque_A4096_al
opaque_bad:
ud2
.globl opaque_pressureA_entry
.type opaque_pressureA_entry,@function
opaque_pressureA_entry:
cmpb $1,%al
jne opaque_bad
jmp opaque_pressureA
.size opaque_pressureA_entry,.-opaque_pressureA_entry
.globl opaque_pressureB_entry
.type opaque_pressureB_entry,@function
opaque_pressureB_entry:
cmpb $8,%al
jne opaque_bad
jmp opaque_pressureB
.size opaque_pressureB_entry,.-opaque_pressureB_entry
.section .note.GNU-stack,"",@progbits
