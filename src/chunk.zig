const std = @import("std");
const Value = @import("value.zig").Value;

pub const OpCode = enum {
    noop,
    ret,
    constant,
};

pub const Chunk = struct {
    code: std.ArrayList(u8),
    constants: std.ArrayList(Value),
    lines: std.ArrayList(usize),

    pub const empty: Chunk = .{
        .code = .empty,
        .constants = .empty,
        .lines = .empty,
    };

    pub fn append(self: *Chunk, allocator: std.mem.Allocator, c: OpCode, line: usize) !void {
        try self.code.append(allocator, @intFromEnum(c));
        try self.lines.append(allocator, line);
    }

    /// Adds a constant to the constant array and returns its index.
    pub fn addConstant(self: *Chunk, allocator: std.mem.Allocator, v: Value) !usize {
        try self.constants.append(allocator, v);
        return self.constants.items.len - 1;
    }

    pub fn deinit(self: *Chunk, allocator: std.mem.Allocator) void {
        self.code.deinit(allocator);
        self.constants.deinit(allocator);
        self.lines.deinit(allocator);
    }
};
