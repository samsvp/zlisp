const std = @import("std");
const ln = @import("linenoise");

const Chunk = @import("chunk.zig").Chunk;
const errors = @import("errors.zig");
const VM = @import("vm.zig").VM;
const reader = @import("reader.zig");
const Obj = @import("value.zig").Obj;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.debug.print("WARNING: memory leaked\n", .{});
    }

    const allocator = gpa.allocator();

    var vm = VM.init();
    defer vm.deinit(allocator);

    var err_ctx = errors.Ctx{ .msg = "" };
    defer err_ctx.deinit(allocator);

    var chunk = Chunk.empty;
    defer chunk.deinit(allocator);

    var s0 = try Obj.String.init(allocator, "wow man!");

    try chunk.emitConstant(allocator, .{ .obj = &s0.obj }, 10);
    try chunk.emitDefGlobal(allocator, "my_var", 10);

    try chunk.emitConstant(allocator, .{ .float = 1.2 }, 123);
    try chunk.emitConstant(allocator, .{ .float = 3.4 }, 123);
    try chunk.emitConstant(allocator, .{ .int = 2 }, 123);
    try chunk.append(allocator, .add, 123);

    try chunk.emitConstant(allocator, .{ .float = 5.6 }, 123);
    try chunk.emitConstant(allocator, .{ .int = 2 }, 123);
    try chunk.append(allocator, .divide, 123);

    try chunk.emitConstant(allocator, .{ .int = 1 }, 123);
    try chunk.append(allocator, .subtract, 123);

    var s3 = try Obj.String.init(allocator, "!");
    var s2 = try Obj.String.init(allocator, "world");
    var s1 = try Obj.String.init(allocator, "hello ");
    try chunk.emitConstant(allocator, .{ .obj = &s3.obj }, 123);
    try chunk.emitConstant(allocator, .{ .obj = &s2.obj }, 123);
    try chunk.emitConstant(allocator, .{ .obj = &s1.obj }, 123);
    try chunk.emitGetGlobal(allocator, "my_var", 123);
    try chunk.emitConstant(allocator, .{ .int = 4 }, 123);
    try chunk.append(allocator, .add, 123);

    try chunk.append(allocator, .ret, 124);

    vm.chunk = chunk;
    vm.ip = chunk.code.items.ptr;
    try vm.run(allocator, &err_ctx);
}
