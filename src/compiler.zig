const std = @import("std");
const reader = @import("reader.zig");

pub fn compile(allocator: std.mem.Allocator, source: []const u8) !reader.TokenDataList {
    return reader.tokenize(allocator, source);
}
