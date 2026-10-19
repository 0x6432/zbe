.text
.globl aggregate_abi_small_integer_envbridge
.type aggregate_abi_small_integer_envbridge,@function
aggregate_abi_small_integer_envbridge:
 pushq %rbp
 movq %rsp,%rbp
 movl $7,%eax
 call aggregate_abi_small_integer_envcaller
 leave
 ret
.size aggregate_abi_small_integer_envbridge,.-aggregate_abi_small_integer_envbridge
.globl aggregate_abi_small_integer_envadd
.type aggregate_abi_small_integer_envadd,@function
aggregate_abi_small_integer_envadd:
 addl %edi,%eax
 ret
.size aggregate_abi_small_integer_envadd,.-aggregate_abi_small_integer_envadd
.globl aggregate_abi_small_integer_cmemory_probe
.type aggregate_abi_small_integer_cmemory_probe,@function
aggregate_abi_small_integer_cmemory_probe:
 leaq 8(%rsp),%rax
 testq $15,%rax
 jne .Laggregate_abi_small_integer_cmemory_probe_bad
 movq %rdi,%r11
 cmpq $11,%rsi
 jne .Laggregate_abi_small_integer_cmemory_probe_bad
 cmpq $22,%rdx
 jne .Laggregate_abi_small_integer_cmemory_probe_bad
 cmpq $33,%rcx
 jne .Laggregate_abi_small_integer_cmemory_probe_bad
 cmpq $44,%r8
 jne .Laggregate_abi_small_integer_cmemory_probe_bad
 cmpq $55,%r9
 jne .Laggregate_abi_small_integer_cmemory_probe_bad
 movabsq $0x897c6f6255483b2e,%rax
 cmpq %rax,8(%rsp)
 jne .Laggregate_abi_small_integer_cmemory_probe_bad
 cmpb $150,16(%rsp)
 jne .Laggregate_abi_small_integer_cmemory_probe_bad
 cmpb $38,24(%rsp)
 jne .Laggregate_abi_small_integer_cmemory_probe_bad
 movq %xmm0,%rax
 movabsq $0x3ff0000000000000,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_integer_cmemory_probe_bad
 movq %xmm1,%rax
 movabsq $0x4000000000000000,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_integer_cmemory_probe_bad
 movq %xmm2,%rax
 movabsq $0x4008000000000000,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_integer_cmemory_probe_bad
 movq %xmm3,%rax
 movabsq $0x4010000000000000,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_integer_cmemory_probe_bad
 movq %xmm4,%rax
 movabsq $0x4014000000000000,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_integer_cmemory_probe_bad
 movq %xmm5,%rax
 movabsq $0x4018000000000000,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_integer_cmemory_probe_bad
 movq %xmm6,%rax
 movabsq $0x401c000000000000,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_integer_cmemory_probe_bad
 movq %xmm7,%rax
 movabsq $0x4020000000000000,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_integer_cmemory_probe_bad
 movabsq $0x4022000000000000,%rax
 cmpq %rax,32(%rsp)
 jne .Laggregate_abi_small_integer_cmemory_probe_bad
 movl $209,%eax
 movl $17,%ecx
 rep stosb
 movq %r11,%rax
 ret
.Laggregate_abi_small_integer_cmemory_probe_bad:
 ud2
.size aggregate_abi_small_integer_cmemory_probe,.-aggregate_abi_small_integer_cmemory_probe
.globl aggregate_abi_small_integer_cinteger_probe
.type aggregate_abi_small_integer_cinteger_probe,@function
aggregate_abi_small_integer_cinteger_probe:
 leaq 8(%rsp),%rax
 testq $15,%rax
 jne .Laggregate_abi_small_integer_cinteger_probe_bad
 cmpq $11,%rdi
 jne .Laggregate_abi_small_integer_cinteger_probe_bad
 cmpq $22,%rsi
 jne .Laggregate_abi_small_integer_cinteger_probe_bad
 cmpq $33,%rdx
 jne .Laggregate_abi_small_integer_cinteger_probe_bad
 cmpq $44,%rcx
 jne .Laggregate_abi_small_integer_cinteger_probe_bad
 movabsq $0x897c6f6255483b2e,%rax
 cmpq %rax,%r8
 jne .Laggregate_abi_small_integer_cinteger_probe_bad
 cmpb $150,%r9b
 jne .Laggregate_abi_small_integer_cinteger_probe_bad
 cmpq $55,8(%rsp)
 jne .Laggregate_abi_small_integer_cinteger_probe_bad
 cmpb $38,16(%rsp)
 jne .Laggregate_abi_small_integer_cinteger_probe_bad
 movq %xmm0,%rax
 movabsq $0x3ff0000000000000,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_integer_cinteger_probe_bad
 movq %xmm1,%rax
 movabsq $0x4000000000000000,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_integer_cinteger_probe_bad
 movq %xmm2,%rax
 movabsq $0x4008000000000000,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_integer_cinteger_probe_bad
 movq %xmm3,%rax
 movabsq $0x4010000000000000,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_integer_cinteger_probe_bad
 movq %xmm4,%rax
 movabsq $0x4014000000000000,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_integer_cinteger_probe_bad
 movq %xmm5,%rax
 movabsq $0x4018000000000000,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_integer_cinteger_probe_bad
 movq %xmm6,%rax
 movabsq $0x401c000000000000,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_integer_cinteger_probe_bad
 movq %xmm7,%rax
 movabsq $0x4020000000000000,%r10
 cmpq %r10,%rax
 jne .Laggregate_abi_small_integer_cinteger_probe_bad
 movabsq $0x4022000000000000,%rax
 cmpq %rax,24(%rsp)
 jne .Laggregate_abi_small_integer_cinteger_probe_bad
 movq %r8,%rax
 movzbl %r9b,%edx
 ret
.Laggregate_abi_small_integer_cinteger_probe_bad:
 ud2
.size aggregate_abi_small_integer_cinteger_probe,.-aggregate_abi_small_integer_cinteger_probe
# A handwritten caller: poison unused high bits in the ninth-byte lane.
.globl aggregate_abi_small_integer_poison_incoming
.type aggregate_abi_small_integer_poison_incoming,@function
aggregate_abi_small_integer_poison_incoming:
 pushq %rbp
 movq %rsp,%rbp
 movq %rdi,%r11
 movq (%r11),%rdi
 movabsq $0xfedcba9876543200,%rsi
 movb 8(%r11),%sil
 call aggregate_abi_small_integer_echo9
 leave
 ret
.size aggregate_abi_small_integer_poison_incoming,.-aggregate_abi_small_integer_poison_incoming
# A handwritten callee: valid payload, unspecified high return bits poisoned.
.globl aggregate_abi_small_integer_poison_result
.type aggregate_abi_small_integer_poison_result,@function
aggregate_abi_small_integer_poison_result:
 movq (%rdi),%rax
 movabsq $0xfedcba9876543200,%rdx
 movb 8(%rdi),%dl
 ret
.size aggregate_abi_small_integer_poison_result,.-aggregate_abi_small_integer_poison_result
# Generic pointer-source call wrapper. Capture both lanes before checking
# independently seeded callee-saved registers; output is a full 16-byte object.
.globl aggregate_abi_small_integer_preserved
.type aggregate_abi_small_integer_preserved,@function
aggregate_abi_small_integer_preserved:
 pushq %rbp
 movq %rsp,%rbp
 pushq %rbx
 pushq %r12
 pushq %r13
 pushq %r14
 pushq %r15
 subq $24,%rsp
 movq %rdx,0(%rsp)
 movq %rdi,8(%rsp)
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
 movabsq $0x1122334455667788,%r10
 cmpq %r10,%rbx
 jne .Lsmall_preserved_bad
 movabsq $0x2233445566778899,%r10
 cmpq %r10,%r12
 jne .Lsmall_preserved_bad
 movabsq $0x33445566778899aa,%r10
 cmpq %r10,%r13
 jne .Lsmall_preserved_bad
 movabsq $0x445566778899aabb,%r10
 cmpq %r10,%r14
 jne .Lsmall_preserved_bad
 movabsq $0x5566778899aabbcc,%r10
 cmpq %r10,%r15
 jne .Lsmall_preserved_bad
 movl $1,%eax
 jmp .Lsmall_preserved_done
.Lsmall_preserved_bad:
 xorl %eax,%eax
.Lsmall_preserved_done:
 addq $24,%rsp
 popq %r15
 popq %r14
 popq %r13
 popq %r12
 popq %rbx
 leave
 ret
.size aggregate_abi_small_integer_preserved,.-aggregate_abi_small_integer_preserved
.section .note.GNU-stack,"",@progbits
