const std = @import("std");
const errors = @import("errors.zig");
const reader = @import("reader.zig");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("chunk.zig").OpCode;

pub fn compile(allocator: std.mem.Allocator, source: []const u8, err_ctx: *errors.Ctx) !Chunk {
    _ = allocator;
    _ = source;
    _ = err_ctx;

    return error.NotImplemented;
}
