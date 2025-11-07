const std = @import("std");
const ln = @import("linenoise");

const Chunk = @import("chunk.zig").Chunk;
const errors = @import("errors.zig");
const VM = @import("vm.zig").VM;
const reader = @import("reader.zig");
const Value = @import("value.zig").Value;
const Obj = @import("value.zig").Obj;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.debug.print("WARNING: memory leaked\n", .{});
    }

    const allocator = gpa.allocator();

    var err_ctx = errors.Ctx{ .msg = "" };
    defer err_ctx.deinit(allocator);

    var chunk = Chunk.empty;
    const function = try Obj.Function.init(allocator, 0, &chunk, "main", "");

    var s0_1 = try Obj.String.init(allocator, "wow man!");
    var s0_2 = try Obj.String.init(allocator, "wow woman!");

    _ = try chunk.emitConstant(allocator, Value.False, 123);

    const jump_false_index = try chunk.emitJumpIfFalse(allocator, 0, 12);
    const offset_1 = try chunk.emitConstant(allocator, .{ .obj = &s0_1.obj }, 13);
    const jump_index = try chunk.emitJump(allocator, 0, 13);

    chunk.replaceJump(jump_false_index, offset_1 + 3);

    const offset_2 = try chunk.emitConstant(allocator, .{ .obj = &s0_2.obj }, 14);
    chunk.replaceJump(jump_index, offset_2);

    try chunk.emitDefGlobal(allocator, "my_var", 10);

    _ = try chunk.emitConstant(allocator, .{ .float = 1.2 }, 123);
    _ = try chunk.emitConstant(allocator, .{ .float = 3.4 }, 123);
    _ = try chunk.emitConstant(allocator, .{ .int = 2 }, 123);
    try chunk.append(allocator, .add, 123);

    _ = try chunk.emitConstant(allocator, .{ .float = 5.6 }, 123);
    _ = try chunk.emitConstant(allocator, .{ .int = 2 }, 123);
    try chunk.append(allocator, .divide, 123);

    _ = try chunk.emitConstant(allocator, .{ .int = 1 }, 123);
    try chunk.append(allocator, .subtract, 123);

    var s3 = try Obj.String.init(allocator, "!");
    var s2 = try Obj.String.init(allocator, "world");
    var s1 = try Obj.String.init(allocator, "hello ");
    _ = try chunk.emitConstant(allocator, .{ .obj = &s3.obj }, 123);
    _ = try chunk.emitConstant(allocator, .{ .obj = &s2.obj }, 123);
    _ = try chunk.emitConstant(allocator, .{ .obj = &s1.obj }, 123);
    try chunk.emitGetGlobal(allocator, "my_var", 123);
    _ = try chunk.emitConstant(allocator, .{ .int = 4 }, 123);
    try chunk.append(allocator, .add, 123);

    try chunk.append(allocator, .ret, 124);

    var vm = VM.init(function);
    defer vm.deinit(allocator);

    try vm.run(allocator, &err_ctx);
}
