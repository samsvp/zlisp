const std = @import("std");

const chunk_ = @import("chunk.zig");
const OpCode = chunk_.OpCode;
const Chunk = chunk_.Chunk;

pub fn disassembleInstruction(allocator: std.mem.Allocator, chunk: Chunk, index: usize) !std.meta.Tuple(&.{ []const u8, usize }) {
    const c = chunk.code.items[index];
    const op_code = std.enums.fromInt(OpCode, c) orelse {
        return error.InvalidOpCode;
    };

    return switch (op_code) {
        .constant => constant: {
            const c_index = chunk.code.items[index + 1];
            const v = chunk.constants.items[c_index];
            const res = switch (v) {
                .obj => |o| switch (o) {
                    .string => |s| try std.fmt.allocPrint(allocator, "OP_CONSTANT {s}", .{s.bytes}),
                },
                else => try std.fmt.allocPrint(allocator, "OP_CONSTANT {}", .{v}),
            };
            break :constant .{ res, 2 };
        },
        .constant_long => constant_long: {
            const c_index = std.mem.bytesToValue(u16, chunk.code.items[index + 1 .. index + 3]);
            const v = chunk.constants.items[c_index];
            const res = switch (v) {
                .obj => |o| switch (o) {
                    .string => |s| std.fmt.allocPrint(allocator, "OP_CONSTANT_LONG {s}", .{s.bytes}) catch unreachable,
                },
                else => std.fmt.allocPrint(allocator, "OP_CONSTANT_LONG {}", .{v}) catch unreachable,
            };
            break :constant_long .{ res, 3 };
        },
        .ret => .{ std.fmt.allocPrint(allocator, "OP_RETURN", .{}) catch unreachable, 1 },
        .add => .{ std.fmt.allocPrint(allocator, "OP_ADD", .{}) catch unreachable, 1 },
        .subtract => .{ std.fmt.allocPrint(allocator, "OP_SUBTRACT", .{}) catch unreachable, 1 },
        .divide => .{ std.fmt.allocPrint(allocator, "OP_DIVIDE", .{}) catch unreachable, 1 },
        .multiply => .{ std.fmt.allocPrint(allocator, "OP_MULTIPLY", .{}) catch unreachable, 1 },
        .noop => .{ std.fmt.allocPrint(allocator, "OP_NOOP", .{}) catch unreachable, 1 },
    };
}

pub fn disassembleChunk(allocator: std.mem.Allocator, chunk: Chunk, name: []const u8, writer: *std.io.Writer) !void {
    try writer.print("==== {s} ====\n", .{name});

    var index: usize = 0;
    var line_i: usize = 0;
    var last_line: usize = 0;
    while (index < chunk.code.items.len) : (line_i += 1) {
        const op_name, const offset = try disassembleInstruction(allocator, chunk, index);
        defer allocator.free(op_name);

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
