.text
.p2align 4
.globl aggregate_abi_union_U4_env_bridge
.type aggregate_abi_union_U4_env_bridge,@function
aggregate_abi_union_U4_env_bridge:
 movq %rdi,%rax
 movq %rsi,%rdi
 jmp aggregate_abi_union_U4_env
.size aggregate_abi_union_U4_env_bridge,.-aggregate_abi_union_U4_env_bridge
.p2align 4
.globl aggregate_abi_union_U4R_env_bridge
.type aggregate_abi_union_U4R_env_bridge,@function
aggregate_abi_union_U4R_env_bridge:
 movq %rdi,%rax
 movq %rsi,%rdi
 jmp aggregate_abi_union_U4R_env
.size aggregate_abi_union_U4R_env_bridge,.-aggregate_abi_union_U4R_env_bridge
.p2align 4
.globl aggregate_abi_union_U8_env_bridge
.type aggregate_abi_union_U8_env_bridge,@function
aggregate_abi_union_U8_env_bridge:
 movq %rdi,%rax
 jmp aggregate_abi_union_U8_env
.size aggregate_abi_union_U8_env_bridge,.-aggregate_abi_union_U8_env_bridge
.p2align 4
.globl aggregate_abi_union_U12_env_bridge
.type aggregate_abi_union_U12_env_bridge,@function
aggregate_abi_union_U12_env_bridge:
 movq %rdi,%rax
 movq %rsi,%rdi
 jmp aggregate_abi_union_U12_env
.size aggregate_abi_union_U12_env_bridge,.-aggregate_abi_union_U12_env_bridge
.p2align 4
.globl aggregate_abi_union_U16_env_bridge
.type aggregate_abi_union_U16_env_bridge,@function
aggregate_abi_union_U16_env_bridge:
 movq %rdi,%rax
 movq %rsi,%rdi
 movq %rdx,%rsi
 jmp aggregate_abi_union_U16_env
.size aggregate_abi_union_U16_env_bridge,.-aggregate_abi_union_U16_env_bridge
.p2align 4
.globl aggregate_abi_union_UM_env_bridge
.type aggregate_abi_union_UM_env_bridge,@function
aggregate_abi_union_UM_env_bridge:
 movq %rsi,%rax
 jmp aggregate_abi_union_UM_env
.size aggregate_abi_union_UM_env_bridge,.-aggregate_abi_union_UM_env_bridge
.p2align 4
.globl aggregate_abi_union_UN_env_bridge
.type aggregate_abi_union_UN_env_bridge,@function
aggregate_abi_union_UN_env_bridge:
 movq %rdi,%rax
 movq %rsi,%rdi
 jmp aggregate_abi_union_UN_env
.size aggregate_abi_union_UN_env_bridge,.-aggregate_abi_union_UN_env_bridge
.p2align 4
.globl aggregate_abi_union_U3_env_bridge
.type aggregate_abi_union_U3_env_bridge,@function
aggregate_abi_union_U3_env_bridge:
 movq %rdi,%rax
 movq %rsi,%rdi
 jmp aggregate_abi_union_U3_env
.size aggregate_abi_union_U3_env_bridge,.-aggregate_abi_union_U3_env_bridge
.p2align 4
.globl aggregate_abi_union_U17_env_bridge
.type aggregate_abi_union_U17_env_bridge,@function
aggregate_abi_union_U17_env_bridge:
 movq %rsi,%rax
 jmp aggregate_abi_union_U17_env
.size aggregate_abi_union_U17_env_bridge,.-aggregate_abi_union_U17_env_bridge
.p2align 4
.globl aggregate_abi_union_UDD_env_bridge
.type aggregate_abi_union_UDD_env_bridge,@function
aggregate_abi_union_UDD_env_bridge:
 movq %rdi,%rax
 jmp aggregate_abi_union_UDD_env
.size aggregate_abi_union_UDD_env_bridge,.-aggregate_abi_union_UDD_env_bridge
.p2align 4
.globl aggregate_abi_union_USI_env_bridge
.type aggregate_abi_union_USI_env_bridge,@function
aggregate_abi_union_USI_env_bridge:
 movq %rdi,%rax
 movq %rsi,%rdi
 jmp aggregate_abi_union_USI_env
.size aggregate_abi_union_USI_env_bridge,.-aggregate_abi_union_USI_env_bridge
.p2align 4
.globl aggregate_abi_union_QS_env_bridge
.type aggregate_abi_union_QS_env_bridge,@function
aggregate_abi_union_QS_env_bridge:
 movq %rdi,%rax
 movq %rsi,%rdi
 jmp aggregate_abi_union_QS_env
.size aggregate_abi_union_QS_env_bridge,.-aggregate_abi_union_QS_env_bridge
.p2align 4
.globl aggregate_abi_union_PS_env_bridge
.type aggregate_abi_union_PS_env_bridge,@function
aggregate_abi_union_PS_env_bridge:
 movq %rdi,%rax
 movq %rsi,%rdi
 jmp aggregate_abi_union_PS_env
.size aggregate_abi_union_PS_env_bridge,.-aggregate_abi_union_PS_env_bridge
.p2align 4
.globl aggregate_abi_union_QR_env_bridge
.type aggregate_abi_union_QR_env_bridge,@function
aggregate_abi_union_QR_env_bridge:
 movq %rdi,%rax
 movq %rsi,%rdi
 jmp aggregate_abi_union_QR_env
.size aggregate_abi_union_QR_env_bridge,.-aggregate_abi_union_QR_env_bridge
.p2align 4
.globl aggregate_abi_union_PR_env_bridge
.type aggregate_abi_union_PR_env_bridge,@function
aggregate_abi_union_PR_env_bridge:
 movq %rdi,%rax
 movq %rsi,%rdi
 jmp aggregate_abi_union_PR_env
.size aggregate_abi_union_PR_env_bridge,.-aggregate_abi_union_PR_env_bridge
.section .note.GNU-stack,"",@progbits

.text
.p2align 4
.globl aggregate_abi_union_pressure_bridge
.type aggregate_abi_union_pressure_bridge,@function
aggregate_abi_union_pressure_bridge:
 pushq %r12
 movq %rdi,%r12
 call aggregate_abi_union_pressure
 cmpq %r12,%rax
 jne .Lunion_pressure_bad_bridge
 popq %r12
 ret
.Lunion_pressure_bad_bridge:
 ud2
.size aggregate_abi_union_pressure_bridge,.-aggregate_abi_union_pressure_bridge
.globl aggregate_abi_union_pressure_asm
.type aggregate_abi_union_pressure_asm,@function
aggregate_abi_union_pressure_asm:
 cmpb $1,%al
 jne .Lunion_pressure_bad
 cmpq $1,%rsi
 jne .Lunion_pressure_bad
 cmpq $2,%rdx
 jne .Lunion_pressure_bad
 cmpq $3,%rcx
 jne .Lunion_pressure_bad
 cmpq $4,%r8
 jne .Lunion_pressure_bad
 cmpq $5,%r9
 jne .Lunion_pressure_bad
 # Preserve all argument banks and original AL around the independent C check.
 subq $200,%rsp
 movq %rdi,0(%rsp)
 movq %rsi,8(%rsp)
 movq %rdx,16(%rsp)
 movq %rcx,24(%rsp)
 movq %r8,32(%rsp)
 movq %r9,40(%rsp)
 movq %rax,48(%rsp)
 movdqu %xmm0,64(%rsp)
 leaq 200(%rsp),%rdi
 leaq 64(%rsp),%rsi
 call aggregate_abi_union_pressure_stack_check
 movq 0(%rsp),%rdi
 movq 8(%rsp),%rsi
 movq 16(%rsp),%rdx
 movq 24(%rsp),%rcx
 movq 32(%rsp),%r8
 movq 40(%rsp),%r9
 movq 48(%rsp),%rax
 movdqu 64(%rsp),%xmm0
 addq $200,%rsp
 jmp aggregate_abi_union_pressure_read
.Lunion_pressure_bad:
 ud2
.size aggregate_abi_union_pressure_asm,.-aggregate_abi_union_pressure_asm

.text
.globl aggregate_abi_union_guard17
.type aggregate_abi_union_guard17,@function
aggregate_abi_union_guard17:
 jmp aggregate_abi_union_U17_indirect
.size aggregate_abi_union_guard17,.-aggregate_abi_union_guard17

.text
.globl aggregate_abi_union_guard4096
.type aggregate_abi_union_guard4096,@function
aggregate_abi_union_guard4096:
 jmp aggregate_abi_union_limit_direct
.size aggregate_abi_union_guard4096,.-aggregate_abi_union_guard4096

.text
.globl aggregate_abi_union_pressure_B_bridge
.type aggregate_abi_union_pressure_B_bridge,@function
aggregate_abi_union_pressure_B_bridge:
 pushq %r12
 movq %rdi,%r12
 call aggregate_abi_union_pressure_B
 cmpq %r12,%rax
 jne .Lunion_pressure_B_bad_bridge
 popq %r12
 ret
.Lunion_pressure_B_bad_bridge:
 ud2
.size aggregate_abi_union_pressure_B_bridge,.-aggregate_abi_union_pressure_B_bridge
.globl aggregate_abi_union_pressure_B_asm
.type aggregate_abi_union_pressure_B_asm,@function
aggregate_abi_union_pressure_B_asm:
 cmpb $8,%al
 jne .Lunion_pressure_B_bad
 cmpq $77,%rsi
 jne .Lunion_pressure_B_bad
 cmpq $99,%rdx
 jne .Lunion_pressure_B_bad
 cmpq $101,%rcx
 jne .Lunion_pressure_B_bad
 jmp aggregate_abi_union_pressure_B_read
.Lunion_pressure_B_bad:
 ud2
.size aggregate_abi_union_pressure_B_asm,.-aggregate_abi_union_pressure_B_asm
