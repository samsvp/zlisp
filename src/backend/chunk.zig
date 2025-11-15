const std = @import("std");
const Obj = @import("../value.zig").Obj;
const Value = @import("../value.zig").Value;

pub const OpCode = enum(u8) {
    noop,
    ret,
    pop,
    constant,
    constant_long,
    add,
    subtract,
    multiply,
    divide,
    eq,
    not,
    lt,
    gt,
    leq,
    geq,
    jump,
    jump_if_false,
    create_vec,
    create_vec_long,
    create_closure,
    def_global,
    get_global,
    def_local,
    get_local,
    call,

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
        try self.constants.append(allocator, v.borrow());
        return self.constants.items.len - 1;
    }

    pub fn emitByte(chunk: *Chunk, allocator: std.mem.Allocator, byte: u8, line: usize) !void {
        try chunk.code.append(allocator, byte);
        try chunk.lines.append(allocator, line);
    }

    pub fn emitBytes(chunk: *Chunk, allocator: std.mem.Allocator, bytes: []const u8, line: usize) !void {
        for (bytes) |b| {
            try chunk.emitByte(allocator, b, line);
        }
    }

    pub fn emitConstant(chunk: *Chunk, allocator: std.mem.Allocator, v: Value, line: usize) !u8 {
        const const_index = try chunk.addConstant(allocator, v);

        if (const_index <= 255) {
            try chunk.emitBytes(allocator, &[_]u8{ @intFromEnum(OpCode.constant), @intCast(const_index) }, line);
            return 2;
        } else {
            const index_16: u16 = @intCast(const_index);
            const index_bytes = std.mem.toBytes(index_16);
            try chunk.emitBytes(allocator, &[_]u8{ @intFromEnum(OpCode.constant_long), index_bytes[0], index_bytes[1] }, line);
            return 3;
        }
    }

    pub fn emitGetGlobal(chunk: *Chunk, allocator: std.mem.Allocator, name: []const u8, line: usize) !void {
        _ = try chunk.emitConstant(allocator, .{ .symbol = name }, line);
        try chunk.append(allocator, .get_global, line);
    }

    pub fn emitGetLocal(chunk: *Chunk, allocator: std.mem.Allocator, offset: u16, line: usize) !void {
        try chunk.append(allocator, .get_local, line);
        const bs = std.mem.toBytes(offset);
        try chunk.emitBytes(allocator, &bs, line);
    }

    pub fn emitJump(chunk: *Chunk, allocator: std.mem.Allocator, offset: u16, line: usize) !usize {
        const bytes = std.mem.toBytes(offset);
        try chunk.append(allocator, .jump, line);
        try chunk.emitBytes(allocator, &bytes, line);
        return chunk.code.items.len - 3;
    }

    pub fn emitJumpIfFalse(chunk: *Chunk, allocator: std.mem.Allocator, offset: u16, line: usize) !usize {
        const bytes = std.mem.toBytes(offset);
        try chunk.append(allocator, .jump_if_false, line);
        try chunk.emitBytes(allocator, &bytes, line);
        return chunk.code.items.len - 3;
    }

    pub fn replaceBytes(chunk: *Chunk, index: usize, bytes: []const u8) void {
        @memcpy(chunk.code.items.ptr + index, bytes);
    }

    pub fn replaceJump(chunk: *Chunk, index: usize, offset: u16) void {
        chunk.replaceBytes(index + 1, &std.mem.toBytes(offset));
    }

    pub fn emitVec(chunk: *Chunk, allocator: std.mem.Allocator, n: u16, line: usize) !void {
        if (n < 256) {
            try chunk.append(allocator, .create_vec, line);
            try chunk.emitByte(allocator, @intCast(n), line);
            return;
        }

        const bytes = std.mem.toBytes(n);
        try chunk.append(allocator, .create_vec_long, line);
        try chunk.emitBytes(allocator, &bytes, line);
    }

    pub fn end(chunk: *Chunk, allocator: std.mem.Allocator) !void {
        try chunk.append(allocator, .ret, 0);
    }

    pub fn deinit(self: *Chunk, allocator: std.mem.Allocator) void {
        for (self.constants.items) |*c| {
            c.deinit(allocator);
        }

        self.code.deinit(allocator);
        self.constants.deinit(allocator);
        self.lines.deinit(allocator);
    }
};
