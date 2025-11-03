const std = @import("std");
const errors = @import("errors.zig");
const reader = @import("reader.zig");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("chunk.zig").OpCode;

pub fn compile(allocator: std.mem.Allocator, source: []const u8, err_ctx: *errors.Ctx) !Chunk {
    var tokens_data = try reader.readStr(allocator, source, err_ctx);
    defer tokens_data.deinit(allocator);

    var chunk = Chunk.empty;

    for (tokens_data.items) |*atom| {
        defer atom.value.deinit(allocator);

        switch (atom.value) {
            .int, .float, .nil, .boolean => try chunk.emitConstant(allocator, atom.value, atom.line),
            .symbol => |s| {
                const op_code: OpCode = switch (s.bytes[0]) {
                    '+' => .add,
                    '-' => .subtract,
                    '*' => .multiply,
                    '/' => .divide,
                    else => {
                        try err_ctx.setMsg(allocator, "Symbol {s} not implemented.", .{s.bytes});
                        return error.NotImplemented;
                    },
                };
                try chunk.emitByte(allocator, @intFromEnum(op_code), atom.line);
            },
        }
    }

    chunk.end(allocator);

    return chunk;
}
