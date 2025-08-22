const std = @import("std");
const LispType = @import("types.zig").LispType;
const Interpreter = @import("interpreter.zig").Interpreter;

test "math ops" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.debug.print("WARNING: memory leaked\n", .{});
    }

    const allocator = gpa.allocator();

    var interpreter = Interpreter.init(allocator);
    defer interpreter.deinit();

    for ([_][]const u8{
        "src/test-files/eval.lisp",
        "src/test-files/if_fn_do.lisp",
        "src/test-files/tco.lisp",
    }) |filename| {
        var file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const buffer = try allocator.alloc(u8, file_size);
        defer allocator.free(buffer);

        _ = try file.readAll(buffer);

        var it = std.mem.splitScalar(u8, buffer, '\n');
        var i: usize = 0;
        while (it.next()) |line| {
            i += 1;
            if (line.len == 0) {
                continue;
            }

            const ret = interpreter.re(line) catch {
                std.debug.print("ERR file {s} line {}: {s}\n", .{ filename, i, interpreter.err_ctx.buffer.items });
                try std.testing.expect(false);
                return;
            };
            std.testing.expect(ret.eql(LispType.lisp_true)) catch {
                const str = try ret.toStringFull(allocator);
                defer allocator.free(str);
                std.debug.print("ERR file {s} line {}: return value {s}\n", .{ filename, i, str });
                try std.testing.expect(false);
            };
        }
    }
}
