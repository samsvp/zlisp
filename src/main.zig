const std = @import("std");
const Linenoise = @import("linenoize").Linenoise;
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

    var ln = Linenoise.init(allocator);
    defer ln.deinit();

    ln.history.load("history.txt") catch {};
    defer ln.history.save("history.txt") catch |err| {
        std.debug.print("Failed to print history {any}\n", .{err});
    };

    const stdout = std.io.getStdOut().writer();
    while (try ln.linenoise("user> ")) |input| {
        defer allocator.free(input);
        const res = interpreter.rep(input) catch |err| {
            try stdout.print("{any}\n", .{err});
            continue;
        };

        try stdout.print("{s}\n", .{res});
        try ln.history.add(input);
    }
}

test {
    _ = @import("tests.zig");
}
