const std = @import("std");
const errors = @import("errors.zig");
const reader = @import("reader.zig");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("chunk.zig").OpCode;

pub fn compile(allocator: std.mem.Allocator, source: []const u8, err_ctx: *errors.Ctx) !Chunk {
    var tokens_data = try reader.tokenize(allocator, source, err_ctx);
    defer tokens_data.deinit(allocator);

    var r = reader.Reader{
        .token_list = tokens_data,
        .current = 0,
    };

    var chunk = Chunk.empty;

    while (r.next()) |data| {
        const atom = try reader.readAtom(allocator, data, err_ctx);
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
