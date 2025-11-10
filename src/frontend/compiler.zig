const std = @import("std");
const errors = @import("../errors.zig");
const reader = @import("reader.zig");

const Obj = @import("../value.zig").Obj;
const Value = @import("../value.zig").Value;
const Chunk = @import("../backend/chunk.zig").Chunk;
const OpCode = @import("../backend/chunk.zig").OpCode;

pub fn compileAtom(allocator: std.mem.Allocator, chunk: *Chunk, atom: reader.Token.Atom) !void {
    switch (atom.value) {
        else => try chunk.emitConstant(allocator, atom.value, atom.line),
    }
}

pub fn compile(allocator: std.mem.Allocator, source: []const u8, err_ctx: *errors.Ctx) !*Chunk {
    const chunk = try allocator.create(Chunk);
    chunk.* = Chunk.empty;

    var tokens = try reader.readStr(allocator, source, err_ctx);
    defer tokens.deinit(allocator);

    for (tokens.items, 0..) |token, i| switch (token) {
        .atom => |a| {
            if (i != tokens.items.len - 1) {
                // ignore any atom that is not the last statement
                continue;
            }
            try compileAtom(allocator, chunk, a);
        },
        .list => |list| {
            if (list.items.len == 0) {
                if (i != tokens.items.len - 1) {
                    // ignore any atom that is not the last statement
                    continue;
                }

                // return empty list
                const empty_list = try Obj.List.empty(allocator);
                try chunk.emitConstant(allocator, .{ .obj = &empty_list.obj }, 0);
                continue;
            }
        },
    };

    return chunk;
}
