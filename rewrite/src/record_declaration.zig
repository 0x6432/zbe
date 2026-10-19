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
pub const Record = struct {
    allocator: std.mem.Allocator,
    /// Scoped to Module.record_names, never Module.symbols or a TypeId.
    name: symbols.Id,
    explicit_alignment: ?u8,
    alignment: u8,
    size: u64,
    runs: []Run,

    pub fn deinit(self: *Record) void {
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
        var cursor: u64 = 0;
        for (record.runs) |run| {
            const expected = try nextRun(&cursor, &alignment, run.field, records[0..index]);
            if (!std.meta.eql(expected, run)) return error.InvalidRecordLayout;
        }
        if (record.alignment != alignment or record.size != try alignUp(cursor, alignment)) return error.InvalidRecordLayout;
    }
}
