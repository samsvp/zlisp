const std = @import("std");

pub const Value = f64;

// stub
pub fn printValue(v: Value) void {
    std.debug.print("{}\n", .{v});
}
