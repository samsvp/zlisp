const std = @import("std");

const chunk_ = @import("chunk.zig");
const OpCode = chunk_.OpCode;
const Chunk = chunk_.Chunk;

pub fn disassembleInstruction(chunk: Chunk, index: usize, buf: []u8) !std.meta.Tuple(&.{ []const u8, usize }) {
    const c = chunk.code.items[index];
    const op_code = std.enums.fromInt(OpCode, c) orelse {
        return error.InvalidOpCode;
    };

    return switch (op_code) {
        .constant => constant: {
            const c_index = chunk.code.items[index + 1];
            const v = chunk.constants.items[c_index];
            const res = std.fmt.bufPrint(buf, "OP_CONSTANT {}", .{v}) catch unreachable;
            break :constant .{ res, 2 };
        },
        .constant_long => constant_long: {
            const c_index = std.mem.bytesToValue(u16, chunk.code.items[index + 1 .. index + 3]);
            const v = chunk.constants.items[c_index];
            const res = std.fmt.bufPrint(buf, "OP_CONSTANT_LONG {}", .{v}) catch unreachable;
            break :constant_long .{ res, 3 };
        },
        .ret => .{ "OP_RETURN", 1 },
        .negate => .{ "OP_NEGATE", 1 },
        .add => .{ "OP_ADD", 1 },
        .subtract => .{ "OP_SUBTRACT", 1 },
        .divide => .{ "OP_DIVIDE", 1 },
        .multiply => .{ "OP_MULTIPLY", 1 },
        .noop => .{ "OP_NOOP", 1 },
    };
}

pub fn disassembleChunk(chunk: Chunk, name: []const u8, writer: *std.io.Writer) !void {
    try writer.print("==== {s} ====\n", .{name});

    var index: usize = 0;
    var buf: [32]u8 = undefined;
    var line_i: usize = 0;
    var last_line: usize = 0;
    while (index < chunk.code.items.len) : (line_i += 1) {
        const op_name, const offset = try disassembleInstruction(chunk, index, &buf);

        const new_line = chunk.lines.items[line_i];
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
