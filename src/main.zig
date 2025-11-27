const std = @import("std");
const ln = @import("linenoise");
const Interpreter = @import("interpreter/interpreter.zig").Interpreter;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.debug.print("WARNING: memory leaked\n", .{});
    }

    const allocator = gpa.allocator();

    var buffer: [1024]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &writer.interface;

    var interpreter = try Interpreter.init(allocator);
    defer interpreter.deinit(allocator);

    _ = ln.linenoiseHistoryLoad("history.txt");

    while (ln.linenoise("user> ")) |line| {
        defer ln.linenoiseFree(line);
        const input: []const u8 = std.mem.span(line);
        try interpreter.interpretString(allocator, input, Interpreter.main_file);

        try stdout.print("{s}\n", .{input});
        try stdout.flush();
        _ = ln.linenoiseHistoryAdd(line);
    }

    _ = ln.linenoiseHistorySave("history.txt");
}
