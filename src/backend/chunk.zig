const std = @import("std");
const Obj = @import("../values/value.zig").Obj;
const Value = @import("../values/value.zig").Value;

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
    create_list,
    create_list_long,
    create_hash_map,
    create_hash_map_long,
    create_closure,
    def_global,
    get_global,
    def_local,
    get_local,
    shrink_locals,
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

    pub fn append(self: *Chunk, gpa: std.mem.Allocator, c: OpCode, line: usize) !void {
        try self.code.append(gpa, @intFromEnum(c));
        try self.lines.append(gpa, line);
    }

    /// Adds a constant to the constant array and returns its index.
    pub fn addConstant(self: *Chunk, gpa: std.mem.Allocator, v: Value) !usize {
        try self.constants.append(gpa, v.borrow());
        return self.constants.items.len - 1;
    }

    pub fn emitByte(chunk: *Chunk, gpa: std.mem.Allocator, byte: u8, line: usize) !void {
        try chunk.code.append(gpa, byte);
        try chunk.lines.append(gpa, line);
    }

    pub fn emitBytes(chunk: *Chunk, gpa: std.mem.Allocator, bytes: []const u8, line: usize) !void {
        for (bytes) |b| {
            try chunk.emitByte(gpa, b, line);
        }
    }

    pub fn emitConstant(chunk: *Chunk, gpa: std.mem.Allocator, v: Value, line: usize) !u8 {
        const const_index = try chunk.addConstant(gpa, v);

        if (const_index <= 255) {
            try chunk.emitBytes(gpa, &[_]u8{ @intFromEnum(OpCode.constant), @intCast(const_index) }, line);
            return 2;
        } else {
            const index_16: u16 = @intCast(const_index);
            const index_bytes = std.mem.toBytes(index_16);
            try chunk.emitBytes(gpa, &[_]u8{ @intFromEnum(OpCode.constant_long), index_bytes[0], index_bytes[1] }, line);
            return 3;
        }
    }

    pub fn emitGetGlobal(chunk: *Chunk, gpa: std.mem.Allocator, name: []const u8, line: usize) !void {
        _ = try chunk.emitConstant(gpa, .{ .symbol = name }, line);
        try chunk.append(gpa, .get_global, line);
    }

    pub fn emitGetLocal(chunk: *Chunk, gpa: std.mem.Allocator, offset: u16, line: usize) !void {
        try chunk.append(gpa, .get_local, line);
        const bs = std.mem.toBytes(offset);
        try chunk.emitBytes(gpa, &bs, line);
    }

    pub fn emitJump(chunk: *Chunk, gpa: std.mem.Allocator, offset: u16, line: usize) !usize {
        const bytes = std.mem.toBytes(offset);
        try chunk.append(gpa, .jump, line);
        try chunk.emitBytes(gpa, &bytes, line);
        return chunk.code.items.len - 3;
    }

    pub fn emitJumpIfFalse(chunk: *Chunk, gpa: std.mem.Allocator, offset: u16, line: usize) !usize {
        const bytes = std.mem.toBytes(offset);
        try chunk.append(gpa, .jump_if_false, line);
        try chunk.emitBytes(gpa, &bytes, line);
        return chunk.code.items.len - 3;
    }

    pub fn replaceBytes(chunk: *Chunk, index: usize, bytes: []const u8) void {
        @memcpy(chunk.code.items.ptr + index, bytes);
    }

    pub fn replaceJump(chunk: *Chunk, index: usize, offset: u16) void {
        chunk.replaceBytes(index + 1, &std.mem.toBytes(offset));
    }

    pub fn emitVec(chunk: *Chunk, gpa: std.mem.Allocator, n: u16, line: usize) !void {
        if (n < 256) {
            try chunk.append(gpa, .create_vec, line);
            try chunk.emitByte(gpa, @intCast(n), line);
            return;
        }

        const bytes = std.mem.toBytes(n);
        try chunk.append(gpa, .create_vec_long, line);
        try chunk.emitBytes(gpa, &bytes, line);
    }

    pub fn emitList(chunk: *Chunk, gpa: std.mem.Allocator, n: u16, line: usize) !void {
        if (n < 256) {
            try chunk.append(gpa, .create_list, line);
            try chunk.emitByte(gpa, @intCast(n), line);
            return;
        }

        const bytes = std.mem.toBytes(n);
        try chunk.append(gpa, .create_list_long, line);
        try chunk.emitBytes(gpa, &bytes, line);
    }

    pub fn emitHashMap(chunk: *Chunk, gpa: std.mem.Allocator, n: u16, line: usize) !void {
        if (n < 256) {
            try chunk.append(gpa, .create_hash_map, line);
            try chunk.emitByte(gpa, @intCast(n), line);
            return;
        }

        const bytes = std.mem.toBytes(n);
        try chunk.append(gpa, .create_hash_map_long, line);
        try chunk.emitBytes(gpa, &bytes, line);
    }

    pub fn emitShrinkLocals(chunk: *Chunk, gpa: std.mem.Allocator, n: u16, line: usize) !void {
        const bytes = std.mem.toBytes(n);
        try chunk.append(gpa, .shrink_locals, line);
        try chunk.emitBytes(gpa, &bytes, line);
    }

    pub fn end(chunk: *Chunk, gpa: std.mem.Allocator) !void {
        try chunk.append(gpa, .ret, 0);
    }

    pub fn deinit(self: *Chunk, gpa: std.mem.Allocator) void {
        for (self.constants.items) |*c| {
            c.deinit(gpa);
        }

        self.code.deinit(gpa);
        self.constants.deinit(gpa);
        self.lines.deinit(gpa);
    }
};
