.text
.globl aggregate_abi_call_targets_B3_env_target
.type aggregate_abi_call_targets_B3_env_target,@function
aggregate_abi_call_targets_B3_env_target:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_B3_env_target
 jmp aggregate_abi_call_targets_B3_echo
.Lbad_B3_env_target:
 ud2
.size aggregate_abi_call_targets_B3_env_target,.-aggregate_abi_call_targets_B3_env_target
.globl aggregate_abi_call_targets_B3_env_alt
.type aggregate_abi_call_targets_B3_env_alt,@function
aggregate_abi_call_targets_B3_env_alt:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_B3_env_alt
 jmp aggregate_abi_call_targets_B3_echo_alt
.Lbad_B3_env_alt:
 ud2
.size aggregate_abi_call_targets_B3_env_alt,.-aggregate_abi_call_targets_B3_env_alt
.globl aggregate_abi_call_targets_B3_alias_target
.type aggregate_abi_call_targets_B3_alias_target,@function
aggregate_abi_call_targets_B3_alias_target:
 leaq aggregate_abi_call_targets_B3_alias_target(%rip),%r10
 cmpq %r10,%rax
 jne .Lbad_B3_alias_target
 jmp aggregate_abi_call_targets_B3_echo
.Lbad_B3_alias_target:
 ud2
.size aggregate_abi_call_targets_B3_alias_target,.-aggregate_abi_call_targets_B3_alias_target
.globl aggregate_abi_call_targets_B3_bridge
.type aggregate_abi_call_targets_B3_bridge,@function
aggregate_abi_call_targets_B3_bridge:
 movq aggregate_abi_call_targets_expected_env(%rip),%rax
 jmp aggregate_abi_call_targets_B3_env
.size aggregate_abi_call_targets_B3_bridge,.-aggregate_abi_call_targets_B3_bridge
.globl aggregate_abi_call_targets_I13_env_target
.type aggregate_abi_call_targets_I13_env_target,@function
aggregate_abi_call_targets_I13_env_target:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_I13_env_target
 jmp aggregate_abi_call_targets_I13_echo
.Lbad_I13_env_target:
 ud2
.size aggregate_abi_call_targets_I13_env_target,.-aggregate_abi_call_targets_I13_env_target
.globl aggregate_abi_call_targets_I13_env_alt
.type aggregate_abi_call_targets_I13_env_alt,@function
aggregate_abi_call_targets_I13_env_alt:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_I13_env_alt
 jmp aggregate_abi_call_targets_I13_echo_alt
.Lbad_I13_env_alt:
 ud2
.size aggregate_abi_call_targets_I13_env_alt,.-aggregate_abi_call_targets_I13_env_alt
.globl aggregate_abi_call_targets_I13_alias_target
.type aggregate_abi_call_targets_I13_alias_target,@function
aggregate_abi_call_targets_I13_alias_target:
 leaq aggregate_abi_call_targets_I13_alias_target(%rip),%r10
 cmpq %r10,%rax
 jne .Lbad_I13_alias_target
 jmp aggregate_abi_call_targets_I13_echo
.Lbad_I13_alias_target:
 ud2
.size aggregate_abi_call_targets_I13_alias_target,.-aggregate_abi_call_targets_I13_alias_target
.globl aggregate_abi_call_targets_I13_bridge
.type aggregate_abi_call_targets_I13_bridge,@function
aggregate_abi_call_targets_I13_bridge:
 movq aggregate_abi_call_targets_expected_env(%rip),%rax
 jmp aggregate_abi_call_targets_I13_env
.size aggregate_abi_call_targets_I13_bridge,.-aggregate_abi_call_targets_I13_bridge
.globl aggregate_abi_call_targets_W8_env_target
.type aggregate_abi_call_targets_W8_env_target,@function
aggregate_abi_call_targets_W8_env_target:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_W8_env_target
 jmp aggregate_abi_call_targets_W8_echo
.Lbad_W8_env_target:
 ud2
.size aggregate_abi_call_targets_W8_env_target,.-aggregate_abi_call_targets_W8_env_target
.globl aggregate_abi_call_targets_W8_env_alt
.type aggregate_abi_call_targets_W8_env_alt,@function
aggregate_abi_call_targets_W8_env_alt:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_W8_env_alt
 jmp aggregate_abi_call_targets_W8_echo_alt
.Lbad_W8_env_alt:
 ud2
.size aggregate_abi_call_targets_W8_env_alt,.-aggregate_abi_call_targets_W8_env_alt
.globl aggregate_abi_call_targets_W8_alias_target
.type aggregate_abi_call_targets_W8_alias_target,@function
aggregate_abi_call_targets_W8_alias_target:
 leaq aggregate_abi_call_targets_W8_alias_target(%rip),%r10
 cmpq %r10,%rax
 jne .Lbad_W8_alias_target
 jmp aggregate_abi_call_targets_W8_echo
.Lbad_W8_alias_target:
 ud2
.size aggregate_abi_call_targets_W8_alias_target,.-aggregate_abi_call_targets_W8_alias_target
.globl aggregate_abi_call_targets_W8_bridge
.type aggregate_abi_call_targets_W8_bridge,@function
aggregate_abi_call_targets_W8_bridge:
 movq aggregate_abi_call_targets_expected_env(%rip),%rax
 jmp aggregate_abi_call_targets_W8_env
.size aggregate_abi_call_targets_W8_bridge,.-aggregate_abi_call_targets_W8_bridge
.globl aggregate_abi_call_targets_S4_env_target
.type aggregate_abi_call_targets_S4_env_target,@function
aggregate_abi_call_targets_S4_env_target:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_S4_env_target
 jmp aggregate_abi_call_targets_S4_echo
.Lbad_S4_env_target:
 ud2
.size aggregate_abi_call_targets_S4_env_target,.-aggregate_abi_call_targets_S4_env_target
.globl aggregate_abi_call_targets_S4_env_alt
.type aggregate_abi_call_targets_S4_env_alt,@function
aggregate_abi_call_targets_S4_env_alt:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_S4_env_alt
 jmp aggregate_abi_call_targets_S4_echo_alt
.Lbad_S4_env_alt:
 ud2
.size aggregate_abi_call_targets_S4_env_alt,.-aggregate_abi_call_targets_S4_env_alt
.globl aggregate_abi_call_targets_S4_alias_target
.type aggregate_abi_call_targets_S4_alias_target,@function
aggregate_abi_call_targets_S4_alias_target:
 leaq aggregate_abi_call_targets_S4_alias_target(%rip),%r10
 cmpq %r10,%rax
 jne .Lbad_S4_alias_target
 jmp aggregate_abi_call_targets_S4_echo
.Lbad_S4_alias_target:
 ud2
.size aggregate_abi_call_targets_S4_alias_target,.-aggregate_abi_call_targets_S4_alias_target
.globl aggregate_abi_call_targets_S4_bridge
.type aggregate_abi_call_targets_S4_bridge,@function
aggregate_abi_call_targets_S4_bridge:
 movq aggregate_abi_call_targets_expected_env(%rip),%rax
 jmp aggregate_abi_call_targets_S4_env
.size aggregate_abi_call_targets_S4_bridge,.-aggregate_abi_call_targets_S4_bridge
.globl aggregate_abi_call_targets_D8_env_target
.type aggregate_abi_call_targets_D8_env_target,@function
aggregate_abi_call_targets_D8_env_target:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_D8_env_target
 jmp aggregate_abi_call_targets_D8_echo
.Lbad_D8_env_target:
 ud2
.size aggregate_abi_call_targets_D8_env_target,.-aggregate_abi_call_targets_D8_env_target
.globl aggregate_abi_call_targets_D8_env_alt
.type aggregate_abi_call_targets_D8_env_alt,@function
aggregate_abi_call_targets_D8_env_alt:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_D8_env_alt
 jmp aggregate_abi_call_targets_D8_echo_alt
.Lbad_D8_env_alt:
 ud2
.size aggregate_abi_call_targets_D8_env_alt,.-aggregate_abi_call_targets_D8_env_alt
.globl aggregate_abi_call_targets_D8_alias_target
.type aggregate_abi_call_targets_D8_alias_target,@function
aggregate_abi_call_targets_D8_alias_target:
 leaq aggregate_abi_call_targets_D8_alias_target(%rip),%r10
 cmpq %r10,%rax
 jne .Lbad_D8_alias_target
 jmp aggregate_abi_call_targets_D8_echo
.Lbad_D8_alias_target:
 ud2
.size aggregate_abi_call_targets_D8_alias_target,.-aggregate_abi_call_targets_D8_alias_target
.globl aggregate_abi_call_targets_D8_bridge
.type aggregate_abi_call_targets_D8_bridge,@function
aggregate_abi_call_targets_D8_bridge:
 movq aggregate_abi_call_targets_expected_env(%rip),%rax
 jmp aggregate_abi_call_targets_D8_env
.size aggregate_abi_call_targets_D8_bridge,.-aggregate_abi_call_targets_D8_bridge
.globl aggregate_abi_call_targets_SS12_env_target
.type aggregate_abi_call_targets_SS12_env_target,@function
aggregate_abi_call_targets_SS12_env_target:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_SS12_env_target
 jmp aggregate_abi_call_targets_SS12_echo
.Lbad_SS12_env_target:
 ud2
.size aggregate_abi_call_targets_SS12_env_target,.-aggregate_abi_call_targets_SS12_env_target
.globl aggregate_abi_call_targets_SS12_env_alt
.type aggregate_abi_call_targets_SS12_env_alt,@function
aggregate_abi_call_targets_SS12_env_alt:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_SS12_env_alt
 jmp aggregate_abi_call_targets_SS12_echo_alt
.Lbad_SS12_env_alt:
 ud2
.size aggregate_abi_call_targets_SS12_env_alt,.-aggregate_abi_call_targets_SS12_env_alt
.globl aggregate_abi_call_targets_SS12_alias_target
.type aggregate_abi_call_targets_SS12_alias_target,@function
aggregate_abi_call_targets_SS12_alias_target:
 leaq aggregate_abi_call_targets_SS12_alias_target(%rip),%r10
 cmpq %r10,%rax
 jne .Lbad_SS12_alias_target
 jmp aggregate_abi_call_targets_SS12_echo
.Lbad_SS12_alias_target:
 ud2
.size aggregate_abi_call_targets_SS12_alias_target,.-aggregate_abi_call_targets_SS12_alias_target
.globl aggregate_abi_call_targets_SS12_bridge
.type aggregate_abi_call_targets_SS12_bridge,@function
aggregate_abi_call_targets_SS12_bridge:
 movq aggregate_abi_call_targets_expected_env(%rip),%rax
 jmp aggregate_abi_call_targets_SS12_env
.size aggregate_abi_call_targets_SS12_bridge,.-aggregate_abi_call_targets_SS12_bridge
.globl aggregate_abi_call_targets_DD16_env_target
.type aggregate_abi_call_targets_DD16_env_target,@function
aggregate_abi_call_targets_DD16_env_target:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_DD16_env_target
 jmp aggregate_abi_call_targets_DD16_echo
.Lbad_DD16_env_target:
 ud2
.size aggregate_abi_call_targets_DD16_env_target,.-aggregate_abi_call_targets_DD16_env_target
.globl aggregate_abi_call_targets_DD16_env_alt
.type aggregate_abi_call_targets_DD16_env_alt,@function
aggregate_abi_call_targets_DD16_env_alt:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_DD16_env_alt
 jmp aggregate_abi_call_targets_DD16_echo_alt
.Lbad_DD16_env_alt:
 ud2
.size aggregate_abi_call_targets_DD16_env_alt,.-aggregate_abi_call_targets_DD16_env_alt
.globl aggregate_abi_call_targets_DD16_alias_target
.type aggregate_abi_call_targets_DD16_alias_target,@function
aggregate_abi_call_targets_DD16_alias_target:
 leaq aggregate_abi_call_targets_DD16_alias_target(%rip),%r10
 cmpq %r10,%rax
 jne .Lbad_DD16_alias_target
 jmp aggregate_abi_call_targets_DD16_echo
.Lbad_DD16_alias_target:
 ud2
.size aggregate_abi_call_targets_DD16_alias_target,.-aggregate_abi_call_targets_DD16_alias_target
.globl aggregate_abi_call_targets_DD16_bridge
.type aggregate_abi_call_targets_DD16_bridge,@function
aggregate_abi_call_targets_DD16_bridge:
 movq aggregate_abi_call_targets_expected_env(%rip),%rax
 jmp aggregate_abi_call_targets_DD16_env
.size aggregate_abi_call_targets_DD16_bridge,.-aggregate_abi_call_targets_DD16_bridge
.globl aggregate_abi_call_targets_IS16_env_target
.type aggregate_abi_call_targets_IS16_env_target,@function
aggregate_abi_call_targets_IS16_env_target:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_IS16_env_target
 jmp aggregate_abi_call_targets_IS16_echo
.Lbad_IS16_env_target:
 ud2
.size aggregate_abi_call_targets_IS16_env_target,.-aggregate_abi_call_targets_IS16_env_target
.globl aggregate_abi_call_targets_IS16_env_alt
.type aggregate_abi_call_targets_IS16_env_alt,@function
aggregate_abi_call_targets_IS16_env_alt:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_IS16_env_alt
 jmp aggregate_abi_call_targets_IS16_echo_alt
.Lbad_IS16_env_alt:
 ud2
.size aggregate_abi_call_targets_IS16_env_alt,.-aggregate_abi_call_targets_IS16_env_alt
.globl aggregate_abi_call_targets_IS16_alias_target
.type aggregate_abi_call_targets_IS16_alias_target,@function
aggregate_abi_call_targets_IS16_alias_target:
 leaq aggregate_abi_call_targets_IS16_alias_target(%rip),%r10
 cmpq %r10,%rax
 jne .Lbad_IS16_alias_target
 jmp aggregate_abi_call_targets_IS16_echo
.Lbad_IS16_alias_target:
 ud2
.size aggregate_abi_call_targets_IS16_alias_target,.-aggregate_abi_call_targets_IS16_alias_target
.globl aggregate_abi_call_targets_IS16_bridge
.type aggregate_abi_call_targets_IS16_bridge,@function
aggregate_abi_call_targets_IS16_bridge:
 movq aggregate_abi_call_targets_expected_env(%rip),%rax
 jmp aggregate_abi_call_targets_IS16_env
.size aggregate_abi_call_targets_IS16_bridge,.-aggregate_abi_call_targets_IS16_bridge
.globl aggregate_abi_call_targets_SI16_env_target
.type aggregate_abi_call_targets_SI16_env_target,@function
aggregate_abi_call_targets_SI16_env_target:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_SI16_env_target
 jmp aggregate_abi_call_targets_SI16_echo
.Lbad_SI16_env_target:
 ud2
.size aggregate_abi_call_targets_SI16_env_target,.-aggregate_abi_call_targets_SI16_env_target
.globl aggregate_abi_call_targets_SI16_env_alt
.type aggregate_abi_call_targets_SI16_env_alt,@function
aggregate_abi_call_targets_SI16_env_alt:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_SI16_env_alt
 jmp aggregate_abi_call_targets_SI16_echo_alt
.Lbad_SI16_env_alt:
 ud2
.size aggregate_abi_call_targets_SI16_env_alt,.-aggregate_abi_call_targets_SI16_env_alt
.globl aggregate_abi_call_targets_SI16_alias_target
.type aggregate_abi_call_targets_SI16_alias_target,@function
aggregate_abi_call_targets_SI16_alias_target:
 leaq aggregate_abi_call_targets_SI16_alias_target(%rip),%r10
 cmpq %r10,%rax
 jne .Lbad_SI16_alias_target
 jmp aggregate_abi_call_targets_SI16_echo
.Lbad_SI16_alias_target:
 ud2
.size aggregate_abi_call_targets_SI16_alias_target,.-aggregate_abi_call_targets_SI16_alias_target
.globl aggregate_abi_call_targets_SI16_bridge
.type aggregate_abi_call_targets_SI16_bridge,@function
aggregate_abi_call_targets_SI16_bridge:
 movq aggregate_abi_call_targets_expected_env(%rip),%rax
 jmp aggregate_abi_call_targets_SI16_env
.size aggregate_abi_call_targets_SI16_bridge,.-aggregate_abi_call_targets_SI16_bridge
.globl aggregate_abi_call_targets_II16_env_target
.type aggregate_abi_call_targets_II16_env_target,@function
aggregate_abi_call_targets_II16_env_target:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_II16_env_target
 jmp aggregate_abi_call_targets_II16_echo
.Lbad_II16_env_target:
 ud2
.size aggregate_abi_call_targets_II16_env_target,.-aggregate_abi_call_targets_II16_env_target
.globl aggregate_abi_call_targets_II16_env_alt
.type aggregate_abi_call_targets_II16_env_alt,@function
aggregate_abi_call_targets_II16_env_alt:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_II16_env_alt
 jmp aggregate_abi_call_targets_II16_echo_alt
.Lbad_II16_env_alt:
 ud2
.size aggregate_abi_call_targets_II16_env_alt,.-aggregate_abi_call_targets_II16_env_alt
.globl aggregate_abi_call_targets_II16_alias_target
.type aggregate_abi_call_targets_II16_alias_target,@function
aggregate_abi_call_targets_II16_alias_target:
 leaq aggregate_abi_call_targets_II16_alias_target(%rip),%r10
 cmpq %r10,%rax
 jne .Lbad_II16_alias_target
 jmp aggregate_abi_call_targets_II16_echo
.Lbad_II16_alias_target:
 ud2
.size aggregate_abi_call_targets_II16_alias_target,.-aggregate_abi_call_targets_II16_alias_target
.globl aggregate_abi_call_targets_II16_bridge
.type aggregate_abi_call_targets_II16_bridge,@function
aggregate_abi_call_targets_II16_bridge:
 movq aggregate_abi_call_targets_expected_env(%rip),%rax
 jmp aggregate_abi_call_targets_II16_env
.size aggregate_abi_call_targets_II16_bridge,.-aggregate_abi_call_targets_II16_bridge
.globl aggregate_abi_call_targets_N16_env_target
.type aggregate_abi_call_targets_N16_env_target,@function
aggregate_abi_call_targets_N16_env_target:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_N16_env_target
 jmp aggregate_abi_call_targets_N16_echo
.Lbad_N16_env_target:
 ud2
.size aggregate_abi_call_targets_N16_env_target,.-aggregate_abi_call_targets_N16_env_target
.globl aggregate_abi_call_targets_N16_env_alt
.type aggregate_abi_call_targets_N16_env_alt,@function
aggregate_abi_call_targets_N16_env_alt:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_N16_env_alt
 jmp aggregate_abi_call_targets_N16_echo_alt
.Lbad_N16_env_alt:
 ud2
.size aggregate_abi_call_targets_N16_env_alt,.-aggregate_abi_call_targets_N16_env_alt
.globl aggregate_abi_call_targets_N16_alias_target
.type aggregate_abi_call_targets_N16_alias_target,@function
aggregate_abi_call_targets_N16_alias_target:
 leaq aggregate_abi_call_targets_N16_alias_target(%rip),%r10
 cmpq %r10,%rax
 jne .Lbad_N16_alias_target
 jmp aggregate_abi_call_targets_N16_echo
.Lbad_N16_alias_target:
 ud2
.size aggregate_abi_call_targets_N16_alias_target,.-aggregate_abi_call_targets_N16_alias_target
.globl aggregate_abi_call_targets_N16_bridge
.type aggregate_abi_call_targets_N16_bridge,@function
aggregate_abi_call_targets_N16_bridge:
 movq aggregate_abi_call_targets_expected_env(%rip),%rax
 jmp aggregate_abi_call_targets_N16_env
.size aggregate_abi_call_targets_N16_bridge,.-aggregate_abi_call_targets_N16_bridge
.globl aggregate_abi_call_targets_M23_env_target
.type aggregate_abi_call_targets_M23_env_target,@function
aggregate_abi_call_targets_M23_env_target:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_M23_env_target
 jmp aggregate_abi_call_targets_M23_echo
.Lbad_M23_env_target:
 ud2
.size aggregate_abi_call_targets_M23_env_target,.-aggregate_abi_call_targets_M23_env_target
.globl aggregate_abi_call_targets_M23_env_alt
.type aggregate_abi_call_targets_M23_env_alt,@function
aggregate_abi_call_targets_M23_env_alt:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_M23_env_alt
 jmp aggregate_abi_call_targets_M23_echo_alt
.Lbad_M23_env_alt:
 ud2
.size aggregate_abi_call_targets_M23_env_alt,.-aggregate_abi_call_targets_M23_env_alt
.globl aggregate_abi_call_targets_M23_alias_target
.type aggregate_abi_call_targets_M23_alias_target,@function
aggregate_abi_call_targets_M23_alias_target:
 leaq aggregate_abi_call_targets_M23_alias_target(%rip),%r10
 cmpq %r10,%rax
 jne .Lbad_M23_alias_target
 jmp aggregate_abi_call_targets_M23_echo
.Lbad_M23_alias_target:
 ud2
.size aggregate_abi_call_targets_M23_alias_target,.-aggregate_abi_call_targets_M23_alias_target
.globl aggregate_abi_call_targets_M23_bridge
.type aggregate_abi_call_targets_M23_bridge,@function
aggregate_abi_call_targets_M23_bridge:
 movq aggregate_abi_call_targets_expected_env(%rip),%rax
 jmp aggregate_abi_call_targets_M23_env
.size aggregate_abi_call_targets_M23_bridge,.-aggregate_abi_call_targets_M23_bridge
.globl aggregate_abi_call_targets_A32_env_target
.type aggregate_abi_call_targets_A32_env_target,@function
aggregate_abi_call_targets_A32_env_target:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_A32_env_target
 jmp aggregate_abi_call_targets_A32_echo
.Lbad_A32_env_target:
 ud2
.size aggregate_abi_call_targets_A32_env_target,.-aggregate_abi_call_targets_A32_env_target
.globl aggregate_abi_call_targets_A32_env_alt
.type aggregate_abi_call_targets_A32_env_alt,@function
aggregate_abi_call_targets_A32_env_alt:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lbad_A32_env_alt
 jmp aggregate_abi_call_targets_A32_echo_alt
.Lbad_A32_env_alt:
 ud2
.size aggregate_abi_call_targets_A32_env_alt,.-aggregate_abi_call_targets_A32_env_alt
.globl aggregate_abi_call_targets_A32_alias_target
.type aggregate_abi_call_targets_A32_alias_target,@function
aggregate_abi_call_targets_A32_alias_target:
 leaq aggregate_abi_call_targets_A32_alias_target(%rip),%r10
 cmpq %r10,%rax
 jne .Lbad_A32_alias_target
 jmp aggregate_abi_call_targets_A32_echo
.Lbad_A32_alias_target:
 ud2
.size aggregate_abi_call_targets_A32_alias_target,.-aggregate_abi_call_targets_A32_alias_target
.globl aggregate_abi_call_targets_A32_bridge
.type aggregate_abi_call_targets_A32_bridge,@function
aggregate_abi_call_targets_A32_bridge:
 movq aggregate_abi_call_targets_expected_env(%rip),%rax
 jmp aggregate_abi_call_targets_A32_env
.size aggregate_abi_call_targets_A32_bridge,.-aggregate_abi_call_targets_A32_bridge
.globl aggregate_abi_call_targets_clobber
.type aggregate_abi_call_targets_clobber,@function
aggregate_abi_call_targets_clobber:
 xorq %rax,%rax
 xorq %rdi,%rdi
 xorq %rsi,%rsi
 xorq %rdx,%rdx
 xorq %rcx,%rcx
 xorq %r8,%r8
 xorq %r9,%r9
 xorq %r10,%r10
 xorq %r11,%r11
 pxor %xmm0,%xmm0
 pxor %xmm1,%xmm1
 pxor %xmm2,%xmm2
 pxor %xmm3,%xmm3
 pxor %xmm4,%xmm4
 pxor %xmm5,%xmm5
 pxor %xmm6,%xmm6
 pxor %xmm7,%xmm7
 pxor %xmm8,%xmm8
 pxor %xmm9,%xmm9
 pxor %xmm10,%xmm10
 pxor %xmm11,%xmm11
 pxor %xmm12,%xmm12
 pxor %xmm13,%xmm13
 pxor %xmm14,%xmm14
 pxor %xmm15,%xmm15
 movl $1,%eax
 ret
.size aggregate_abi_call_targets_clobber,.-aggregate_abi_call_targets_clobber
.section .note.GNU-stack,"",@progbits

.text
.globl aggregate_abi_call_targets_pressure_target
aggregate_abi_call_targets_pressure_target:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lpressure_bad
 movq %rsp,%r10
 andq $15,%r10
 cmpq $8,%r10
 jne .Lpressure_bad
 cmpq $1,%rsi
 jne .Lpressure_bad
 cmpq $2,%rdx
 jne .Lpressure_bad
 cmpq $3,%rcx
 jne .Lpressure_bad
 cmpq $4,%r8
 jne .Lpressure_bad
 cmpq $5,%r9
 jne .Lpressure_bad
 cmpl $0x34343434,8(%rsp)
 jne .Lpressure_bad
 movabsq $0x3434343434343434,%r10
 cmpq %r10,16(%rsp)
 jne .Lpressure_bad
 cmpq $99,48(%rsp)
 jne .Lpressure_bad
 cmpl $0x56565656,56(%rsp)
 jne .Lpressure_bad
 cmpl $0x56565656,60(%rsp)
 jne .Lpressure_bad
 cmpl $0x56565656,64(%rsp)
 jne .Lpressure_bad
 cmpb $17,24(%rsp)
 jne .Lpressure_bad
 cmpb $18,25(%rsp)
 jne .Lpressure_bad
 cmpb $19,26(%rsp)
 jne .Lpressure_bad
 cmpb $20,27(%rsp)
 jne .Lpressure_bad
 cmpb $21,28(%rsp)
 jne .Lpressure_bad
 cmpb $22,29(%rsp)
 jne .Lpressure_bad
 cmpb $23,30(%rsp)
 jne .Lpressure_bad
 cmpb $24,31(%rsp)
 jne .Lpressure_bad
 cmpb $25,32(%rsp)
 jne .Lpressure_bad
 cmpb $26,33(%rsp)
 jne .Lpressure_bad
 cmpb $27,34(%rsp)
 jne .Lpressure_bad
 cmpb $28,35(%rsp)
 jne .Lpressure_bad
 cmpb $29,36(%rsp)
 jne .Lpressure_bad
 cmpb $30,37(%rsp)
 jne .Lpressure_bad
 cmpb $31,38(%rsp)
 jne .Lpressure_bad
 cmpb $32,39(%rsp)
 jne .Lpressure_bad
 cmpb $33,40(%rsp)
 jne .Lpressure_bad
 cmpb $34,41(%rsp)
 jne .Lpressure_bad
 cmpb $35,42(%rsp)
 jne .Lpressure_bad
 cmpb $36,43(%rsp)
 jne .Lpressure_bad
 cmpb $37,44(%rsp)
 jne .Lpressure_bad
 cmpb $38,45(%rsp)
 jne .Lpressure_bad
 cmpb $39,46(%rsp)
 jne .Lpressure_bad
 movabsq $4607182418800017408,%r10
 movq %xmm0,%r11
 cmpq %r10,%r11
 jne .Lpressure_bad
 movabsq $4611686018427387904,%r10
 movq %xmm1,%r11
 cmpq %r10,%r11
 jne .Lpressure_bad
 movabsq $4613937818241073152,%r10
 movq %xmm2,%r11
 cmpq %r10,%r11
 jne .Lpressure_bad
 movabsq $4616189618054758400,%r10
 movq %xmm3,%r11
 cmpq %r10,%r11
 jne .Lpressure_bad
 movabsq $4617315517961601024,%r10
 movq %xmm4,%r11
 cmpq %r10,%r11
 jne .Lpressure_bad
 movabsq $4618441417868443648,%r10
 movq %xmm5,%r11
 cmpq %r10,%r11
 jne .Lpressure_bad
 movabsq $4619567317775286272,%r10
 movq %xmm6,%r11
 cmpq %r10,%r11
 jne .Lpressure_bad
 movabsq $4620693217682128896,%r10
 movq %xmm7,%r11
 cmpq %r10,%r11
 jne .Lpressure_bad
 movabsq $4621256167635550208,%r10
 movq 72(%rsp),%r11
 cmpq %r10,%r11
 jne .Lpressure_bad
 jmp aggregate_abi_call_targets_pressure_c
.Lpressure_bad:
 ud2
.globl aggregate_abi_call_targets_pressure_bridge
aggregate_abi_call_targets_pressure_bridge:
 subq $24,%rsp
 movq %rdi,(%rsp)
 call aggregate_abi_call_targets_pressure
 cmpq (%rsp),%rax
 jne .Lbridge_bad
 addq $24,%rsp
 ret
.Lbridge_bad:
 ud2
.globl aggregate_abi_call_targets_double_target
aggregate_abi_call_targets_double_target:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lpressure_bad
 jmp aggregate_abi_call_targets_double_c
.globl aggregate_abi_call_targets_void_target
aggregate_abi_call_targets_void_target:
 cmpq aggregate_abi_call_targets_expected_env(%rip),%rax
 jne .Lpressure_bad
 jmp aggregate_abi_call_targets_void_c
.section .note.GNU-stack,"",@progbits
