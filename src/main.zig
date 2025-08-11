const std = @import("std");
const lib = @import("zlisp_lib");
const errors = @import("errors.zig");
const UserStruct = @import("types.zig").LispType.UserStruct;
const LispType = @import("types.zig").LispType;
const Reader = @import("reader.zig");
const Linenoise = @import("linenoize").Linenoise;
const Interpreter = @import("interpreter.zig").Interpreter;
const eval = @import("eval.zig").eval;

const S = struct {
    a: i32,
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.debug.print("WARNING: memory leaked\n", .{});
    }

    const allocator = gpa.allocator();
    var interpreter = Interpreter.init(gpa.allocator(), 1000);
    defer interpreter.deinit();

    const u = S{ .a = 5 };
    var ptr = UserStruct.init(allocator, u);
    defer ptr.deinit(allocator);
    const maybe_u2 = ptr.record.as(S);
    if (maybe_u2) |m_u2| {
        std.debug.print("{}\n", .{m_u2.a});
    }

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
