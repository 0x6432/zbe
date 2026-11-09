# Extern/GOT foundation — work in progress

This is an unreviewed draft, based on integration draft `3890562118b85be550dcc19f6c400414d3f8672a`. That base has not passed its fresh local integration gate or terminal audit; its exact-commit CI is running. This branch is not production acceptance or a complete extern/GOT implementation.

Current work adds a module-owned `got_symbol` IR operand, conservative decoded-symbol eligibility and an allocation-free eligibility scan after generic and aggregate checks. Scalar-only modules are scanned before the existing empty-plan return. Contextual extern value and call syntax and dedicated/wrapped call-target identity are implemented in the draft. The interpreter refuses reached GOT operands/calls and the native emitter fails closed; GOT materialization and native extern call execution are **not implemented**.

Focused Debug tests covered the naming helper and representative operand, eligibility, call identity and parser behavior. Full three-mode testing, the existing compatibility matrices, independent reviews, secondary calibration audit, terminal audit and exact-commit CI for this new tree remain outstanding. No release, canonical advancement, ABI parity or complete compiler claim is made.
