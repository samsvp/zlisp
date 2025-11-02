const std = @import("std");

pub const Value = union(enum) {
    int: i32,
    float: f32,
    boolean: bool,
    nil,
    symbol: String,

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .symbol => |*s| s.deinit(allocator),
            .int, .float, .boolean, .nil => {},
        }
    }

    pub const String = struct {
        bytes: []const u8,

        pub fn init(allocator: std.mem.Allocator, v: []const u8) !String {
            return .{ .bytes = try allocator.dupe(u8, v) };
        }

        pub fn deinit(self: *String, allocator: std.mem.Allocator) void {
            allocator.free(self.bytes);
        }
    };
};

// stub
pub fn printValue(v: Value) void {
    std.debug.print("{}", .{v});
}
