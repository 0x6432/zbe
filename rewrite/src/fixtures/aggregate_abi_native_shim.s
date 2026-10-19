.text
.globl aggregate_abi_native_guard_return
.type aggregate_abi_native_guard_return,@function
aggregate_abi_native_guard_return:
 pushq %rbp
 movq %rsp,%rbp
 pushq %rbx
 pushq %r12
 pushq %r13
 pushq %r14
 pushq %r15
 subq $8,%rsp
 movq %rdi,%r11
 movq %rsi,%rdi
 movq %rdx,%rsi
 movl $101,%ebx
 movl $102,%r12d
 movl $103,%r13d
 movl $104,%r14d
 movl $105,%r15d
 call *%r11
 cmpq $101,%rbx
 jne 1f
 cmpq $102,%r12
 jne 1f
 cmpq $103,%r13
 jne 1f
 cmpq $104,%r14
 jne 1f
 cmpq $105,%r15
 jne 1f
 jmp 2f
1: xorl %eax,%eax
2: addq $8,%rsp
 popq %r15
 popq %r14
 popq %r13
 popq %r12
 popq %rbx
 leave
 ret
.size aggregate_abi_native_guard_return,.-aggregate_abi_native_guard_return
.globl aggregate_abi_native_env_bridge
.type aggregate_abi_native_env_bridge,@function
aggregate_abi_native_env_bridge:
 pushq %rbp
 movq %rsp,%rbp
 movl $7,%eax
 call aggregate_abi_native_envcaller
 leave
 ret
.size aggregate_abi_native_env_bridge,.-aggregate_abi_native_env_bridge
.section .note.GNU-stack,"",@progbits
.text
.globl aggregate_abi_native_stackprobe
.type aggregate_abi_native_stackprobe,@function
aggregate_abi_native_stackprobe:
 movq %rdi,%r11
 leaq 8(%rsp),%rax
 testq $15,%rax
 jne .Lprobe_bad
 cmpq $11,%rsi
 jne .Lprobe_bad
 cmpq $22,%rdx
 jne .Lprobe_bad
 cmpq $33,%rcx
 jne .Lprobe_bad
 cmpq $44,%r8
 jne .Lprobe_bad
 cmpq $55,%r9
 jne .Lprobe_bad
 cmpq $66,8(%rsp)
 jne .Lprobe_bad
 cmpb $20,16(%rsp)
 jne .Lprobe_bad
 movabsq $0x1122334455667788,%rax
 cmpq %rax,40(%rsp)
 jne .Lprobe_bad
 movq %xmm0,%rax
 movabsq $0x3ff0000000000000,%r10
 cmpq %r10,%rax
 jne .Lprobe_bad
 movq %xmm1,%rax
 movabsq $0x4000000000000000,%r10
 cmpq %r10,%rax
 jne .Lprobe_bad
 movq %xmm2,%rax
 movabsq $0x4008000000000000,%r10
 cmpq %r10,%rax
 jne .Lprobe_bad
 movq %xmm3,%rax
 movabsq $0x4010000000000000,%r10
 cmpq %r10,%rax
 jne .Lprobe_bad
 movq %xmm4,%rax
 movabsq $0x4014000000000000,%r10
 cmpq %r10,%rax
 jne .Lprobe_bad
 movq %xmm5,%rax
 movabsq $0x4018000000000000,%r10
 cmpq %r10,%rax
 jne .Lprobe_bad
 movq %xmm6,%rax
 movabsq $0x401c000000000000,%r10
 cmpq %r10,%rax
 jne .Lprobe_bad
 movq %xmm7,%rax
 movabsq $0x4020000000000000,%r10
 cmpq %r10,%rax
 jne .Lprobe_bad
 movabsq $0x4022000000000000,%rax
 cmpq %rax,72(%rsp)
 jne .Lprobe_bad
 leaq 16(%rsp),%rsi
 movl $17,%ecx
 rep movsb
 movb $234,(%r11)
 movq %r11,%rax
 ret
.Lprobe_bad:
 movb $0,(%r11)
 movq %r11,%rax
 ret
.size aggregate_abi_native_stackprobe,.-aggregate_abi_native_stackprobe
.globl aggregate_abi_native_manual_caller
.type aggregate_abi_native_manual_caller,@function
aggregate_abi_native_manual_caller:
 pushq %rbp
 movq %rsp,%rbp
 subq $112,%rsp
 movq %rdi,-8(%rbp)
 movq %rsi,-16(%rbp)
 movq %rdx,-24(%rbp)
 leaq 8(%rsp),%rdi
 movl $17,%ecx
 rep movsb
 movq -24(%rbp),%rsi
 leaq 32(%rsp),%rdi
 movl $32,%ecx
 rep movsb
 movq $66,0(%rsp)
 movabsq $0x4022000000000000,%rax
 movq %rax,64(%rsp)
 movabsq $0x3ff0000000000000,%rax
 movq %rax,%xmm0
 movabsq $0x4000000000000000,%rax
 movq %rax,%xmm1
 movabsq $0x4008000000000000,%rax
 movq %rax,%xmm2
 movabsq $0x4010000000000000,%rax
 movq %rax,%xmm3
 movabsq $0x4014000000000000,%rax
 movq %rax,%xmm4
 movabsq $0x4018000000000000,%rax
 movq %rax,%xmm5
 movabsq $0x401c000000000000,%rax
 movq %rax,%xmm6
 movabsq $0x4020000000000000,%rax
 movq %rax,%xmm7
 movq -8(%rbp),%rdi
 movl $11,%esi
 movl $22,%edx
 movl $33,%ecx
 movl $44,%r8d
 movl $55,%r9d
 call aggregate_abi_native_mix
 cmpq -8(%rbp),%rax
 sete %al
 movzbl %al,%eax
 leave
 ret
.size aggregate_abi_native_manual_caller,.-aggregate_abi_native_manual_caller
.section .note.GNU-stack,"",@progbits
