const std = @import("std");
const ln = @import("linenoise");
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

    var buffer: [1024]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &writer.interface;

    _ = ln.linenoiseHistoryLoad("history.txt");
    while (ln.linenoise("user> ")) |line| {
        defer ln.linenoiseFree(line);
        const input: []const u8 = std.mem.span(line);
        const res = interpreter.rep(input) catch |err| {
            try stdout.print("{any}\n", .{err});
            continue;
        };

        try stdout.print("{s}\n", .{res});
        try stdout.flush();
        _ = ln.linenoiseHistoryAdd(line);
    }

    _ = ln.linenoiseHistorySave("history.txt");
}

test {
    _ = @import("tests.zig");
}
