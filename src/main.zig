const std = @import("std");
const ln = @import("linenoise");

const VM = @import("vm.zig").VM;
const reader = @import("reader.zig");

pub fn repl(allocator: std.mem.Allocator) !void {
    const hist_file = "history.txt";
    _ = ln.linenoiseHistoryLoad(hist_file);
    defer _ = ln.linenoiseHistorySave(hist_file);

    var buffer: [1024]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &writer.interface;

    var vm = VM.init();
    defer vm.deinit(allocator);

    while (ln.linenoise("user> ")) |line| {
        defer ln.linenoiseFree(line);

        const input: []const u8 = std.mem.span(line);
        var tokens = vm.interpret(allocator, input) catch |err| err_blk: {
            try stdout.print("[ ERROR ] {any}", .{err});
            break :err_blk reader.TokenDataList.empty;
        };
        defer tokens.deinit(allocator);

        for (tokens.items) |t| {
            try stdout.print("{s} ", .{t.str});
        }
        try stdout.print("\n", .{});

        try stdout.flush();
    }
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.debug.print("WARNING: memory leaked\n", .{});
    }

    const allocator = gpa.allocator();

    try repl(allocator);
}
