//! Bounded QBE record declarations, not aggregate ABI classes or host layouts.
const std = @import("std");
const symbols = @import("symbols.zig");
pub const Id = enum(u32) { _ };
pub const max_records = 4096;
pub const max_record_runs = 4096;
pub const max_module_runs = 65536;
pub const max_repeat = 2147483647;
pub const Error = std.mem.Allocator.Error || error{
    InvalidRecordName,
    DuplicateType,
    InvalidRecordReference,
    InvalidRecordRepeat,
    InvalidRecordAlignment,
    InvalidRecordLayout,
    RecordLayoutOverflow,
    RecordLimitExceeded,
};
pub const Scalar = enum {
    byte,
    half,
    word,
    long,
    single,
    double,
    pub fn bytes(self: Scalar) u8 {
        return switch (self) {
            .byte => 1,
            .half => 2,
            .word, .single => 4,
            .long, .double => 8,
        };
    }
};
pub const Element = union(enum) { scalar: Scalar, record: Id };
pub const Field = struct { element: Element, count: u32 = 1 };
pub const Run = struct { field: Field, offset: u64, stride: u64 };
pub const Kind = enum { regular, union_type };
pub const Variant = struct { first_run: usize, run_count: usize, size: u64, alignment: u8 };
pub const Record = struct {
    allocator: std.mem.Allocator,
    /// Scoped to Module.record_names, never Module.symbols or a TypeId.
    name: symbols.Id,
    explicit_alignment: ?u8,
    alignment: u8,
    size: u64,
    runs: []Run,
    kind: Kind = .regular,
    /// Union alternatives partition runs, with each alternative offset relative to zero.
    variants: []Variant = &.{},

    pub fn deinit(self: *Record) void {
        // Cleanup follows ownership, never a mutable kind/cache discriminator.
        self.allocator.free(self.variants);
        self.allocator.free(self.runs);
        self.* = undefined;
    }

    /// Copies field structure; repeated conceptual bytes are never allocated.
    /// Caller supplies an already validated, earlier-only declaration table.
    pub fn create(allocator: std.mem.Allocator, name: symbols.Id, explicit_alignment: ?u8, fields: []const Field, earlier: []const *Record) Error!*Record {
        if (fields.len == 0) return error.InvalidRecordLayout;
        if (fields.len > max_record_runs) return error.RecordLimitExceeded;
        var alignment = try initialAlignment(explicit_alignment);
        var cursor: u64 = 0;
        // Check all arithmetic before allocating owned storage.
        for (fields) |field| _ = try nextRun(&cursor, &alignment, field, earlier);
        const size = try alignUp(cursor, alignment);
        const runs = try allocator.alloc(Run, fields.len);
        errdefer allocator.free(runs);
        var second_alignment = try initialAlignment(explicit_alignment);
        cursor = 0;
        for (fields, runs) |field, *run| run.* = try nextRun(&cursor, &second_alignment, field, earlier);
        const record = try allocator.create(Record);
        record.* = .{ .allocator = allocator, .name = name, .explicit_alignment = explicit_alignment, .alignment = alignment, .size = size, .runs = runs };
        return record;
    }
    /// Borrowed alternative lists are copied into one flat run array and owned headers.
    pub fn createUnion(allocator: std.mem.Allocator, name: symbols.Id, explicit_alignment: ?u8, alternatives: []const []const Field, earlier: []const *Record) Error!*Record {
        if (alternatives.len == 0) return error.InvalidRecordLayout;
        if (alternatives.len > max_record_runs) return error.RecordLimitExceeded;
        var total: usize = 0;
        var alignment = try initialAlignment(explicit_alignment);
        var maximum: u64 = 0;
        // Validate EVERY alternative before owned allocations/publication.
        for (alternatives) |fields| {
            if (fields.len == 0) return error.InvalidRecordLayout;
            total = std.math.add(usize, total, fields.len) catch return error.RecordLimitExceeded;
            if (total > max_record_runs) return error.RecordLimitExceeded;
            var cursor: u64 = 0;
            var arm_alignment = try initialAlignment(explicit_alignment);
            for (fields) |field| _ = try nextRun(&cursor, &arm_alignment, field, earlier);
            maximum = @max(maximum, try alignUp(cursor, arm_alignment));
            alignment = @max(alignment, arm_alignment);
        }
        const size = try alignUp(maximum, alignment);
        const runs = try allocator.alloc(Run, total);
        errdefer allocator.free(runs);
        const variants = try allocator.alloc(Variant, alternatives.len);
        errdefer allocator.free(variants);
        var offset: usize = 0;
        for (alternatives, variants) |fields, *variant| {
            var cursor: u64 = 0;
            var arm_alignment = try initialAlignment(explicit_alignment);
            for (fields, runs[offset..][0..fields.len]) |field, *run| run.* = try nextRun(&cursor, &arm_alignment, field, earlier);
            variant.* = .{ .first_run = offset, .run_count = fields.len, .size = try alignUp(cursor, arm_alignment), .alignment = arm_alignment };
            offset += fields.len; // Checked total above bounds every slice/addition.
        }
        const record = try allocator.create(Record);
        record.* = .{ .allocator = allocator, .name = name, .explicit_alignment = explicit_alignment, .alignment = alignment, .size = size, .runs = runs, .kind = .union_type, .variants = variants };
        return record;
    }
};

pub fn validName(name: []const u8) bool {
    if (name.len == 0 or !nameStart(name[0])) return false;
    for (name[1..]) |c| if (!nameStart(c) and !std.ascii.isDigit(c) and c != '$') return false;
    return true;
}
fn nameStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '.' or c == '_';
}
fn initialAlignment(explicit: ?u8) Error!u8 {
    const value = explicit orelse 1;
    if (value == 0 or value > 64 or value & (value - 1) != 0) return error.InvalidRecordAlignment;
    return value;
}
fn alignUp(value: u64, alignment: u8) Error!u64 {
    const mask: u64 = alignment - 1;
    const sum = std.math.add(u64, value, mask) catch return error.RecordLayoutOverflow;
    return sum & ~mask;
}
fn nextRun(cursor: *u64, alignment: *u8, field: Field, earlier: []const *Record) Error!Run {
    if (field.count == 0 or field.count > max_repeat) return error.InvalidRecordRepeat;
    var member_alignment: u8 = undefined;
    const stride: u64 = switch (field.element) {
        .scalar => |scalar| scalar: {
            member_alignment = scalar.bytes();
            break :scalar member_alignment;
        },
        .record => |id| child: {
            const index = @backingInt(id);
            if (index >= earlier.len) return error.InvalidRecordReference;
            const record = earlier[index];
            member_alignment = try initialAlignment(record.alignment);
            if (record.size == 0) return error.InvalidRecordLayout;
            break :child record.size;
        },
    };
    alignment.* = @max(alignment.*, member_alignment);
    const offset = try alignUp(cursor.*, member_alignment);
    const extent = std.math.mul(u64, stride, field.count) catch return error.RecordLayoutOverflow;
    cursor.* = std.math.add(u64, offset, extent) catch return error.RecordLayoutOverflow;
    return .{ .field = field, .offset = offset, .stride = stride };
}

/// Recompute EVERY declaration, including unused records. No lookup/cache is
/// trusted, and strictly earlier IDs avoid recursion or expanded type graphs.
/// pool MUST be the owning Module.record_names, not its codegen symbol pool.
pub fn validate(allocator: std.mem.Allocator, records: []const *Record, pool: *const symbols.Pool) Error!void {
    if (records.len > max_records) return error.RecordLimitExceeded;
    var names: std.AutoHashMapUnmanaged(symbols.Id, void) = .empty;
    defer names.deinit(allocator);
    var total: usize = 0;
    for (records, 0..) |record, index| {
        const name = pool.get(record.name) orelse return error.InvalidRecordName;
        if (!validName(name)) return error.InvalidRecordName;
        const entry = try names.getOrPut(allocator, record.name);
        if (entry.found_existing) return error.DuplicateType;
        entry.value_ptr.* = {};
        if (record.runs.len == 0) return error.InvalidRecordLayout;
        if (record.runs.len > max_record_runs) return error.RecordLimitExceeded;
        total = std.math.add(usize, total, record.runs.len) catch return error.RecordLimitExceeded;
        if (total > max_module_runs) return error.RecordLimitExceeded;
        var alignment = try initialAlignment(record.explicit_alignment);
        switch (record.kind) {
            .regular => {
                if (record.variants.len != 0) return error.InvalidRecordLayout;
                var cursor: u64 = 0;
                for (record.runs) |run| {
                    const expected = try nextRun(&cursor, &alignment, run.field, records[0..index]);
                    if (!std.meta.eql(expected, run)) return error.InvalidRecordLayout;
                }
                if (record.alignment != alignment or record.size != try alignUp(cursor, alignment)) return error.InvalidRecordLayout;
            },
            .union_type => {
                if (record.variants.len == 0 or record.variants.len > max_record_runs) return error.InvalidRecordLayout;
                var consumed: usize = 0;
                var maximum: u64 = 0;
                for (record.variants) |variant| {
                    if (variant.first_run != consumed or variant.run_count == 0) return error.InvalidRecordLayout;
                    const limit = std.math.add(usize, consumed, variant.run_count) catch return error.InvalidRecordLayout;
                    if (limit > record.runs.len) return error.InvalidRecordLayout;
                    var cursor: u64 = 0;
                    var arm_alignment = try initialAlignment(record.explicit_alignment);
                    for (record.runs[consumed..limit]) |run| {
                        const expected = try nextRun(&cursor, &arm_alignment, run.field, records[0..index]);
                        if (!std.meta.eql(expected, run)) return error.InvalidRecordLayout;
                    }
                    const size = try alignUp(cursor, arm_alignment);
                    if (variant.size != size or variant.alignment != arm_alignment) return error.InvalidRecordLayout;
                    maximum = @max(maximum, size);
                    alignment = @max(alignment, arm_alignment);
                    consumed = limit;
                }
                if (consumed != record.runs.len or record.alignment != alignment or record.size != try alignUp(maximum, alignment)) return error.InvalidRecordLayout;
            },
        }
    }
}
