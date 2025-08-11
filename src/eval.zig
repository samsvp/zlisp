const std = @import("std");
const LispType = @import("types.zig").LispType;

pub fn eval(allocator: std.mem.Allocator, s: LispType) LispType {
    return s.clone(allocator);
}
