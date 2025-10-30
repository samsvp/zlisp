const std = @import("std");

const chunk_ = @import("chunk.zig");
const OpCode = chunk_.OpCode;
const Chunk = chunk_.Chunk;

fn constant(chunk: Chunk, buf: []u8, constant_index: usize) []const u8 {
    const v = chunk.constants.items[constant_index];
    return std.fmt.bufPrint(buf, "OP_CONSTANT {}", .{v}) catch unreachable;
}

pub fn disassembleChunk(chunk: Chunk, name: []const u8, writer: *std.io.Writer) !void {
    try writer.print("==== {s} ====\n", .{name});

    var index: usize = 0;
    var buf: [32]u8 = undefined;
    var line_i: usize = 0;
    var last_line: usize = 0;
    while (index < chunk.code.items.len) : (line_i += 1) {
        const c = chunk.code.items[index];
        const new_line = chunk.lines.items[line_i];
        const op_code = std.enums.fromInt(OpCode, c) orelse {
            try writer.print("[ {d:0>4} ] {d:0>4} INVALID OP CODE", .{ index, new_line });
            index += 1;
            continue;
        };

        const op_name, const offset: usize = switch (op_code) {
            .constant => constant: {
                const c_index = chunk.code.items[index + 1];
                const v = chunk.constants.items[c_index];
                const res = std.fmt.bufPrint(&buf, "OP_CONSTANT {}", .{v}) catch unreachable;
                break :constant .{ res, 2 };
            },
            .constant_long => constant_long: {
                const c_index = std.mem.bytesToValue(u16, chunk.code.items[index + 1 .. index + 3]);
                const v = chunk.constants.items[c_index];
                const res = std.fmt.bufPrint(&buf, "OP_CONSTANT_LONG {}", .{v}) catch unreachable;
                break :constant_long .{ res, 3 };
            },
            .ret => .{ "OP_RETURN", 1 },
            .noop => .{ "OP_NOOP", 1 },
        };

        if (new_line != last_line) {
            try writer.print("[ {d:0>4} ] {d:0>4} {s}\n", .{ index, new_line, op_name });
        } else {
            try writer.print("[ {d:0>4} ]    | {s}\n", .{ index, op_name });
        }
        last_line = new_line;
        try writer.flush();
        index += offset;
    }
}
