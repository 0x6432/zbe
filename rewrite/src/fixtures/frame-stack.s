.text
.globl zbe_on_stack
.type zbe_on_stack, @function
zbe_on_stack:
	pushq %rbp
	movq %rsp, %rbp
	pushq %r12
	movq %rsp, %r12
	movq %rdi, %rsp
	call *%rsi
	movq %r12, %rsp
	popq %r12
	leave
	ret
.size zbe_on_stack, .-zbe_on_stack
.section .note.GNU-stack,"",@progbits
