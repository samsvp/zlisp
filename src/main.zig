const std = @import("std");
const ln = @import("linenoise");

const errors = @import("errors.zig");
const VM = @import("backend/vm.zig").VM;
const Obj = @import("value.zig").Obj;
const compiler = @import("frontend/compiler.zig");
const debug = @import("backend/debug.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var err_ctx = errors.Ctx.empty;
    defer err_ctx.deinit(allocator);

    std.debug.print("\nCompiled\n", .{});
    const m_chunk = try compiler.compile(
        allocator,
        \\(def add-3 (fn [&xs] (+ &xs [1 "2" 3])))
        \\(add-3 "12")
        \\nil
    ,
        &err_ctx,
    );

    try debug.disassembleChunk(allocator, m_chunk.*, "Compiled chunk");

    var m_function = try Obj.Function.init(allocator, m_chunk, 0, false, "");
    defer m_function.deinit(allocator);

    var m_vm = VM.init(m_function);
    defer m_vm.deinit(allocator);

    m_vm.run(allocator) catch |err| {
        std.debug.print("ERROR: {any}\n", .{err});
        return err;
    };
}
