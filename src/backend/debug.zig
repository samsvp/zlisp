const std = @import("std");

const Obj = @import("../value.zig").Obj;
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
            const str = try v.toString(allocator);
            defer allocator.free(str);
            const res = try std.fmt.allocPrint(allocator, "OP_CONSTANT {s}", .{str});
            break :constant .{ res, 2 };
        },
        .constant_long => constant_long: {
            const c_index = std.mem.bytesToValue(u16, chunk.code.items[index + 1 .. index + 3]);
            const v = chunk.constants.items[c_index];
            const str = try v.toString(allocator);
            defer allocator.free(str);
            const res = try std.fmt.allocPrint(allocator, "OP_CONSTANT_LONG {s}", .{str});
            break :constant_long .{ res, 3 };
        },
        .jump => jump: {
            const v = std.mem.bytesToValue(u16, chunk.code.items[index + 1 .. index + 3]);
            break :jump .{ try std.fmt.allocPrint(allocator, "OP_JUMP {d}", .{v}), 3 };
        },
        .jump_if_false => jump_false: {
            const v = std.mem.bytesToValue(u16, chunk.code.items[index + 1 .. index + 3]);
            break :jump_false .{ try std.fmt.allocPrint(allocator, "OP_JUMP_IF_FALSE {d}", .{v}), 3 };
        },
        .def_global => .{ try std.fmt.allocPrint(allocator, "OP_DEF_GLOBAL", .{}), 1 },
        .get_global => .{ try std.fmt.allocPrint(allocator, "OP_GET_GLOBAL", .{}), 1 },
        .def_local => .{ try std.fmt.allocPrint(allocator, "OP_DEF_LOCAL", .{}), 1 },
        .get_local => .{ try std.fmt.allocPrint(allocator, "OP_GET_LOCAL", .{}), 3 },
        .ret => .{ try std.fmt.allocPrint(allocator, "OP_RETURN", .{}), 1 },
        .add => .{ try std.fmt.allocPrint(allocator, "OP_ADD", .{}), 2 },
        .subtract => .{ try std.fmt.allocPrint(allocator, "OP_SUBTRACT", .{}), 2 },
        .divide => .{ try std.fmt.allocPrint(allocator, "OP_DIVIDE", .{}), 2 },
        .multiply => .{ try std.fmt.allocPrint(allocator, "OP_MULTIPLY", .{}), 2 },
        .eq => .{ try std.fmt.allocPrint(allocator, "OP_EQUAL", .{}), 2 },
        .not => .{ try std.fmt.allocPrint(allocator, "OP_NOT", .{}), 2 },
        .lt => .{ try std.fmt.allocPrint(allocator, "OP_LESS", .{}), 2 },
        .gt => .{ try std.fmt.allocPrint(allocator, "OP_GREATER", .{}), 2 },
        .leq => .{ try std.fmt.allocPrint(allocator, "OP_LESS_EQUAL", .{}), 2 },
        .geq => .{ try std.fmt.allocPrint(allocator, "OP_GREATER_EQUAL", .{}), 2 },
        .create_vec => .{ try std.fmt.allocPrint(allocator, "OP_CREATE_VEC", .{}), 2 },
        .create_vec_long => .{ try std.fmt.allocPrint(allocator, "OP_CREATE_VEC_LONG", .{}), 3 },
        .create_closure => .{ try std.fmt.allocPrint(allocator, "OP_CREATE_CLOSURE", .{}), 3 },
        .call => .{ try std.fmt.allocPrint(allocator, "OP_CALL", .{}), 3 },
        .pop => .{ try std.fmt.allocPrint(allocator, "OP_POP", .{}), 1 },
        .noop => .{ try std.fmt.allocPrint(allocator, "OP_NOOP", .{}), 1 },
    };
}

pub fn disassembleChunk(allocator: std.mem.Allocator, chunk: Chunk, name: []const u8) !void {
    std.debug.print("==== {s} ====\n", .{name});

    var index: usize = 0;
    var line_i: usize = 0;
    var last_line: usize = 0;
    while (index < chunk.code.items.len) : (line_i += 1) {
        const op_name, const offset = try disassembleInstruction(allocator, chunk, index);
        defer allocator.free(op_name);

        const new_line = chunk.lines.items[line_i];
        if (new_line != last_line) {
            std.debug.print("[ {d:0>4} ] {d:0>4} {s}\n", .{ index, new_line, op_name });
        } else {
            std.debug.print("[ {d:0>4} ]    | {s}\n", .{ index, op_name });
        }
        last_line = new_line;
        index += offset;
    }
}
