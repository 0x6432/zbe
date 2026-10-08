//! One-to-one translation of amd64/winabi.c
const std = @import("std");
const assert = std.debug.assert;
// -- imports --
const all = @import("../all.zig");
const tgt = @import("all.zig");
const BIT = all.BIT;
const Blk = all.Blk;
const CALL = all.CALL;
const Fn = all.Fn;
const INS = all.INS;
const INT = all.INT;
const Ins = all.Ins;
const Jret0 = all.Jret0;
const Jretc = all.Jretc;
const Jretw = all.Jretw;
const KBASE = all.KBASE;
const Kl = all.Kl;
const Kw = all.Kw;
const NCLR_WIN = tgt.NCLR_WIN;
const NFPS = tgt.NFPS;
const NGPS_WIN = tgt.NGPS_WIN;
const Oadd = all.ops.Oadd;
const Oalloc8 = all.ops.Oalloc8;
const Oarg = all.ops.Oarg;
const Oargc = all.ops.Oargc;
const Oarge = all.ops.Oarge;
const Oargv = all.ops.Oargv;
const Oblit0 = all.ops.Oblit0;
const Oblit1 = all.ops.Oblit1;
const Ocall = all.ops.Ocall;
const Ocast = all.ops.Ocast;
const Ocopy = all.ops.Ocopy;
const Oload = all.ops.Oload;
const Opar = all.ops.Opar;
const Oparc = all.ops.Oparc;
const Opare = all.ops.Opare;
const Osalloc = all.ops.Osalloc;
const Ostorel = all.ops.Ostorel;
const Ovaarg = all.ops.Ovaarg;
const Ovastart = all.ops.Ovastart;
const PFn = all.PFn;
const R = all.R;
const R10 = tgt.R10;
const R11 = tgt.R11;
const R12 = tgt.R12;
const R13 = tgt.R13;
const R14 = tgt.R14;
const R15 = tgt.R15;
const R8 = tgt.R8;
const R9 = tgt.R9;
const RAX = tgt.RAX;
const RBP = tgt.RBP;
const RBX = tgt.RBX;
const RCX = tgt.RCX;
const RCall = all.RCall;
const RDI = tgt.RDI;
const RDX = tgt.RDX;
const RSI = tgt.RSI;
const RTmp = all.RTmp;
const Ref = all.Ref;
const SLOT = all.SLOT;
const TMP = all.TMP;
const Typ = all.Typ;
const XMM0 = tgt.XMM0;
const XMM1 = tgt.XMM1;
const XMM10 = tgt.XMM10;
const XMM11 = tgt.XMM11;
const XMM12 = tgt.XMM12;
const XMM13 = tgt.XMM13;
const XMM14 = tgt.XMM14;
const XMM2 = tgt.XMM2;
const XMM3 = tgt.XMM3;
const XMM4 = tgt.XMM4;
const XMM5 = tgt.XMM5;
const XMM6 = tgt.XMM6;
const XMM7 = tgt.XMM7;
const XMM8 = tgt.XMM8;
const XMM9 = tgt.XMM9;
const bits = all.bits;
const die = all.die;
const dprint = all.dprint;
const emit = all.emit;
const emiti = all.emiti;
const err = all.err;
const getcon = all.getcon;
const icpy = all.icpy;
const idup = all.idup;
const isarg = all.isarg;
const ispar = all.ispar;
const isret = all.isret;
const newtmp = all.newtmp;
const palloc = all.palloc;
const pnew = all.pnew;
const printfn = all.printfn;
const ptrdiff = all.ptrdiff;
const req = all.req;
const rtype = all.rtype;
const uint = all.uint;
const vnewT = all.vnewT;
// -- end imports --

const ArgPassStyle = enum(i32) {
    APS_Invalid = 0,
    APS_Register,
    APS_InlineOnStack,
    APS_CopyAndPointerInRegister,
    APS_CopyAndPointerOnStack,
    APS_VarargsTag,
    APS_EnvTag,
};

const ArgClass = struct {
    type: ?*Typ,
    style: ArgPassStyle,
    @"align": i32,
    size: uint,
    cls: i32,
    ref: Ref,
};

const ExtraAlloc = struct {
    instr: Ins,
    link: ?*ExtraAlloc,
};

inline fn ALIGN_DOWN(n: anytype, a: @TypeOf(n)) @TypeOf(n) {
    return n & ~(a - 1);
}
inline fn ALIGN_UP(n: anytype, a: @TypeOf(n)) @TypeOf(n) {
    return ALIGN_DOWN(n + a - 1, a);
}

// Number of stack bytes required be reserved for the callee.
const SHADOW_SPACE_SIZE = 32;

pub var amd64_winabi_rsave = [_]i32{
    RCX,  RDX,  R8,    R9,    R10,   R11,   RAX,   XMM0,
    XMM1, XMM2, XMM3,  XMM4,  XMM5,  XMM6,  XMM7,  XMM8,
    XMM9, XMM10, XMM11, XMM12, XMM13, XMM14, -1,
};
pub var amd64_winabi_rclob = [_]i32{ RBX, R12, R13, R14, R15, RSI, RDI, -1 };

comptime {
    if (!(amd64_winabi_rsave.len == NGPS_WIN + NFPS + 1 and
        amd64_winabi_rclob.len == NCLR_WIN + 1))
        @compileError("winabi_arrays_ok");
}

// layout of call's second argument (RCall)
//
// bit 0: rax returned
// bit 1: xmm0 returned
// bits 23: 0
// bits 4567: rcx, rdx, r8, r9 passed
// bits 89ab: xmm0,1,2,3 passed
// bit c: env call (rax passed)
// bits d..1f: 0

pub fn amd64_winabi_retregs(r: Ref, p: ?*[2]i32) bits {
    assert(rtype(r) == RCall);

    var b: bits = 0;
    const num_int_returns: i32 = @intCast(r.val & 1);
    const num_float_returns: i32 = @intCast(r.val & 2);
    if (num_int_returns == 1) {
        b |= BIT(RAX);
    } else {
        b |= BIT(XMM0);
    }
    if (p) |q|
        q.* = .{ num_int_returns, num_float_returns };
    return b;
}

fn popcnt(b_: bits) uint {
    var b = b_;
    b = (b & 0x5555555555555555) + ((b >> 1) & 0x5555555555555555);
    b = (b & 0x3333333333333333) + ((b >> 2) & 0x3333333333333333);
    b = (b & 0x0f0f0f0f0f0f0f0f) + ((b >> 4) & 0x0f0f0f0f0f0f0f0f);
    b +%= (b >> 8);
    b +%= (b >> 16);
    b +%= (b >> 32);
    return @intCast(b & 0xff);
}

pub fn amd64_winabi_argregs(r: Ref, p: ?*[2]i32) bits {
    assert(rtype(r) == RCall);

    // On SysV, these are counts. Here, a count isn't sufficient, we actually need
    // to know which ones are in use because they're not necessarily contiguous.
    const int_passed: u32 = (r.val >> 4) & 15;
    const float_passed: u32 = (r.val >> 8) & 15;
    const env_param = ((r.val >> 12) & 1) != 0;

    var b: bits = 0;
    b |= if ((int_passed & 1) != 0) BIT(RCX) else 0;
    b |= if ((int_passed & 2) != 0) BIT(RDX) else 0;
    b |= if ((int_passed & 4) != 0) BIT(R8) else 0;
    b |= if ((int_passed & 8) != 0) BIT(R9) else 0;
    b |= if ((float_passed & 1) != 0) BIT(XMM0) else 0;
    b |= if ((float_passed & 2) != 0) BIT(XMM1) else 0;
    b |= if ((float_passed & 4) != 0) BIT(XMM2) else 0;
    b |= if ((float_passed & 8) != 0) BIT(XMM3) else 0;
    b |= if (env_param) BIT(RAX) else 0;
    if (p) |q| {
        // TODO: The only place this is used is live.c. I'm not sure what should be
        // returned here wrt to using the same counter for int/float regs on win.
        // For now, try the number of registers in use even though they're not
        // contiguous.
        q.* = .{ @intCast(popcnt(int_passed)), @intCast(popcnt(float_passed)) };
    }
    return b;
}

const RegisterUsage = extern struct {
    // Counter for both int/float as they're counted together. Only if the bool's
    // set in regs_passed is the given register *actually* needed for a value
    // (i.e. needs to be saved, etc.).
    num_regs_passed: i32,

    // Indexed first by 0=int, 1=float, use KBASE(cls).
    // Indexed second by register index in calling convention, so for integer,
    // 0=RCX, 1=RDX, 2=R8, 3=R9, and for float XMM0, XMM1, XMM2, XMM3.
    regs_passed: [2][4]bool,

    rax_returned: bool,
    xmm0_returned: bool,

    // This is also used as where the va_start will start for varargs functions
    // (there's no 'Oparv', so we need to keep track of a count here.)
    num_named_args_passed: i32,

    // This is set when classifying the arguments for a call (but not when
    // classifying the parameters of a function definition).
    is_varargs_call: bool,

    has_env: bool,
};

fn register_usage_to_call_arg_value(reg_usage: RegisterUsage) i32 {
    const B = struct {
        fn b(x: bool) i32 {
            return @intFromBool(x);
        }
    }.b;
    return (B(reg_usage.rax_returned) << 0) | //
        (B(reg_usage.xmm0_returned) << 1) | //
        (B(reg_usage.regs_passed[0][0]) << 4) | //
        (B(reg_usage.regs_passed[0][1]) << 5) | //
        (B(reg_usage.regs_passed[0][2]) << 6) | //
        (B(reg_usage.regs_passed[0][3]) << 7) | //
        (B(reg_usage.regs_passed[1][0]) << 8) | //
        (B(reg_usage.regs_passed[1][1]) << 9) | //
        (B(reg_usage.regs_passed[1][2]) << 10) | //
        (B(reg_usage.regs_passed[1][3]) << 11) | //
        (B(reg_usage.has_env) << 12);
}

// Assigns the argument to a register if there's any left according to the
// calling convention, and updates the regs_passed bools. Otherwise marks the
// value as needing stack space to be passed.
fn assign_register_or_stack(reg_usage: *RegisterUsage, arg: *ArgClass, is_float: bool, by_copy: bool) void {
    if (reg_usage.num_regs_passed == 4) {
        arg.style = if (by_copy) .APS_CopyAndPointerOnStack else .APS_InlineOnStack;
    } else {
        reg_usage.regs_passed[@intFromBool(is_float)][@intCast(reg_usage.num_regs_passed)] = true;
        reg_usage.num_regs_passed += 1;
        arg.style = if (by_copy) .APS_CopyAndPointerInRegister else .APS_Register;
    }
    reg_usage.num_named_args_passed += 1;
}

fn type_is_by_copy(@"type": *const Typ) bool {
    // Note that only these sizes are passed by register, even though e.g. a
    // 5 byte struct would "fit", it still is passed by copy-and-pointer.
    return @"type".isdark != 0 or (@"type".size != 1 and @"type".size != 2 and
        @"type".size != 4 and @"type".size != 8);
}

// This function is used for both arguments and parameters.
// instrs should be the Oarg instructions of a call, or the Opar instructions
// at the start of the function.
fn classify_arguments(reg_usage: *RegisterUsage, instrs: []const Ins, arg_classes: []ArgClass, env: *Ref) void {
    // For each argument, determine how it will be passed (int, float, stack)
    // and update the `reg_usage` counts. Additionally, fill out arg_classes for
    // each argument.
    for (instrs, arg_classes) |*instr, *arg| {
        switch (instr.op) {
            Oarg, Opar => {
                assign_register_or_stack(reg_usage, arg, KBASE(instr.cls) != 0, false);
                arg.cls = @intCast(instr.cls);
                arg.@"align" = 3;
                arg.size = 8;
            },
            Oargc, Oparc => {
                const typ_index = instr.arg[0].val;
                const @"type" = &all.typ[typ_index];
                const by_copy = type_is_by_copy(@"type");
                assign_register_or_stack(reg_usage, arg, false, by_copy);
                arg.cls = Kl;
                if (!by_copy and @"type".size <= 4) {
                    arg.cls = Kw;
                }
                arg.@"align" = 3;
                arg.size = @intCast(@"type".size);
            },
            Oarge => {
                env.* = instr.arg[0];
                arg.style = .APS_EnvTag;
                reg_usage.has_env = true;
            },
            Opare => {
                env.* = instr.to;
                arg.style = .APS_EnvTag;
                reg_usage.has_env = true;
            },
            Oargv => {
                reg_usage.is_varargs_call = true;
                arg.style = .APS_VarargsTag;
            },
            else => {},
        }
    }

    if (reg_usage.has_env and reg_usage.is_varargs_call) {
        die("can't use env with varargs", .{});
    }

    // During a varargs call, float arguments have to be duplicated to their
    // associated integer register, so mark them as in-use too.
    if (reg_usage.is_varargs_call) {
        var i: usize = 0;
        while (i < 4) : (i += 1) {
            if (reg_usage.regs_passed[1][i]) {
                reg_usage.regs_passed[0][i] = true;
            }
        }
    }
}

fn is_integer_type(ty: i32) bool {
    assert(ty >= 0 and ty < 4); // expecting Kw Kl Ks Kd
    return KBASE(ty) == 0;
}

fn register_for_arg(cls: i32, counter: i32) Ref {
    assert(counter < 4);
    if (is_integer_type(cls)) {
        return TMP(amd64_winabi_rsave[@intCast(counter)]);
    } else {
        return TMP(XMM0 + counter);
    }
}

fn lower_call(func: *Fn, block: *Blk, call_idx: uint, pextra_alloc: *?*ExtraAlloc) uint {
    // Call arguments are instructions. Walk through them to find the start of
    // the call+args that we need to process (and return its index, the number
    // of instructions before it, for continuing processing).
    const call_instr = &block.ins[call_idx];
    var earliest_arg = call_idx;
    while (earliest_arg > 0 and isarg(block.ins[earliest_arg - 1].op))
        earliest_arg -= 1;
    const args = block.ins[earliest_arg..call_idx];

    // Don't need an ArgClass for the call itself, so one less than the total
    // number of instructions we're dealing with.
    const num_args: uint = @intCast(args.len);
    const arg_classes = palloc(ArgClass, num_args)[0..num_args];

    var reg_usage = std.mem.zeroes(RegisterUsage);
    var ret_arg_class = std.mem.zeroes(ArgClass);

    // Ocall's two arguments are the the function to be called in 0, and, if the
    // the function returns a non-basic type, then arg[1] is a reference to the
    // type of the return. req checks if Refs are equal; `R` is 0.
    const il_has_struct_return = !req(call_instr.arg[1], R);
    var is_struct_return = false;
    if (il_has_struct_return) {
        const ret_type = &all.typ[call_instr.arg[1].val];
        is_struct_return = type_is_by_copy(ret_type);
        if (is_struct_return) {
            assign_register_or_stack(&reg_usage, &ret_arg_class, false, true);
        }
        ret_arg_class.size = @intCast(ret_type.size);
    }
    var env = R;
    classify_arguments(&reg_usage, args, arg_classes, &env);

    // We now know which arguments are on the stack and which are in registers, so
    // we can allocate the correct amount of space to stash the stack-located ones
    // into.
    var stack_usage: uint = 0;
    var i: uint = 0;
    while (i < num_args) : (i += 1) {
        const arg = &arg_classes[i];
        // stack_usage only accounts for pushes that are for values that don't have
        // enough registers. Large struct copies are alloca'd separately, and then
        // only have (potentially) 8 bytes to add to stack_usage here.
        if (arg.style == .APS_InlineOnStack) {
            if (arg.@"align" > 4) {
                err("win abi cannot pass alignments > 16", .{});
            }
            stack_usage += arg.size;
        } else if (arg.style == .APS_CopyAndPointerOnStack) {
            stack_usage += 8;
        }
    }
    stack_usage = ALIGN_UP(stack_usage, 16);

    // Note that here we're logically 'after' the call (due to emitting
    // instructions in reverse order), so we're doing a negative stack
    // allocation to clean up after the call.
    const stack_size_ref = getcon(-@as(i64, stack_usage + SHADOW_SPACE_SIZE), func);
    emit(Osalloc, Kl, R, stack_size_ref, R);

    var return_pad: ?*ExtraAlloc = null;
    if (is_struct_return) {
        return_pad = pnew(ExtraAlloc);
        const ret_pad_ref = newtmp("abi.ret_pad", Kl, func);
        return_pad.?.instr = INS(Oalloc8, Kl, ret_pad_ref, getcon(ret_arg_class.size, func), R);
        return_pad.?.link = pextra_alloc.*;
        pextra_alloc.* = return_pad;
        reg_usage.rax_returned = true;
        emit(Ocopy, call_instr.cls, call_instr.to, TMP(RAX), R);
    } else {
        if (il_has_struct_return) {
            // In the case that at the IL level, a struct return was specified, but as
            // far as the calling convention is concerned it's not actually by
            // pointer, we need to store the return value into an alloca because
            // subsequent IL will still be treating the function return as a pointer.
            const return_copy = pnew(ExtraAlloc);
            return_copy.instr = INS(Oalloc8, Kl, call_instr.to, getcon(8, func), R);
            return_copy.link = pextra_alloc.*;
            pextra_alloc.* = return_copy;
            const copy = newtmp("abi.copy", Kl, func);
            emit(Ostorel, 0, R, copy, call_instr.to);
            emit(Ocopy, Kl, copy, TMP(RAX), R);
            reg_usage.rax_returned = true;
        } else if (is_integer_type(@intCast(call_instr.cls))) {
            // Only a basic type returned from the call, integer.
            emit(Ocopy, call_instr.cls, call_instr.to, TMP(RAX), R);
            reg_usage.rax_returned = true;
        } else {
            // Basic type, floating point.
            emit(Ocopy, call_instr.cls, call_instr.to, TMP(XMM0), R);
            reg_usage.xmm0_returned = true;
        }
    }

    // Emit the actual call instruction. There's no 'to' value by this point
    // because we've lowered it into register manipulation (that's the `R`),
    // arg[0] of the call is the function, and arg[1] is register usage is
    // documented as above (copied from SysV).
    emit(Ocall, call_instr.cls, R, call_instr.arg[0], CALL(register_usage_to_call_arg_value(reg_usage)));

    if (!req(R, env)) {
        // If there's an env arg to be passed, it gets stashed in RAX.
        emit(Ocopy, Kl, TMP(RAX), env, R);
    }

    if (reg_usage.is_varargs_call) {
        // Any float arguments need to be duplicated to integer registers. This is
        // required by the calling convention so that dumping to shadow space can be
        // done without a prototype and for varargs.
        if (reg_usage.regs_passed[1][0]) emit(Ocast, Kl, TMP(RCX), TMP(XMM0), R);
        if (reg_usage.regs_passed[1][1]) emit(Ocast, Kl, TMP(RDX), TMP(XMM1), R);
        if (reg_usage.regs_passed[1][2]) emit(Ocast, Kl, TMP(R8), TMP(XMM2), R);
        if (reg_usage.regs_passed[1][3]) emit(Ocast, Kl, TMP(R9), TMP(XMM3), R);
    }

    var reg_counter: i32 = 0;
    if (is_struct_return) {
        const first_reg = register_for_arg(Kl, reg_counter);
        reg_counter += 1;
        emit(Ocopy, Kl, first_reg, return_pad.?.instr.to, R);
    }

    // This is where we actually do the load of values into registers or into
    // stack slots.
    const arg_stack_slots = newtmp("abi.args", Kl, func);
    var slot_offset: uint = SHADOW_SPACE_SIZE;
    for (args, arg_classes) |*instr, *arg| {
        switch (arg.style) {
            .APS_Register => {
                const into = register_for_arg(arg.cls, reg_counter);
                reg_counter += 1;
                if (instr.op == Oargc) {
                    // If this is a small struct being passed by value. The value in the
                    // instruction in this case is a pointer, but it needs to be loaded
                    // into the register.
                    emit(Oload, arg.cls, into, instr.arg[1], R);
                } else {
                    // Otherwise, a normal value passed in a register.
                    emit(Ocopy, instr.cls, into, instr.arg[0], R);
                }
            },
            .APS_InlineOnStack => {
                const slot = newtmp("abi.off", Kl, func);
                if (instr.op == Oargc) {
                    // This is a small struct, so it's not passed by copy, but the
                    // instruction is a pointer. So we need to copy it into the stack
                    // slot. (And, remember that these are emitted backwards, so store,
                    // then load.)
                    const smalltmp = newtmp("abi.smalltmp", arg.cls, func);
                    emit(Ostorel, 0, R, smalltmp, slot);
                    emit(Oload, arg.cls, smalltmp, instr.arg[1], R);
                } else {
                    // Stash the value into the stack slot.
                    emit(Ostorel, 0, R, instr.arg[0], slot);
                }
                emit(Oadd, Kl, slot, arg_stack_slots, getcon(slot_offset, func));
                slot_offset += arg.size;
            },
            .APS_CopyAndPointerInRegister, .APS_CopyAndPointerOnStack => {
                // Alloca a space to copy into, and blit the value from the instr to the
                // copied location.
                const arg_copy = pnew(ExtraAlloc);
                const copy_ref = newtmp("abi.copy", Kl, func);
                arg_copy.instr = INS(Oalloc8, Kl, copy_ref, getcon(arg.size, func), R);
                arg_copy.link = pextra_alloc.*;
                pextra_alloc.* = arg_copy;
                emit(Oblit1, 0, R, INT(arg.size), R);
                emit(Oblit0, 0, R, instr.arg[1], copy_ref);

                // Now load the pointer into the correct register or stack slot.
                if (arg.style == .APS_CopyAndPointerInRegister) {
                    const into = register_for_arg(arg.cls, reg_counter);
                    reg_counter += 1;
                    emit(Ocopy, Kl, into, copy_ref, R);
                } else {
                    assert(arg.style == .APS_CopyAndPointerOnStack);
                    const slot = newtmp("abi.off", Kl, func);
                    emit(Ostorel, 0, R, copy_ref, slot);
                    emit(Oadd, Kl, slot, arg_stack_slots, getcon(slot_offset, func));
                    slot_offset += 8;
                }
            },
            .APS_EnvTag, .APS_VarargsTag => {
                // Nothing to do here, see right before the call for reg dupe.
            },
            .APS_Invalid => die("unreachable", .{}),
        }
    }

    if (stack_usage != 0) {
        // The last (first in call order) thing we do is allocate the the stack
        // space we're going to fill with temporaries.
        emit(Osalloc, Kl, arg_stack_slots, getcon(stack_usage + SHADOW_SPACE_SIZE, func), R);
    } else {
        // When there's no usage for temporaries, we can add this into the other
        // alloca, but otherwise emit it separately (not storing into a reference)
        // so that it doesn't get removed later for being useless.
        emit(Osalloc, Kl, R, getcon(SHADOW_SPACE_SIZE, func), R);
    }

    return earliest_arg;
}

fn lower_block_return(func: *Fn, block: *Blk) void {
    const jmp_type: i32 = block.jmp.type.int();

    if (!isret(jmp_type) or jmp_type == Jret0.int()) {
        return;
    }

    // Save the argument, and set the block to be a void return because once it's
    // lowered it's handled by the the register/stack manipulation.
    const ret_arg = block.jmp.arg;
    block.jmp.type = Jret0;

    var reg_usage = std.mem.zeroes(RegisterUsage);

    if (jmp_type == Jretc.int()) {
        const @"type" = &all.typ[@intCast(func.retty)];
        if (type_is_by_copy(@"type")) {
            assert(rtype(func.retr) == RTmp);
            emit(Ocopy, Kl, TMP(RAX), func.retr, R);
            emit(Oblit1, 0, R, INT(@"type".size), R);
            emit(Oblit0, 0, R, ret_arg, func.retr);
        } else {
            emit(Oload, Kl, TMP(RAX), ret_arg, R);
        }
        reg_usage.rax_returned = true;
    } else {
        const k = jmp_type - Jretw.int();
        if (is_integer_type(k)) {
            emit(Ocopy, k, TMP(RAX), ret_arg, R);
            reg_usage.rax_returned = true;
        } else {
            emit(Ocopy, k, TMP(XMM0), ret_arg, R);
            reg_usage.xmm0_returned = true;
        }
    }
    block.jmp.arg = CALL(register_usage_to_call_arg_value(reg_usage));
}

fn lower_vastart(func: *Fn, param_reg_usage: *RegisterUsage, valist: Ref) void {
    assert(func.vararg != 0);
    // In varargs functions:
    // 1. the int registers are already dumped to the shadow stack space;
    // 2. any parameters passed in floating point registers have
    //    been duplicated to the integer registers
    // 3. we ensure (later) that for varargs functions we're always using an rbp
    //    frame pointer.
    // So, the ... argument is just indexed past rbp by the number of named values
    // that were actually passed.

    const offset = newtmp("abi.vastart", Kl, func);
    emit(Ostorel, 0, R, offset, valist);

    // *8 for sizeof(u64), +16 because the return address and rbp have been pushed
    // by the time we get to the body of the function.
    emit(Oadd, Kl, offset, TMP(RBP), getcon(param_reg_usage.num_named_args_passed * 8 + 16, func));
}

fn lower_vaarg(func: *Fn, vaarg_instr: *Ins) void {
    // va_list is just a void** on winx64, so load the pointer, then load the
    // argument from that pointer, then increment the pointer to the next arg.
    // (All emitted backwards as usual.)
    const inc = newtmp("abi.vaarg.inc", Kl, func);
    const ptr = newtmp("abi.vaarg.ptr", Kl, func);
    emit(Ostorel, 0, R, inc, vaarg_instr.arg[0]);
    emit(Oadd, Kl, inc, ptr, getcon(8, func));
    emit(Oload, vaarg_instr.cls, vaarg_instr.to, ptr, R);
    emit(Oload, Kl, ptr, vaarg_instr.arg[0], R);
}

fn lower_args_for_block(func: *Fn, block: *Blk, param_reg_usage: *RegisterUsage, pextra_alloc: *?*ExtraAlloc) void {
    // global temporary buffer used by emit. Reset to the end, and predecremented
    // when adding to it.
    all.curi = all.insbEnd();

    lower_block_return(func, block);

    // Work backwards through the instructions, either copying them unchanged,
    // or modifying as necessary. n is the number of instructions left.
    var n = block.nins;
    while (n > 0) {
        const instr = &block.ins[n - 1];
        switch (instr.op) {
            Ocall => n = lower_call(func, block, n - 1, pextra_alloc),
            Ovastart => {
                lower_vastart(func, param_reg_usage, instr.arg[0]);
                n -= 1;
            },
            Ovaarg => {
                lower_vaarg(func, instr);
                n -= 1;
            },
            Oarg, Oargc => die("unreachable", .{}),
            else => {
                emiti(instr.*);
                n -= 1;
            },
        }
    }

    // This it the start block, which is processed last. Add any allocas that
    // other blocks needed.
    const is_start_block = block == func.start;
    if (is_start_block) {
        var ea_it: ?*ExtraAlloc = pextra_alloc.*;
        while (ea_it) |ea| : (ea_it = ea.link) {
            emiti(ea.instr);
        }
    }

    // emit/emiti add instructions from the end to the beginning of the temporary
    // global buffer. dup the final version into the final block storage.
    block.nins = @intCast(all.insbTail());
    idup(block, all.curi, block.nins);
}

/// returns the number of Opar instructions at the start of start_block
fn find_end_of_func_parameters(start_block: *Blk) uint {
    var i: uint = 0;
    while (i < start_block.nins and ispar(start_block.ins[i].op))
        i += 1;
    return i;
}

// Copy from registers/stack into values.
fn lower_func_parameters(func: *Fn) RegisterUsage {
    const start_block = func.start.?;
    const num_params = find_end_of_func_parameters(start_block);
    const params = start_block.ins[0..num_params];
    const arg_classes = palloc(ArgClass, num_params)[0..num_params];
    var arg_ret = std.mem.zeroes(ArgClass);

    // global temporary buffer used by emit. Reset to the end, and predecremented
    // when adding to it.
    all.curi = all.insbEnd();

    var reg_counter: i32 = 0;
    var reg_usage = std.mem.zeroes(RegisterUsage);
    if (func.retty >= 0) {
        const by_copy = type_is_by_copy(&all.typ[@intCast(func.retty)]);
        if (by_copy) {
            assign_register_or_stack(&reg_usage, &arg_ret, false, by_copy);
            const ret_ref = newtmp("abi.ret", Kl, func);
            emit(Ocopy, Kl, ret_ref, TMP(RCX), R);
            func.retr = ret_ref;
            reg_counter += 1;
        }
    }
    var env = R;
    classify_arguments(&reg_usage, params, arg_classes, &env);
    func.reg = amd64_winabi_argregs(CALL(register_usage_to_call_arg_value(reg_usage)), null);

    // Copy from the registers or stack slots into the named parameters. Depending
    // on how they're passed, they either need to be copied or loaded.
    var slot_offset: i32 = SHADOW_SPACE_SIZE / 4 + 4;
    for (params, arg_classes) |*instr, *arg| {
        switch (arg.style) {
            .APS_Register => {
                const from = register_for_arg(arg.cls, reg_counter);
                reg_counter += 1;
                // If it's a struct at the IL level, we need to copy the register into
                // an alloca so we have something to point at (same for InlineOnStack).
                if (instr.op == Oparc) {
                    arg.ref = newtmp("abi", Kl, func);
                    emit(Ostorel, 0, R, arg.ref, instr.to);
                    emit(Ocopy, instr.cls, arg.ref, from, R);
                    emit(Oalloc8, Kl, instr.to, getcon(arg.size, func), R);
                } else {
                    emit(Ocopy, instr.cls, instr.to, from, R);
                }
            },
            .APS_InlineOnStack => {
                if (instr.op == Oparc) {
                    arg.ref = newtmp("abi", Kl, func);
                    emit(Ostorel, 0, R, arg.ref, instr.to);
                    emit(Ocopy, instr.cls, arg.ref, SLOT(-slot_offset), R);
                    emit(Oalloc8, Kl, instr.to, getcon(arg.size, func), R);
                } else {
                    emit(Ocopy, Kl, instr.to, SLOT(-slot_offset), R);
                }
                slot_offset += 2;
            },
            .APS_CopyAndPointerOnStack => {
                emit(Oload, Kl, instr.to, SLOT(-slot_offset), R);
                slot_offset += 2;
            },
            .APS_CopyAndPointerInRegister => {
                // Because this has to be a copy (that we own), it is sufficient to just
                // copy the register to the target.
                const from = register_for_arg(Kl, reg_counter);
                reg_counter += 1;
                emit(Ocopy, Kl, instr.to, from, R);
            },
            .APS_EnvTag => {},
            .APS_VarargsTag, .APS_Invalid => die("unreachable", .{}),
        }
    }

    // If there was an `env`, it was passed in RAX, so copy it into the env ref.
    if (!req(R, env)) {
        emit(Ocopy, Kl, env, TMP(RAX), R);
    }

    const num_created_instrs: uint = @intCast(all.insbTail());
    const num_other_after_instrs: uint = @intCast(start_block.nins - num_params);
    const new_total_instrs = num_other_after_instrs + num_created_instrs;
    const new_instrs = vnewT(Ins, new_total_instrs, PFn);
    const instr_p = icpy(new_instrs, all.curi, num_created_instrs);
    _ = icpy(instr_p, start_block.ins + num_params, num_other_after_instrs);
    start_block.nins = new_total_instrs;
    start_block.ins = new_instrs;

    return reg_usage;
}

// The main job of this function is to lower generic instructions into the
// specific details of how arguments are passed, and parameters are
// interpreted for win x64. A useful reference is
// https://learn.microsoft.com/en-us/cpp/build/x64-calling-convention .
//
// (see winabi.c for the full description of differences from SysV)
pub fn amd64_winabi_abi(func: *Fn) void {
    // The first thing to do is lower incoming parameters to this function.
    var param_reg_usage = lower_func_parameters(func);

    // This is the second larger part of the job. We walk all blocks, and rewrite
    // instructions returns, calls, and handling of varargs into their win x64
    // specific versions. Any other instructions are just passed through unchanged
    // by using `emiti`.

    // Skip over the entry block, and do it at the end so that our later
    // modifications can add allocations to the start block. In particular, we
    // need to add stack allocas for copies when structs are passed or returned by
    // value.
    var extra_alloc: ?*ExtraAlloc = null;
    var block_it: ?*Blk = func.start.?.link;
    while (block_it) |block| : (block_it = block.link) {
        lower_args_for_block(func, block, &param_reg_usage, &extra_alloc);
    }
    lower_args_for_block(func, func.start.?, &param_reg_usage, &extra_alloc);

    if (all.debug['A'] != 0) {
        dprint("\n> After ABI lowering:\n", .{});
        printfn(func, all.dbg) catch {};
    }
}
