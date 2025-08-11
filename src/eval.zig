const std = @import("std");
const ZType = @import("types.zig").ZType;

pub fn eval(allocator: std.mem.Allocator, s: ZType) ZType {
    return s.clone(allocator);
}
