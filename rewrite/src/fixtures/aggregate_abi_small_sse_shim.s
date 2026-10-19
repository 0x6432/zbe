.text
.globl aggregate_abi_small_sse_preserved
.type aggregate_abi_small_sse_preserved,@function
aggregate_abi_small_sse_preserved:
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
 jne .Lsmall_sse_preserved_bad
 movabsq $0x1122334455667788,%r10
 cmpq %r10,%rbx
 jne .Lsmall_sse_preserved_bad
 movabsq $0x2233445566778899,%r10
 cmpq %r10,%r12
 jne .Lsmall_sse_preserved_bad
 movabsq $0x33445566778899aa,%r10
 cmpq %r10,%r13
 jne .Lsmall_sse_preserved_bad
 movabsq $0x445566778899aabb,%r10
 cmpq %r10,%r14
 jne .Lsmall_sse_preserved_bad
 movabsq $0x5566778899aabbcc,%r10
 cmpq %r10,%r15
 jne .Lsmall_sse_preserved_bad
 movl $1,%eax
 jmp .Lsmall_sse_preserved_done
.Lsmall_sse_preserved_bad:
 xorl %eax,%eax
.Lsmall_sse_preserved_done:
 addq $40,%rsp
 popq %r15
 popq %r14
 popq %r13
 popq %r12
 popq %rbx
 leave
 ret
.size aggregate_abi_small_sse_preserved,.-aggregate_abi_small_sse_preserved

.globl aggregate_abi_small_sse_poison_incoming_F4
.type aggregate_abi_small_sse_poison_incoming_F4,@function
aggregate_abi_small_sse_poison_incoming_F4:
 pushq %rbp
 movq %rsp,%rbp
 movq %rdi,%r11
 movdqu .Lsmall_sse_poison(%rip),%xmm0
 movdqu .Lsmall_sse_poison(%rip),%xmm1
 movabsq $0xaabbccdddeadbeef,%rdx
 movd 0(%r11),%xmm2
 movss %xmm2,%xmm0
 call aggregate_abi_small_sse_echo_F4
 leave
 ret
.size aggregate_abi_small_sse_poison_incoming_F4,.-aggregate_abi_small_sse_poison_incoming_F4
.globl aggregate_abi_small_sse_poison_result_F4
.type aggregate_abi_small_sse_poison_result_F4,@function
aggregate_abi_small_sse_poison_result_F4:
 movq %rdi,%r11
 movdqu .Lsmall_sse_poison(%rip),%xmm0
 movdqu .Lsmall_sse_poison(%rip),%xmm1
 movabsq $0xaabbccdddeadbeef,%rdx
 movd 0(%r11),%xmm2
 movss %xmm2,%xmm0
 ret
.size aggregate_abi_small_sse_poison_result_F4,.-aggregate_abi_small_sse_poison_result_F4
.globl aggregate_abi_small_sse_poison_incoming_F12
.type aggregate_abi_small_sse_poison_incoming_F12,@function
aggregate_abi_small_sse_poison_incoming_F12:
 pushq %rbp
 movq %rsp,%rbp
 movq %rdi,%r11
 movdqu .Lsmall_sse_poison(%rip),%xmm0
 movdqu .Lsmall_sse_poison(%rip),%xmm1
 movabsq $0xaabbccdddeadbeef,%rdx
 movq 0(%r11),%xmm0
 movd 8(%r11),%xmm2
 movss %xmm2,%xmm1
 call aggregate_abi_small_sse_echo_F12
 leave
 ret
.size aggregate_abi_small_sse_poison_incoming_F12,.-aggregate_abi_small_sse_poison_incoming_F12
.globl aggregate_abi_small_sse_poison_result_F12
.type aggregate_abi_small_sse_poison_result_F12,@function
aggregate_abi_small_sse_poison_result_F12:
 movq %rdi,%r11
 movdqu .Lsmall_sse_poison(%rip),%xmm0
 movdqu .Lsmall_sse_poison(%rip),%xmm1
 movabsq $0xaabbccdddeadbeef,%rdx
 movq 0(%r11),%xmm0
 movd 8(%r11),%xmm2
 movss %xmm2,%xmm1
 ret
.size aggregate_abi_small_sse_poison_result_F12,.-aggregate_abi_small_sse_poison_result_F12
.globl aggregate_abi_small_sse_poison_incoming_PIS12
.type aggregate_abi_small_sse_poison_incoming_PIS12,@function
aggregate_abi_small_sse_poison_incoming_PIS12:
 pushq %rbp
 movq %rsp,%rbp
 movq %rdi,%r11
 movdqu .Lsmall_sse_poison(%rip),%xmm0
 movdqu .Lsmall_sse_poison(%rip),%xmm1
 movabsq $0xaabbccdddeadbeef,%rdx
 movq 0(%r11),%rdi
 movd 8(%r11),%xmm2
 movss %xmm2,%xmm0
 call aggregate_abi_small_sse_echo_PIS12
 leave
 ret
.size aggregate_abi_small_sse_poison_incoming_PIS12,.-aggregate_abi_small_sse_poison_incoming_PIS12
.globl aggregate_abi_small_sse_poison_result_PIS12
.type aggregate_abi_small_sse_poison_result_PIS12,@function
aggregate_abi_small_sse_poison_result_PIS12:
 movq %rdi,%r11
 movdqu .Lsmall_sse_poison(%rip),%xmm0
 movdqu .Lsmall_sse_poison(%rip),%xmm1
 movabsq $0xaabbccdddeadbeef,%rdx
 movq 0(%r11),%rax
 movd 8(%r11),%xmm2
 movss %xmm2,%xmm0
 ret
.size aggregate_abi_small_sse_poison_result_PIS12,.-aggregate_abi_small_sse_poison_result_PIS12
.globl aggregate_abi_small_sse_poison_incoming_PSI12
.type aggregate_abi_small_sse_poison_incoming_PSI12,@function
aggregate_abi_small_sse_poison_incoming_PSI12:
 pushq %rbp
 movq %rsp,%rbp
 movq %rdi,%r11
 movdqu .Lsmall_sse_poison(%rip),%xmm0
 movdqu .Lsmall_sse_poison(%rip),%xmm1
 movabsq $0xaabbccdddeadbeef,%rdx
 movq 0(%r11),%xmm0
 movl 8(%r11),%edi
 call aggregate_abi_small_sse_echo_PSI12
 leave
 ret
.size aggregate_abi_small_sse_poison_incoming_PSI12,.-aggregate_abi_small_sse_poison_incoming_PSI12
.globl aggregate_abi_small_sse_poison_result_PSI12
.type aggregate_abi_small_sse_poison_result_PSI12,@function
aggregate_abi_small_sse_poison_result_PSI12:
 movq %rdi,%r11
 movdqu .Lsmall_sse_poison(%rip),%xmm0
 movdqu .Lsmall_sse_poison(%rip),%xmm1
 movabsq $0xaabbccdddeadbeef,%rdx
 movq 0(%r11),%xmm0
 movl 8(%r11),%eax
 ret
.size aggregate_abi_small_sse_poison_result_PSI12,.-aggregate_abi_small_sse_poison_result_PSI12
.globl aggregate_abi_small_sse_asm_gp
.type aggregate_abi_small_sse_asm_gp,@function
aggregate_abi_small_sse_asm_gp:
 leaq 8(%rsp),%rax
 testq $15,%rax
 jne .Laggregate_abi_small_sse_asm_gp_bad
 cmpq $1,%rdi
 jne .Laggregate_abi_small_sse_asm_gp_bad
 cmpq $2,%rsi
 jne .Laggregate_abi_small_sse_asm_gp_bad
 cmpq $3,%rdx
 jne .Laggregate_abi_small_sse_asm_gp_bad
 cmpq $4,%rcx
 jne .Laggregate_abi_small_sse_asm_gp_bad
 cmpq $5,%r8
 jne .Laggregate_abi_small_sse_asm_gp_bad
 cmpq $6,%r9
 jne .Laggregate_abi_small_sse_asm_gp_bad
 movq %xmm0,%rax
 movabsq $4607182418800017408,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_gp_bad
 movq %xmm1,%rax
 movabsq $4611686018427387904,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_gp_bad
 movq %xmm2,%rax
 movabsq $4613937818241073152,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_gp_bad
 movq %xmm3,%rax
 movabsq $4616189618054758400,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_gp_bad
 movq %xmm4,%rax
 movabsq $4617315517961601024,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_gp_bad
 movq %xmm5,%rax
 movabsq $4618441417868443648,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_gp_bad
 movq %xmm6,%rax
 movabsq $4619567317775286272,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_gp_bad
 movabsq $9833440827789222400,%r10
 cmpq %r10,8(%rsp)
 jne .Laggregate_abi_small_sse_asm_gp_bad
 cmpl $0x80000000,16(%rsp)
 jne .Laggregate_abi_small_sse_asm_gp_bad
 movq %xmm7,%rax
 movabsq $4620693217682128896,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_gp_bad
 movabsq $4621256167635550208,%r10
 cmpq %r10,24(%rsp)
 jne .Laggregate_abi_small_sse_asm_gp_bad
 movl $1,%eax
 ret
.Laggregate_abi_small_sse_asm_gp_bad:
 ud2
.size aggregate_abi_small_sse_asm_gp,.-aggregate_abi_small_sse_asm_gp
.globl aggregate_abi_small_sse_asm_sse
.type aggregate_abi_small_sse_asm_sse,@function
aggregate_abi_small_sse_asm_sse:
 leaq 8(%rsp),%rax
 testq $15,%rax
 jne .Laggregate_abi_small_sse_asm_sse_bad
 cmpq $1,%rdi
 jne .Laggregate_abi_small_sse_asm_sse_bad
 cmpq $2,%rsi
 jne .Laggregate_abi_small_sse_asm_sse_bad
 cmpq $3,%rdx
 jne .Laggregate_abi_small_sse_asm_sse_bad
 cmpq $4,%rcx
 jne .Laggregate_abi_small_sse_asm_sse_bad
 cmpq $5,%r8
 jne .Laggregate_abi_small_sse_asm_sse_bad
 movq %xmm0,%rax
 movabsq $4607182418800017408,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_sse_bad
 movq %xmm1,%rax
 movabsq $4611686018427387904,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_sse_bad
 movq %xmm2,%rax
 movabsq $4613937818241073152,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_sse_bad
 movq %xmm3,%rax
 movabsq $4616189618054758400,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_sse_bad
 movq %xmm4,%rax
 movabsq $4617315517961601024,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_sse_bad
 movq %xmm5,%rax
 movabsq $4618441417868443648,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_sse_bad
 movq %xmm6,%rax
 movabsq $4619567317775286272,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_sse_bad
 movq %xmm7,%rax
 movabsq $4620693217682128896,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_sse_bad
 movabsq $9833440827789222400,%r10
 cmpq %r10,8(%rsp)
 jne .Laggregate_abi_small_sse_asm_sse_bad
 cmpl $0x80000000,16(%rsp)
 jne .Laggregate_abi_small_sse_asm_sse_bad
 cmpq $99,%r9
 jne .Laggregate_abi_small_sse_asm_sse_bad
 cmpb $38,24(%rsp)
 jne .Laggregate_abi_small_sse_asm_sse_bad
 movabsq $4621256167635550208,%r10
 cmpq %r10,32(%rsp)
 jne .Laggregate_abi_small_sse_asm_sse_bad
 movl $1,%eax
 ret
.Laggregate_abi_small_sse_asm_sse_bad:
 ud2
.size aggregate_abi_small_sse_asm_sse,.-aggregate_abi_small_sse_asm_sse
.globl aggregate_abi_small_sse_asm_fit
.type aggregate_abi_small_sse_asm_fit,@function
aggregate_abi_small_sse_asm_fit:
 leaq 8(%rsp),%rax
 testq $15,%rax
 jne .Laggregate_abi_small_sse_asm_fit_bad
 cmpq $1,%rdi
 jne .Laggregate_abi_small_sse_asm_fit_bad
 cmpq $2,%rsi
 jne .Laggregate_abi_small_sse_asm_fit_bad
 cmpq $3,%rdx
 jne .Laggregate_abi_small_sse_asm_fit_bad
 cmpq $4,%rcx
 jne .Laggregate_abi_small_sse_asm_fit_bad
 cmpq $5,%r8
 jne .Laggregate_abi_small_sse_asm_fit_bad
 movq %xmm0,%rax
 movabsq $4607182418800017408,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_fit_bad
 movq %xmm1,%rax
 movabsq $4611686018427387904,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_fit_bad
 movq %xmm2,%rax
 movabsq $4613937818241073152,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_fit_bad
 movq %xmm3,%rax
 movabsq $4616189618054758400,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_fit_bad
 movq %xmm4,%rax
 movabsq $4617315517961601024,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_fit_bad
 movq %xmm5,%rax
 movabsq $4618441417868443648,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_fit_bad
 movq %xmm6,%rax
 movabsq $4619567317775286272,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_fit_bad
 movabsq $9833440827789222400,%r10
 cmpq %r10,%r9
 jne .Laggregate_abi_small_sse_asm_fit_bad
 movd %xmm7,%eax
 cmpl $2147483648,%eax
 jne .Laggregate_abi_small_sse_asm_fit_bad
 cmpq $99,8(%rsp)
 jne .Laggregate_abi_small_sse_asm_fit_bad
 movabsq $4621256167635550208,%r10
 cmpq %r10,16(%rsp)
 jne .Laggregate_abi_small_sse_asm_fit_bad
 movl $1,%eax
 ret
.Laggregate_abi_small_sse_asm_fit_bad:
 ud2
.size aggregate_abi_small_sse_asm_fit,.-aggregate_abi_small_sse_asm_fit
.globl aggregate_abi_small_sse_asm_ss
.type aggregate_abi_small_sse_asm_ss,@function
aggregate_abi_small_sse_asm_ss:
 leaq 8(%rsp),%rax
 testq $15,%rax
 jne .Laggregate_abi_small_sse_asm_ss_bad
 movq %xmm0,%rax
 movabsq $4607182418800017408,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_ss_bad
 movq %xmm1,%rax
 movabsq $4611686018427387904,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_ss_bad
 movq %xmm2,%rax
 movabsq $4613937818241073152,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_ss_bad
 movq %xmm3,%rax
 movabsq $4616189618054758400,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_ss_bad
 movq %xmm4,%rax
 movabsq $4617315517961601024,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_ss_bad
 movq %xmm5,%rax
 movabsq $4618441417868443648,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_ss_bad
 movq %xmm6,%rax
 movabsq $4619567317775286272,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_ss_bad
 cmpl $2147483648,8(%rsp)
 jne .Laggregate_abi_small_sse_asm_ss_bad
 cmpl $2139095040,12(%rsp)
 jne .Laggregate_abi_small_sse_asm_ss_bad
 cmpl $4286578688,16(%rsp)
 jne .Laggregate_abi_small_sse_asm_ss_bad
 movq %xmm7,%rax
 movabsq $4620693217682128896,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_sse_asm_ss_bad
 movl $1,%eax
 ret
.Laggregate_abi_small_sse_asm_ss_bad:
 ud2
.size aggregate_abi_small_sse_asm_ss,.-aggregate_abi_small_sse_asm_ss
.section .rodata
.p2align 4
.Lsmall_sse_poison:
.quad 0xfedcba9876543210,0xdeadbeef01234567
.text
.globl aggregate_abi_small_sse_envbridge
.type aggregate_abi_small_sse_envbridge,@function
aggregate_abi_small_sse_envbridge:
 pushq %rbp
 movq %rsp,%rbp
 movl $7,%eax
 call aggregate_abi_small_sse_envcaller
 leave
 ret
.size aggregate_abi_small_sse_envbridge,.-aggregate_abi_small_sse_envbridge
.section .note.GNU-stack,"",@progbits
