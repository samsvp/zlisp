const std = @import("std");
const Interpreter = @import("interpreter.zig").Interpreter;
const LispType = @import("types.zig").LispType;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.debug.print("WARNING: memory leaked\n", .{});
    }

    const allocator = gpa.allocator();
    var interpreter = Interpreter.init(allocator);
    defer interpreter.deinit();

    const stdout = std.io.getStdOut().writer();
    _ = stdout;
}

test {
    _ = @import("tests.zig");
}
