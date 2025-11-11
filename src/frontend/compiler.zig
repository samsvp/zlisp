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

pub fn compileAtom(allocator: std.mem.Allocator, chunk: *Chunk, value: Value, line: usize) !void {
    try chunk.emitConstant(allocator, value, line);
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
        try chunk.emitConstant(allocator, .{ .obj = &empty_list.obj }, line);
        return;
    }

    const first = list.items[0];
    if (first.kind != .atom) {
        // TODO! The first element could be a list if it defines an anonymous function
        err_ctx.line = line;
        err_ctx.setMsg(allocator, "COMPILE", "List first element must be function.", .{});
        return Errors.NonFunctionAsHeadOfList;
    }

    // TODO! the rest of the function, lol
}

pub fn compile(allocator: std.mem.Allocator, source: []const u8, err_ctx: *errors.Ctx) !*Chunk {
    const chunk = try allocator.create(Chunk);
    chunk.* = Chunk.empty;

    var tokens = try reader.readStr(allocator, source, err_ctx);
    defer tokens.deinit(allocator);

    for (tokens.items, 0..) |token, i| switch (token.kind) {
        .atom => |a| {
            if (i != tokens.items.len - 1) {
                // ignore any atom that is not the last statement
                continue;
            }
            try compileAtom(allocator, a, token.line);
        },
        .list => |list| {
            if (list.items.len == 0 and i != tokens.items.len - 1) {
                // ignore any atom that is not the last statement
                continue;
            }

            compileList(allocator, chunk, list, token.line);
        },
    };

    return chunk;
}
