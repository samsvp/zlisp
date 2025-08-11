const std = @import("std");
const lib = @import("zlisp_lib");
const LispType = @import("types.zig").LispType;
const Reader = @import("reader.zig");
const Linenoise = @import("linenoize").Linenoise;
const eval = @import("eval.zig").eval;

fn print(allocator: std.mem.Allocator, s: LispType) []const u8 {
    return s.toStringFull(allocator) catch unreachable;
}

fn rep(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var val = try Reader.readStr(
        allocator,
        s,
    );
    defer val.deinit(allocator);

    var ret = eval(allocator, val);
    defer ret.deinit(allocator);

    return ret.toStringFull(allocator);
}
pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.debug.print("WARNING: memory leaked\n", .{});
    }

    const allocator = gpa.allocator();

    var ln = Linenoise.init(allocator);
    defer ln.deinit();

    ln.history.load("history.txt") catch {};
    defer ln.history.save("history.txt") catch |err| {
        std.debug.print("Failed to print history {any}\n", .{err});
    };

    const stdout = std.io.getStdOut().writer();
    while (try ln.linenoise("user> ")) |input| {
        defer allocator.free(input);
        const res = rep(allocator, input) catch |err| {
            try stdout.print("{any}\n", .{err});
            continue;
        };
        defer allocator.free(res);

        try stdout.print("{s}\n", .{res});
        try ln.history.add(input);
    }
}
