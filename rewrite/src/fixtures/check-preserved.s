# SysV test adapter: seed all five allocatable preserved registers, call a
# no-argument generated function, verify all 64 bits, then restore our caller.
.text
.globl zbe_check_preserved
.type zbe_check_preserved, @function
zbe_check_preserved:
    pushq %rbx
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15
    movabsq $0x1234567887654321, %rbx
    movabsq $0x2345678998765432, %r12
    movabsq $0x3456789aa9876543, %r13
    movabsq $0x456789abba987654, %r14
    movabsq $0x56789abccba98765, %r15
    call *%rdi
    movabsq $0x1234567887654321, %rax
    cmpq %rax, %rbx
    jne .Lzbe_preserved_fail
    movabsq $0x2345678998765432, %rax
    cmpq %rax, %r12
    jne .Lzbe_preserved_fail
    movabsq $0x3456789aa9876543, %rax
    cmpq %rax, %r13
    jne .Lzbe_preserved_fail
    movabsq $0x456789abba987654, %rax
    cmpq %rax, %r14
    jne .Lzbe_preserved_fail
    movabsq $0x56789abccba98765, %rax
    cmpq %rax, %r15
    jne .Lzbe_preserved_fail
    xorl %eax, %eax
    jmp .Lzbe_preserved_done
.Lzbe_preserved_fail:
    movl $1, %eax
.Lzbe_preserved_done:
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %rbx
    ret
.size zbe_check_preserved, .-zbe_check_preserved
.section .note.GNU-stack,"",@progbits
