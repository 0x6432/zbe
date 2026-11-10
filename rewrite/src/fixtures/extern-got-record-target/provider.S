.text
# Both callees have the same SysV signature: 24-byte memory return, then a
# 16-byte INTEGER record in RSI/RDX. Every sentinel path uses the valid hidden
# result pointer and returns that pointer in RAX.
.globl m04_real
.type m04_real,@function
m04_real:
 movq m04_wrong@GOTPCREL(%rip), %r10
 cmpq 0(%r10), %rsi
 jne .Lm04_bad
 cmpq 8(%r10), %rdx
 jne .Lm04_bad
 movq $(BASE+51), 0(%rdi)
 movq $(BASE+52), 8(%rdi)
 movq $(BASE+53), 16(%rdi)
 movq %rdi, %rax
 ret
.Lm04_bad:
 movq $901, 0(%rdi)
 movq $902, 8(%rdi)
 movq $903, 16(%rdi)
 movq %rdi, %rax
 ret
.size m04_real,.-m04_real
.globl m04_wrong
.type m04_wrong,@function
m04_wrong:
 movq $0, 0(%rdi)
 movq $0, 8(%rdi)
 movq $0, 16(%rdi)
 movq %rdi, %rax
 ret
.size m04_wrong,.-m04_wrong
.globl m04_source
.type m04_source,@function
m04_source:
 movq m04_wrong@GOTPCREL(%rip), %rax
 ret
.size m04_source,.-m04_source
.section .note.GNU-stack,"",@progbits
