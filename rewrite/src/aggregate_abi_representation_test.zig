const std = @import("std");
const t = std.testing;
const ir = @import("ir.zig");
const Module = @import("module.zig").Module;
const frontend = @import("frontend.zig");
const validation = @import("module_validation.zig");
const amd64 = @import("amd64.zig");
const interpreter = @import("interpreter.zig");
const metadata = @embedFile("fixtures/aggregate_abi_representation_metadata.ssa");
const bad_id: @import("record_declaration.zig").Id = @fromBackingInt(std.math.maxInt(u32));
fn parse(allocator: std.mem.Allocator, text: []const u8) !Module {
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    return frontend.parse(allocator, .{ .name = "aggregate_abi_representation", .text = text }, &diagnostic);
}
fn record(ty: ir.AbiDescriptor, expected: u32) !void {
    try t.expect(ty == .record);
    try t.expectEqual(expected, @backingInt(ty.record));
}
fn scalar(ty: ir.AbiDescriptor, expected: ir.AbiType) !void {
    try t.expect(ty == .scalar);
    try t.expectEqual(expected, ty.scalar);
}
fn allConsumersReject(module: *Module, expected: anyerror) !void {
    try t.expectError(expected, validation.validate(t.allocator, module));
    try t.expectError(expected, amd64.emit(t.allocator, module));
    try t.expectError(expected, interpreter.evaluateModule(t.allocator, module, @fromBackingInt(@as(u32, 0)), &.{}, .{}));
}

test "aggregate_abi_representation independent eight-annotation coherence table and nominal long carrier" {
    // Hand-authored language table; production carrier/subword accessors do NOT
    // derive the expected relation. Narrow annotations remain distinct from w.
    const abis = [_]ir.AbiType{ .word, .long, .single, .double, .signed_byte, .unsigned_byte, .signed_half, .unsigned_half };
    const widths = [_]ir.ScalarType{ .word, .long, .single, .double, .word, .word, .word, .word };
    const small = [_]?ir.SubwordType{ null, null, null, null, .signed_byte, .unsigned_byte, .signed_half, .unsigned_half };
    for (abis, widths, small, 0..) |abi, width, narrow, index| {
        try scalar((try ir.checkedAbiDescriptor(width, narrow, null)).?, abi);
        for (abis, 0..) |explicit, other| {
            const descriptor: ir.AbiDescriptor = .{ .scalar = explicit };
            if (index == other) try scalar((try ir.checkedAbiDescriptor(width, narrow, descriptor)).?, abi) else try t.expectError(error.TypeMismatch, ir.checkedAbiDescriptor(width, narrow, descriptor));
        }
        const descriptor: ir.AbiDescriptor = .{ .record = bad_id };
        if (index == 1) try record((try ir.checkedAbiDescriptor(width, narrow, descriptor)).?, std.math.maxInt(u32)) else try t.expectError(error.TypeMismatch, ir.checkedAbiDescriptor(width, narrow, descriptor));
    }
    try t.expect((try ir.checkedAbiDescriptor(null, null, null)) == null);
    try t.expectError(error.TypeMismatch, ir.checkedAbiDescriptor(null, null, .{ .record = bad_id }));
    try t.expectError(error.TypeMismatch, ir.checkedAbiDescriptor(null, null, .{ .scalar = .long }));
    try t.expectError(error.TypeMismatch, ir.checkedAbiDescriptor(.long, .signed_byte, null));
}

test "aggregate_abi_representation parser keeps ABI identity in every slot and accepts generic huge overalign metadata" {
    const source = try t.allocator.dupe(u8, metadata);
    var module = parse(t.allocator, source) catch |err| {
        t.allocator.free(source);
        return err;
    };
    defer module.deinit();
    @memset(source, 0xa5);
    t.allocator.free(source);
    try validation.validate(t.allocator, &module);
    try t.expectEqual(@as(usize, 6), module.types.items.len);
    try t.expectEqual(@as(u64, 1), module.types.items[0].size);
    try t.expectEqual(@as(u8, 64), module.types.items[2].alignment);
    try t.expectEqual(std.math.maxInt(u64), module.types.items[5].size);
    const identity = module.functions.items[0];
    try record((try identity.returnAbi()).?, 0);
    try record(try identity.parameterAbi(identity.parameters.items[0]), 0);
    try t.expectEqual(ir.ScalarType.long, identity.return_type.?);
    const env = module.functions.items[1];
    try scalar(try env.parameterAbi(env.environment.?), .long);
    try record(try env.parameterAbi(env.ordinaryParameters()[0]), 2);
    try record((try env.returnAbi()).?, 2);
    const variadic = module.functions.items[2];
    try t.expect(variadic.variadic);
    try record(try variadic.parameterAbi(variadic.parameters.items[0]), 5);
    const caller = module.functions.items[3];
    const call = caller.blocks.items[0].instructions.items[0].call;
    try record(call.result_descriptor.?, 0); // inspect storage, not only accessors
    try record(call.arguments[0].descriptor.?, 0);
    try t.expectEqual(ir.ScalarType.long, caller.values.items[@backingInt(call.result.?)].scalar_type);
    try record((try call.resultAbi(caller)).?, 0);
    const tail = module.functions.items[4].blocks.items[0].instructions.items[0].call;
    try t.expectEqual(@as(?usize, 1), tail.variadic_start);
    try record(tail.arguments[0].descriptor.?, 2);
    try record(tail.arguments[1].descriptor.?, 0);
    const env_call = module.functions.items[5].blocks.items[0].instructions.items[0].call;
    try t.expect(env_call.environment != null);
    try record(env_call.arguments[0].descriptor.?, 0);
    const indirect = module.functions.items[6].blocks.items[0].instructions.items[0].call;
    try t.expect(indirect.callee == .address);
    try record(indirect.arguments[0].descriptor.?, 5);
    try record((try module.functions.items[7].returnAbi()).?, 5);
    for (module.functions.items) |function| _ = try @import("optimize.zig").foldIntegerConstants(t.allocator, function);
    try validation.validate(t.allocator, &module);
    try record(caller.blocks.items[0].instructions.items[0].call.result_descriptor.?, 0);
}

test "aggregate_abi_representation all record native uses refuse before frame planning in all eight modes" {
    var module = try parse(t.allocator, metadata);
    defer module.deinit();
    for (0..8) |mask| {
        if (mask & 1 != 0) for (module.functions.items) |f| {
            _ = try @import("optimize.zig").foldIntegerConstants(t.allocator, f);
        };
        try t.expectError(error.UnsupportedAggregateAbi, amd64.emitWithOptions(t.allocator, &module, .{ .reuse_stack_homes = mask & 2 != 0, .callee_saved_homes = mask & 4 != 0 }));
    }
    // A valid record signature with enough scalar homes to exceed64KiB must
    // still refuse aggregate ABI BEFORE any frame/home planning attempt.
    var large = Module.init(t.allocator);
    defer large.deinit();
    const ty = try large.addRecord("T", null, &.{.{ .element = .{ .scalar = .byte } }});
    const id = try large.addFunctionDescriptor("large", .{ .record = ty });
    const f = large.getFunction(id).?;
    for (0..8193) |_| _ = try f.addParameter(.long);
    const b = try f.addBlock(null);
    try f.terminate(b, .{ .return_value = .{ .constant = .{ .long = 0 } } });
    try t.expectError(error.UnsupportedAggregateAbi, amd64.emit(t.allocator, &large));
}

test "aggregate_abi_representation root guards precede depth space and argument binding after validation" {
    var module = try parse(t.allocator, metadata);
    defer module.deinit();
    const options: interpreter.Options = .{ .max_call_depth = 0, .stack_memory = .{ .base = 0 }, .root_variadic_arguments = &.{.{ .word = 1 }} };
    for ([_]u32{ 0, 1, 2, 7 }) |entry| {
        try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluate(t.allocator, module.functions.items[entry], &.{}, options));
        try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluateModule(t.allocator, &module, @fromBackingInt(entry), &.{.{ .word = 1 }}, options));
    }
    try t.expectError(error.InvalidFunction, interpreter.evaluateModule(t.allocator, &module, @fromBackingInt(std.math.maxInt(u32)), &.{}, options));
    module.functions.items[0].return_descriptor = .{ .record = bad_id };
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluate(t.allocator, module.functions.items[0], &.{}, options));
    try allConsumersReject(&module, error.InvalidAggregateType);
}

test "aggregate_abi_representation reached call step wins then aggregate guard wins over missing owner and address resolution" {
    var module = try parse(t.allocator, "type :T = { b }\nfunction $f() {\n@e\ncall $external(:T $unresolved)\nret\n}");
    defer module.deinit();
    const f = module.functions.items[0];
    try t.expectError(error.StepLimitExceeded, interpreter.evaluate(t.allocator, f, &.{}, .{ .max_steps = 0 }));
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluate(t.allocator, f, &.{}, .{ .max_steps = 1 }));
    try t.expectError(error.StepLimitExceeded, interpreter.evaluateModule(t.allocator, &module, @fromBackingInt(@as(u32, 0)), &.{}, .{ .max_steps = 0 }));
    try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluateModule(t.allocator, &module, @fromBackingInt(@as(u32, 0)), &.{}, .{ .max_steps = 1, .max_call_depth = 1, .stack_memory = .{}, .global_memory = .{}, .internal_variadic_calls = true, .consume_vaargs = true }));
}

test "aggregate_abi_representation unused call IDs resolve but unreachable execution is not invented" {
    var module = try parse(t.allocator, "type :T = { b }\nfunction w $f() {\n@e\nret 42\n@dead\ncall $external(:T 0)\nret 0\n}");
    defer module.deinit();
    try t.expectEqual(@as(u32, 42), (try interpreter.evaluate(t.allocator, module.functions.items[0], &.{}, .{})).?.word);
    try t.expectEqual(@as(u32, 42), (try interpreter.evaluateModule(t.allocator, &module, @fromBackingInt(@as(u32, 0)), &.{}, .{})).?.word);
    try t.expectError(error.UnsupportedAggregateAbi, amd64.emit(t.allocator, &module));
    const arguments = @constCast(module.functions.items[0].blocks.items[1].instructions.items[0].call.arguments);
    arguments[0].descriptor = .{ .record = bad_id };
    try allConsumersReject(&module, error.InvalidAggregateType);
}

test "aggregate_abi_representation complete ID pass precedes nominal signature comparison across every call category" {
    var module = try parse(t.allocator, metadata);
    defer module.deinit();
    const mismatch = &module.functions.items[3].blocks.items[0].instructions.items[0].call;
    @constCast(mismatch.arguments)[0].descriptor = .{ .record = @fromBackingInt(@as(u32, 1)) }; // Twin has same1-byte layout, NOT Tiny identity.
    try t.expectError(error.CallSignatureMismatch, validation.validate(t.allocator, &module));
    for (0..6) |slot| {
        const identity = module.functions.items[0];
        const old_result = identity.return_descriptor;
        const old_parameter = identity.values.items[0].parameter_descriptor;
        const external = &module.functions.items[4].blocks.items[0].instructions.items[0].call;
        const indirect = &module.functions.items[6].blocks.items[0].instructions.items[0].call;
        const old_external0 = external.arguments[0];
        const old_tail = external.arguments[1];
        const old_indirect = indirect.arguments[0];
        const old_call_result = mismatch.result_descriptor;
        defer {
            identity.return_descriptor = old_result;
            identity.values.items[0].parameter_descriptor = old_parameter;
            @constCast(external.arguments)[0] = old_external0;
            @constCast(external.arguments)[1] = old_tail;
            @constCast(indirect.arguments)[0] = old_indirect;
            mismatch.result_descriptor = old_call_result;
        }
        switch (slot) {
            0 => identity.return_descriptor = .{ .record = bad_id },
            1 => identity.values.items[0].parameter_descriptor = .{ .record = bad_id },
            2 => @constCast(external.arguments)[0].descriptor = .{ .record = bad_id },
            3 => @constCast(external.arguments)[1].descriptor = .{ .record = bad_id },
            4 => @constCast(indirect.arguments)[0].descriptor = .{ .record = bad_id },
            5 => mismatch.result_descriptor = .{ .record = bad_id },
            else => unreachable,
        }
        try allConsumersReject(&module, error.InvalidAggregateType);
    }
    // Same width is not identity either: old scalar long annotation cannot
    // satisfy a known record signature simply by erasing its record tag.
    @constCast(mismatch.arguments)[0].descriptor = .{ .scalar = .long };
    try t.expectError(error.CallSignatureMismatch, validation.validate(t.allocator, &module));
}

test "aggregate_abi_representation every public carrier annotation contradiction and hidden environment tag is checked" {
    var module = try parse(t.allocator, metadata);
    defer module.deinit();
    for (0..9) |mutation| {
        const identity = module.functions.items[0];
        const caller = module.functions.items[3];
        const env = module.functions.items[1];
        const external = &module.functions.items[4].blocks.items[0].instructions.items[0].call;
        const old_return = identity.return_descriptor;
        const old_parameter = identity.values.items[0];
        const old_argument = external.arguments[0];
        const old_external_result = external.result_descriptor;
        const old_value_descriptor = caller.values.items[0].parameter_descriptor;
        const old_result = caller.blocks.items[0].instructions.items[0].call.result_descriptor;
        const old_env = env.values.items[0].parameter_descriptor;
        defer {
            identity.return_descriptor = old_return;
            identity.values.items[0] = old_parameter;
            @constCast(external.arguments)[0] = old_argument;
            external.result_descriptor = old_external_result;
            caller.values.items[0].parameter_descriptor = old_value_descriptor;
            caller.blocks.items[0].instructions.items[0].call.result_descriptor = old_result;
            env.values.items[0].parameter_descriptor = old_env;
        }
        switch (mutation) {
            0 => identity.return_descriptor = .{ .scalar = .word },
            1 => identity.values.items[0].parameter_descriptor = .{ .scalar = .word },
            2 => identity.values.items[0].scalar_type = .word,
            3 => @constCast(external.arguments)[0].subword_type = .signed_byte,
            4 => @constCast(external.arguments)[0].descriptor = .{ .scalar = .word },
            5 => external.result_descriptor = .{ .record = @fromBackingInt(@as(u32, 0)) }, // void call
            6 => caller.values.items[0].parameter_descriptor = .{ .record = @fromBackingInt(@as(u32, 0)) }, // instruction, NOT parameter
            7 => caller.blocks.items[0].instructions.items[0].call.result_descriptor = .{ .scalar = .word },
            8 => env.values.items[0].parameter_descriptor = .{ .record = @fromBackingInt(@as(u32, 0)) }, // long carrier is insufficient
            else => unreachable,
        }
        try allConsumersReject(&module, if (mutation == 8) error.InvalidEnvironment else error.TypeMismatch);
    }
    try validation.validate(t.allocator, &module);
}

test "aggregate_abi_representation dual result options require exact scalar equality and never publish contradictions" {
    for ([_]ir.AbiDescriptor{ .{ .scalar = .long }, .{ .scalar = .word }, .{ .record = @fromBackingInt(@as(u32, 0)) } }, 0..) |descriptor, index| {
        var f = ir.Function.init(t.allocator, @fromBackingInt(@as(u32, 0)), null);
        defer f.deinit();
        const b = try f.addBlock(null);
        const result = try f.declareValue(.long);
        const options: ir.CallOptions = .{ .result_abi = .long, .result_descriptor = descriptor };
        if (index == 0) {
            try f.appendCall(b, result, .{ .symbol = @fromBackingInt(@as(u32, 1)) }, &.{}, options);
            try scalar(f.blocks.items[0].instructions.items[0].call.result_descriptor.?, .long);
        } else {
            try t.expectError(error.TypeMismatch, f.appendCall(b, result, .{ .symbol = @fromBackingInt(@as(u32, 1)) }, &.{}, options));
            try t.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
            try t.expect(f.values.items[@backingInt(result)].definition == .pending);
            try f.appendCall(b, result, .{ .symbol = @fromBackingInt(@as(u32, 1)) }, &.{}, .{ .result_abi = .long });
        }
        try f.terminate(b, .{ .return_value = null });
        try f.validateStructure();
    }
}

test "aggregate_abi_representation module builders resolve IDs before mutation and copied arguments own nominal metadata" {
    var module = Module.init(t.allocator);
    defer module.deinit();
    try t.expectError(error.InvalidAggregateType, module.addFunctionDescriptor("invalid", .{ .record = bad_id }));
    try t.expectEqual(@as(usize, 0), module.functions.items.len);
    try t.expectEqual(@as(usize, 0), module.symbols.names.items.len);
    const ty = try module.addRecord("T", null, &.{.{ .element = .{ .scalar = .byte } }});
    const identity = try module.addFunctionDescriptor("identity", .{ .record = ty });
    try t.expectError(error.InvalidAggregateType, module.addParameterDescriptor(identity, .{ .record = bad_id }));
    try t.expectEqual(@as(usize, 0), module.getFunction(identity).?.parameters.items.len);
    const p = try module.addParameterDescriptor(identity, .{ .record = ty });
    const body = try module.getFunction(identity).?.addBlock(null);
    try module.getFunction(identity).?.terminate(body, .{ .return_value = .{ .value = p } });
    const caller_id = try module.addFunction("caller", null);
    const caller = module.getFunction(caller_id).?;
    const block = try caller.addBlock(null);
    const result = try caller.declareValue(.long);
    var arguments = [_]ir.CallArgument{ir.CallArgument.initDescriptor(.{ .record = ty }, .{ .constant = .{ .long = 0 } })};
    try t.expectError(error.InvalidAggregateType, module.appendCallDescriptor(caller_id, block, result, .{ .symbol = module.getFunction(identity).?.name }, &arguments, .{ .result_descriptor = .{ .record = bad_id } }));
    try t.expect(caller.values.items[@backingInt(result)].definition == .pending);
    try t.expectEqual(@as(usize, 0), caller.blocks.items[0].instructions.items.len);
    try module.appendCallDescriptor(caller_id, block, result, .{ .symbol = module.getFunction(identity).?.name }, &arguments, .{ .result_descriptor = .{ .record = ty } });
    arguments[0].descriptor = .{ .record = bad_id };
    try caller.terminate(block, .{ .return_value = null });
    try record(caller.blocks.items[0].instructions.items[0].call.arguments[0].descriptor.?, @backingInt(ty));
    try validation.validate(t.allocator, &module);
}

test "aggregate_abi_representation parameter and call allocation failures retry without advanced IDs or published definitions" {
    for ([_]bool{ false, true }) |call_mode| {
        var finished = false;
        for (0..24) |failure| {
            var failing = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
            var module = Module.init(failing.allocator());
            defer module.deinit();
            const ty = try module.addRecord("T", null, &.{.{ .element = .{ .scalar = .byte } }});
            const fid = try module.addFunctionDescriptor("f", if (call_mode) null else .{ .record = ty });
            const f = module.getFunction(fid).?;
            const b = try f.addBlock(null);
            const symbol = try module.symbols.intern("external");
            const result: ?ir.ValueId = if (call_mode) try f.declareValue(.long) else null;
            const arguments = [_]ir.CallArgument{ir.CallArgument.initDescriptor(.{ .record = ty }, .{ .constant = .{ .long = 0 } })};
            failing.fail_index = failing.alloc_index + failure;
            const attempt: anyerror!void = if (call_mode) f.appendCall(b, result, .{ .symbol = symbol }, &arguments, .{ .result_descriptor = .{ .record = ty } }) else add: {
                _ = f.addParameterDescriptor(.{ .record = ty }) catch |err| break :add err;
                break :add {};
            };
            if (attempt) |_| {
                finished = true;
            } else |err| {
                try t.expectEqual(error.OutOfMemory, err);
                try t.expectEqual(@as(usize, 0), f.parameters.items.len);
                try t.expectEqual(@as(usize, 0), f.blocks.items[0].instructions.items.len);
                if (result) |id| try t.expect(f.values.items[@backingInt(id)].definition == .pending) else try t.expectEqual(@as(usize, 0), f.values.items.len);
                failing.fail_index = std.math.maxInt(usize);
                if (call_mode) try f.appendCall(b, result, .{ .symbol = symbol }, &arguments, .{ .result_descriptor = .{ .record = ty } }) else try t.expectEqual(@as(u32, 0), @backingInt(try f.addParameterDescriptor(.{ .record = ty })));
            }
            try f.terminate(b, .{ .return_value = if (call_mode) null else .{ .value = @fromBackingInt(@as(u32, 0)) } });
            try validation.validate(t.allocator, &module);
            if (finished) break;
        }
        try t.expect(finished);
    }
}

fn exercise(allocator: std.mem.Allocator) !void {
    var module = try parse(allocator, metadata);
    defer module.deinit();
    try validation.validate(allocator, &module);
    for (module.functions.items) |f| _ = try @import("optimize.zig").foldIntegerConstants(allocator, f);
    if (amd64.emit(allocator, &module)) |unexpected| {
        allocator.free(unexpected);
        return error.ExpectedRefusal;
    } else |err| if (err != error.UnsupportedAggregateAbi) return err;
    if (interpreter.evaluate(allocator, module.functions.items[0], &.{}, .{})) |_| return error.ExpectedRefusal else |err| if (err != error.UnsupportedAggregateAbi) return err;
    if (interpreter.evaluateModule(allocator, &module, @fromBackingInt(@as(u32, 3)), &.{}, .{})) |_| return error.ExpectedRefusal else |err| if (err != error.UnsupportedAggregateAbi) return err;
    const invalid = try std.mem.concat(allocator, u8, &.{ metadata, "function $bad() {\n@e\n%x =:Tiny copy 0\nret\n}" });
    defer allocator.free(invalid);
    if (parse(allocator, invalid)) |unexpected| {
        var owned = unexpected;
        owned.deinit();
        return error.ExpectedRefusal;
    } else |err| if (err != error.InvalidInput) return err;
}

test "aggregate_abi_representation every parse validation refusal optimization and late syntax allocation failure cleans up" {
    try @import("test_support.zig").checkAllocationFailures(exercise);
}

test "aggregate_abi_representation scalar errors and approved env variadic metadata keep deterministic ordering" {
    var module = try parse(t.allocator, metadata);
    defer module.deinit();
    try validation.validate(t.allocator, &module);
    const combinations = module.functions.items[8];
    const variadic = combinations.blocks.items[0].instructions.items[0].call;
    try t.expectEqual(@as(?usize, 1), variadic.variadic_start);
    try record(variadic.arguments[0].descriptor.?, 5);
    const environment = combinations.blocks.items[0].instructions.items[1].call;
    try t.expect(environment.environment != null);
    try record(environment.result_descriptor.?, 2);
    try record(module.functions.items[9].blocks.items[0].instructions.items[0].call.result_descriptor.?, 5);
    // Scalar roots with record result-only, arg-only, env, variadic and indirect
    // call metadata all refuse at the reached instruction (never as long calls).
    for ([_]u32{ 3, 4, 5, 6, 8, 9 }) |entry| {
        const arguments: []const ir.Constant = if (entry == 6) &.{.{ .long = 0 }} else &.{};
        try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluate(t.allocator, module.functions.items[entry], arguments, .{ .max_steps = 1 }));
        try t.expectError(error.UnsupportedAggregateAbi, interpreter.evaluateModule(t.allocator, &module, @fromBackingInt(entry), arguments, .{ .max_steps = 1, .internal_variadic_calls = true, .consume_vaargs = true }));
    }
    var scalar_module = try parse(t.allocator, "function w $f() {\n@e\nret 42\n}");
    defer scalar_module.deinit();
    const f = scalar_module.functions.items[0];
    try t.expectError(error.CallDepthLimitExceeded, interpreter.evaluate(t.allocator, f, &.{}, .{ .max_call_depth = 0, .stack_memory = .{ .base = 0 } }));
    try t.expectError(error.InvalidStackRange, interpreter.evaluate(t.allocator, f, &.{}, .{ .stack_memory = .{ .base = 0 } }));
    try t.expectError(error.StepLimitExceeded, interpreter.evaluate(t.allocator, f, &.{}, .{ .max_steps = 0 }));
    var call_function = ir.Function.init(t.allocator, @fromBackingInt(@as(u32, 0)), null);
    defer call_function.deinit();
    const b = try call_function.addBlock(null);
    const result = try call_function.declareValue(.long);
    const arguments = [_]ir.CallArgument{ir.CallArgument.initDescriptor(.{ .record = bad_id }, .{ .constant = .{ .long = 0 } })};
    // Existing invalid marker/environment checks win before the new dual-option
    // contradiction. No mutation occurs in either failure case.
    const options: ir.CallOptions = .{ .result_abi = .long, .result_descriptor = .{ .record = bad_id }, .variadic_start = 2 };
    try t.expectError(error.InvalidVariadicMarker, call_function.appendCall(b, result, .{ .symbol = @fromBackingInt(@as(u32, 1)) }, &arguments, options));
    var with_env = options;
    with_env.environment = .{ .constant = .{ .long = 0 } };
    try t.expectError(error.InvalidEnvironment, call_function.appendCall(b, result, .{ .symbol = @fromBackingInt(@as(u32, 1)) }, &arguments, with_env));
    try t.expectEqual(@as(usize, 0), call_function.blocks.items[0].instructions.items.len);
    try t.expect(call_function.values.items[@backingInt(result)].definition == .pending);
}

test "aggregate_abi_representation parser still refuses aggregate noncall classes and resolves unknown type spans" {
    for ([_][]const u8{
        "type :T = { b }\nfunction $f() {\n@e\n%x =:T copy 0\nret\n}",
        "type :T = { b }\nfunction $f() {\n@e\n%x =:T add 0, 0\nret\n}",
        "type :T = { b }\nfunction $f() {\n@e\njmp @next\n@next\n%x =:T phi @e 0\nret\n}",
        "type :T = { b }\ndata $x = { :T 0 }",
        "type :T = { b }\nfunction l $f() {\n@e\nret :T\n}",
    }) |text| try t.expectError(error.InvalidInput, parse(t.allocator, text));
    const text = "function :Missing $f() {\n@e\nret 0\n}";
    var diagnostic: ?@import("source.zig").Diagnostic = null;
    try t.expectError(error.InvalidInput, frontend.parse(t.allocator, .{ .name = "unknown", .text = text }, &diagnostic));
    try t.expectEqual(@import("source.zig").Diagnostic.Code.unknown_type, diagnostic.?.code);
    try t.expectEqualStrings(":Missing", text[diagnostic.?.span.start..diagnostic.?.span.end]);
}

test "aggregate_abi_representation parsed scalar slots retain legacy authority and old body error" {
    // Scalar parser wrappers must not add a second cached authority: existing
    // public-field mutation keeps its prior structural error, not a new tag error.
    var module = try parse(t.allocator, "function w $f(w %p) {\n@e\n%r =w call $g(w %p)\nret %r\n}\nfunction w $g(w %p) {\n@e\nret %p\n}");
    defer module.deinit();
    try validation.validate(t.allocator, &module);
    for (module.functions.items) |f| {
        try t.expect(f.return_descriptor == null);
        for (f.parameters.items) |id| try t.expect(f.values.items[@backingInt(id)].parameter_descriptor == null);
    }
    const call = module.functions.items[0].blocks.items[0].instructions.items[0].call;
    try t.expect(call.result_descriptor == null);
    try t.expect(call.arguments[0].descriptor == null);
    try scalar((try call.resultAbi(module.functions.items[0])).?, .word);
    try scalar(try call.arguments[0].abi(), .word);
    module.functions.items[1].return_type = .long;
    try allConsumersReject(&module, error.InvalidReturn);
}
