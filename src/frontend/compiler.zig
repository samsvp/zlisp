const std = @import("std");
const errors = @import("../errors.zig");
const reader = @import("reader.zig");

const Obj = @import("../value.zig").Obj;
const Value = @import("../value.zig").Value;
const Chunk = @import("../backend/chunk.zig").Chunk;
const OpCode = @import("../backend/chunk.zig").OpCode;

pub const Errors = error{
    NonFunctionAsHeadOfList,
};

/// Returns false if the function is a builtin (+,-,*,/) or a true function to be called.
pub fn compileAtom(allocator: std.mem.Allocator, chunk: *Chunk, value: Value, line: usize) !bool {
    switch (value) {
        .symbol => {
            const v = value.symbol;
            const maybe_op: ?OpCode = if (v.len == 1) switch (v[0]) {
                '+' => .add,
                '-' => .subtract,
                '*' => .multiply,
                '/' => .divide,
                else => null,
            } else null;

            if (maybe_op) |op| {
                try chunk.append(allocator, op, line);
                return false;
            }

            // TODO! check if variable is a local
            try chunk.emitGetGlobal(allocator, value.symbol, line);
        },
        else => _ = try chunk.emitConstant(allocator, value, line),
    }
    return true;
}

pub fn compileList(
    allocator: std.mem.Allocator,
    chunk: *Chunk,
    list: std.ArrayList(reader.Token),
    line: usize,
    err_ctx: *errors.Ctx,
) !void {
    if (list.items.len == 0) {
        const empty_list = try Obj.List.empty(allocator);
        _ = try chunk.emitConstant(allocator, .{ .obj = &empty_list.obj }, line);
        return;
    }

    const first = list.items[0];
    if (first.kind != .atom) {
        // TODO! The first element could be a list if it defines an anonymous function
        err_ctx.line = line;
        try err_ctx.setMsg(allocator, "COMPILE", "List first element must be function.", .{});
        return Errors.NonFunctionAsHeadOfList;
    }

    const atom = first.kind.atom;
    if (atom != .symbol) {
        err_ctx.line = line;
        try err_ctx.setMsg(allocator, "COMPILE", "List first element must be function.", .{});
        return Errors.NonFunctionAsHeadOfList;
    }

    for (list.items[1..]) |token| switch (token.kind) {
        .atom => |v| _ = try compileAtom(allocator, chunk, v, token.line),
        .list => |m_list| try compileList(allocator, chunk, m_list, token.line, err_ctx),
    };

    // compile the atom last
    if (try compileAtom(allocator, chunk, atom, line)) {
        try chunk.append(allocator, .call, 125);
    }
    try chunk.emitByte(allocator, @intCast(list.items.len - 1), 125);
}

pub fn compile(allocator: std.mem.Allocator, source: []const u8, err_ctx: *errors.Ctx) !*Chunk {
    var tokens = try reader.readStr(allocator, source, err_ctx);
    defer tokens.deinit(allocator);

    defer for (tokens.items) |*token| token.deinit(allocator);

    const chunk = try allocator.create(Chunk);
    chunk.* = Chunk.empty;
    for (tokens.items, 0..) |token, i| switch (token.kind) {
        .atom => |a| {
            if (i != tokens.items.len - 1) {
                // ignore any atom that is not the last statement
                continue;
            }
            _ = try compileAtom(allocator, chunk, a, token.line);
        },
        .list => |list| {
            if (list.items.len == 0 and i != tokens.items.len - 1) {
                // ignore any atom that is not the last statement
                continue;
            }

            try compileList(allocator, chunk, list, token.line, err_ctx);
            // pop the last statement value
            if (i != tokens.items.len - 1) {}
        },
    };

    try chunk.append(allocator, .ret, 0);
    return chunk;
}
