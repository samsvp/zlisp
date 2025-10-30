const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const debug = @import("debug.zig");

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

    var chunk = Chunk.empty;
    defer chunk.deinit(allocator);

    try chunk.append(allocator, .ret, 123);

    for (0..280) |_| {
        const i = try chunk.addConstant(allocator, 1.2);

        if (i <= 255) {
            try chunk.append(allocator, .constant, 123);
            try chunk.code.append(allocator, @intCast(i));
        } else {
            try chunk.append(allocator, .constant_long, 123);
            const int_16: u16 = @intCast(i);
            const bytes = std.mem.toBytes(int_16);
            try chunk.code.appendSlice(allocator, &bytes);
        }
    }

    try debug.disassembleChunk(chunk, "Test", stdout);
}
