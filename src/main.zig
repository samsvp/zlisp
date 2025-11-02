const std = @import("std");
const ln = @import("linenoise");

const errors = @import("errors.zig");
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

    var err_ctx = errors.Ctx{ .msg = "" };
    defer err_ctx.deinit(allocator);

    while (ln.linenoise("user> ")) |line| {
        defer ln.linenoiseFree(line);

        const input: []const u8 = std.mem.span(line);
        vm.interpret(allocator, input, &err_ctx) catch |err| {
            try stdout.print("[ ERROR ] {any}\n\t{s}\n", .{ err, err_ctx.msg });
            try stdout.flush();
            continue;
        };
        try stdout.print("{s}\n", .{line});

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
