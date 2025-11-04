const std = @import("std");
const Obj = @import("value.zig").Obj;
const Value = @import("value.zig").Value;

pub const OpCode = enum {
    noop,
    ret,
    constant,
    constant_long,
    add,
    subtract,
    multiply,
    divide,

    pub const Error = error{
        InvalidOpCode,
    };
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

    pub fn addString(self: *Chunk, allocator: std.mem.Allocator, str: []const u8) !usize {
        const string = try Obj.String.init(allocator, str);
        return self.addConstant(allocator, .{ .obj = .{ .string = string } });
    }

    pub fn emitByte(chunk: *Chunk, allocator: std.mem.Allocator, byte: u8, line: usize) !void {
        const op_code = std.enums.fromInt(OpCode, byte) orelse return OpCode.Error.InvalidOpCode;
        try chunk.append(allocator, op_code, line);
    }

    pub fn emitBytes(chunk: *Chunk, allocator: std.mem.Allocator, bytes: []const u8, line: usize) !void {
        for (bytes) |b| {
            try chunk.emitByte(allocator, b, line);
        }
    }

    pub fn emitConstant(chunk: *Chunk, allocator: std.mem.Allocator, v: Value, line: usize) !void {
        const const_index = try chunk.addConstant(allocator, v);

        if (const_index <= 255) {
            try chunk.emitBytes(allocator, &[_]u8{ @intFromEnum(OpCode.constant), @intCast(const_index) }, line);
        } else {
            const index_16: u16 = @intCast(const_index);
            const index_bytes = std.mem.toBytes(index_16);
            try chunk.emitBytes(allocator, &[_]u8{ @intFromEnum(OpCode.constant_long), index_bytes[0], index_bytes[1] }, line);
        }
    }

    pub fn emitRet(chunk: *Chunk, allocator: std.mem.Allocator, line: usize) !void {
        try chunk.emitByte(allocator, @intFromEnum(OpCode.ret), line);
    }

    pub fn end(chunk: *Chunk, allocator: std.mem.Allocator) void {
        chunk.emitRet(allocator, 0) catch unreachable;
    }

    pub fn deinit(self: *Chunk, allocator: std.mem.Allocator) void {
        self.code.deinit(allocator);
        self.constants.deinit(allocator);
        self.lines.deinit(allocator);
    }
};
