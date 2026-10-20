.text
.globl aggregate_abi_align16_preserved
.type aggregate_abi_align16_preserved,@function
aggregate_abi_align16_preserved:
 pushq %rbp
 movq %rsp,%rbp
 pushq %rbx
 pushq %r12
 pushq %r13
 pushq %r14
 pushq %r15
 subq $40,%rsp
 movq %rdx,0(%rsp)
 movq %rdi,8(%rsp)
 stmxcsr 16(%rsp)
 movq %rsi,%rdi
 movabsq $0x1122334455667788,%rbx
 movabsq $0x2233445566778899,%r12
 movabsq $0x33445566778899aa,%r13
 movabsq $0x445566778899aabb,%r14
 movabsq $0x5566778899aabbcc,%r15
 call *8(%rsp)
 movq 0(%rsp),%r11
 movq %rax,0(%r11)
 movq %rdx,8(%r11)
 movq %xmm0,16(%r11)
 movq %xmm1,24(%r11)
 stmxcsr 20(%rsp)
 movl 16(%rsp),%r10d
 cmpl %r10d,20(%rsp)
 jne .Lalign16_preserved_bad
 movabsq $0x1122334455667788,%r10
 cmpq %r10,%rbx
 jne .Lalign16_preserved_bad
 movabsq $0x2233445566778899,%r10
 cmpq %r10,%r12
 jne .Lalign16_preserved_bad
 movabsq $0x33445566778899aa,%r10
 cmpq %r10,%r13
 jne .Lalign16_preserved_bad
 movabsq $0x445566778899aabb,%r10
 cmpq %r10,%r14
 jne .Lalign16_preserved_bad
 movabsq $0x5566778899aabbcc,%r10
 cmpq %r10,%r15
 jne .Lalign16_preserved_bad
 movl $1,%eax
 jmp .Lalign16_preserved_done
.Lalign16_preserved_bad:
 xorl %eax,%eax
.Lalign16_preserved_done:
 addq $40,%rsp
 popq %r15
 popq %r14
 popq %r13
 popq %r12
 popq %rbx
 leave
 ret
.size aggregate_abi_align16_preserved,.-aggregate_abi_align16_preserved



.text
.globl aggregate_abi_align16_pressure_gp_asm
.type aggregate_abi_align16_pressure_gp_asm,@function
aggregate_abi_align16_pressure_gp_asm:
 leaq 8(%rsp),%r10
 testq $15,%r10
 jne .Lgp_bad
 movabsq $1,%r10
 cmpq %r10,%rdi
 jne .Lgp_bad
 movabsq $2,%r10
 cmpq %r10,%rsi
 jne .Lgp_bad
 movabsq $3,%r10
 cmpq %r10,%rdx
 jne .Lgp_bad
 movabsq $4,%r10
 cmpq %r10,%rcx
 jne .Lgp_bad
 movabsq $5,%r10
 cmpq %r10,%r8
 jne .Lgp_bad
 movabsq $6,%r10
 cmpq %r10,%r9
 jne .Lgp_bad
 movabsq $7,%r10
 cmpq %r10,8(%rsp)
 jne .Lgp_bad
 cmpl $287454020,24(%rsp)
 jne .Lgp_bad
 cmpl $2141266757,28(%rsp)
 jne .Lgp_bad
 movabsq $99,%r10
 cmpq %r10,40(%rsp)
 jne .Lgp_bad
 movq %xmm0,%r11
 movabsq $9218888453225749180,%r10
 cmpq %r10,%r11
 jne .Lgp_bad
 movl $1,%eax
 ret
.Lgp_bad:
 ud2
.size aggregate_abi_align16_pressure_gp_asm,.-aggregate_abi_align16_pressure_gp_asm

.text
.globl aggregate_abi_align16_pressure_ione_asm
.type aggregate_abi_align16_pressure_ione_asm,@function
aggregate_abi_align16_pressure_ione_asm:
 leaq 8(%rsp),%r10
 testq $15,%r10
 jne .Lione_bad
 movabsq $1,%r10
 cmpq %r10,%rdi
 jne .Lione_bad
 movabsq $2,%r10
 cmpq %r10,%rsi
 jne .Lione_bad
 movabsq $3,%r10
 cmpq %r10,%rdx
 jne .Lione_bad
 movabsq $4,%r10
 cmpq %r10,%rcx
 jne .Lione_bad
 movabsq $5,%r10
 cmpq %r10,%r8
 jne .Lione_bad
 movabsq $9196670693614433092,%r10
 cmpq %r10,%r9
 jne .Lione_bad
 movabsq $99,%r10
 cmpq %r10,8(%rsp)
 jne .Lione_bad
 movq %xmm0,%r11
 movabsq $9218888453225749180,%r10
 cmpq %r10,%r11
 jne .Lione_bad
 movl $1,%eax
 ret
.Lione_bad:
 ud2
.size aggregate_abi_align16_pressure_ione_asm,.-aggregate_abi_align16_pressure_ione_asm

.text
.globl aggregate_abi_align16_pressure_sone_asm
.type aggregate_abi_align16_pressure_sone_asm,@function
aggregate_abi_align16_pressure_sone_asm:
 leaq 8(%rsp),%r10
 testq $15,%r10
 jne .Lsone_bad
 movq %xmm0,%r11
 movabsq $4607182418800017408,%r10
 cmpq %r10,%r11
 jne .Lsone_bad
 movq %xmm1,%r11
 movabsq $4607182418800017409,%r10
 cmpq %r10,%r11
 jne .Lsone_bad
 movq %xmm2,%r11
 movabsq $4607182418800017410,%r10
 cmpq %r10,%r11
 jne .Lsone_bad
 movq %xmm3,%r11
 movabsq $4607182418800017411,%r10
 cmpq %r10,%r11
 jne .Lsone_bad
 movq %xmm4,%r11
 movabsq $4607182418800017412,%r10
 cmpq %r10,%r11
 jne .Lsone_bad
 movq %xmm5,%r11
 movabsq $4607182418800017413,%r10
 cmpq %r10,%r11
 jne .Lsone_bad
 movq %xmm6,%r11
 movabsq $4607182418800017414,%r10
 cmpq %r10,%r11
 jne .Lsone_bad
 movd %xmm7,%r10d
 cmpl $2141266757,%r10d
 jne .Lsone_bad
 movabsq $9218888453225749180,%r10
 cmpq %r10,8(%rsp)
 jne .Lsone_bad
 movabsq $99,%r10
 cmpq %r10,%rdi
 jne .Lsone_bad
 movl $1,%eax
 ret
.Lsone_bad:
 ud2
.size aggregate_abi_align16_pressure_sone_asm,.-aggregate_abi_align16_pressure_sone_asm

.text
.globl aggregate_abi_align16_pressure_gpfail_asm
.type aggregate_abi_align16_pressure_gpfail_asm,@function
aggregate_abi_align16_pressure_gpfail_asm:
 leaq 8(%rsp),%r10
 testq $15,%r10
 jne .Lgpfail_bad
 movabsq $1,%r10
 cmpq %r10,%rdi
 jne .Lgpfail_bad
 movabsq $2,%r10
 cmpq %r10,%rsi
 jne .Lgpfail_bad
 movabsq $3,%r10
 cmpq %r10,%rdx
 jne .Lgpfail_bad
 movabsq $4,%r10
 cmpq %r10,%rcx
 jne .Lgpfail_bad
 movabsq $5,%r10
 cmpq %r10,%r8
 jne .Lgpfail_bad
 movabsq $6,%r10
 cmpq %r10,%r9
 jne .Lgpfail_bad
 cmpl $2141266757,8(%rsp)
 jne .Lgpfail_bad
 movabsq $6153737369425722316,%r10
 cmpq %r10,16(%rsp)
 jne .Lgpfail_bad
 movabsq $99,%r10
 cmpq %r10,24(%rsp)
 jne .Lgpfail_bad
 movq %xmm0,%r11
 movabsq $9218888453225749180,%r10
 cmpq %r10,%r11
 jne .Lgpfail_bad
 movl $1,%eax
 ret
.Lgpfail_bad:
 ud2
.size aggregate_abi_align16_pressure_gpfail_asm,.-aggregate_abi_align16_pressure_gpfail_asm

.text
.globl aggregate_abi_align16_pressure_ssefail_asm
.type aggregate_abi_align16_pressure_ssefail_asm,@function
aggregate_abi_align16_pressure_ssefail_asm:
 leaq 8(%rsp),%r10
 testq $15,%r10
 jne .Lssefail_bad
 movq %xmm0,%r11
 movabsq $4607182418800017408,%r10
 cmpq %r10,%r11
 jne .Lssefail_bad
 movq %xmm1,%r11
 movabsq $4607182418800017409,%r10
 cmpq %r10,%r11
 jne .Lssefail_bad
 movq %xmm2,%r11
 movabsq $4607182418800017410,%r10
 cmpq %r10,%r11
 jne .Lssefail_bad
 movq %xmm3,%r11
 movabsq $4607182418800017411,%r10
 cmpq %r10,%r11
 jne .Lssefail_bad
 movq %xmm4,%r11
 movabsq $4607182418800017412,%r10
 cmpq %r10,%r11
 jne .Lssefail_bad
 movq %xmm5,%r11
 movabsq $4607182418800017413,%r10
 cmpq %r10,%r11
 jne .Lssefail_bad
 movq %xmm6,%r11
 movabsq $4607182418800017414,%r10
 cmpq %r10,%r11
 jne .Lssefail_bad
 movq %xmm7,%r11
 movabsq $4607182418800017415,%r10
 cmpq %r10,%r11
 jne .Lssefail_bad
 movabsq $6153737369425722316,%r10
 cmpq %r10,8(%rsp)
 jne .Lssefail_bad
 cmpl $2141266757,16(%rsp)
 jne .Lssefail_bad
 movabsq $9218888453225749180,%r10
 cmpq %r10,24(%rsp)
 jne .Lssefail_bad
 movabsq $99,%r10
 cmpq %r10,%rdi
 jne .Lssefail_bad
 movl $1,%eax
 ret
.Lssefail_bad:
 ud2
.size aggregate_abi_align16_pressure_ssefail_asm,.-aggregate_abi_align16_pressure_ssefail_asm

.section .note.GNU-stack,"",@progbits
