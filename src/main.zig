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

    const stdout = std.fs.File.stdout();
    while (ln.linenoise("hello> ")) |c_line| {
        defer ln.linenoiseFree(c_line);

        const line: []const u8 = std.mem.span(c_line);
        _ = try stdout.write(line);
        _ = try stdout.write("\n");
    }
}

test {
    _ = @import("tests.zig");
}
