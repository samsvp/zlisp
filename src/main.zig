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
        \\(def x
        \\  (if (+ 1 2)
        \\      (- 8 2)
        \\      (+ 8 2)))
        \\(def add (fn [a b] (+ a b)))
        \\(def add-2 (fn [x] [] (add x (add 5 10))))
        \\(+ 1 (add-2))
        \\(add "hello " "world")
    ,
        &err_ctx,
    );

    try debug.disassembleChunk(allocator, m_chunk.*, "Compiled chunk");

    const m_function = try Obj.Function.init(allocator, m_chunk, 0, "");
    var m_vm = VM.init(m_function);
    defer m_vm.deinit(allocator);

    m_vm.run(allocator) catch |err| {
        std.debug.print("ERROR: {any}\n", .{err});
        return err;
    };
}
