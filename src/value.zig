const std = @import("std");

pub const Value = union(enum) {
    int: i32,
    float: f32,
    boolean: bool,
    nil,
    obj: Obj,
};

/// Objects which live in the heap and must be garbage collected.
pub const Obj = union(enum) {
    string: String,

    pub const String = struct {
        bytes: []u8,

        pub fn init(allocator: std.mem.Allocator, v: []const u8) !String {
            return .{ .bytes = try allocator.dupe(u8, v) };
        }

        pub fn deinit(self: *String, allocator: std.mem.Allocator) void {
            allocator.free(self.bytes);
        }

        pub fn copy(self: String, allocator: std.mem.Allocator) !String {
            return String.init(allocator, self.bytes);
        }

        pub fn appendMut(self: *String, allocator: std.mem.Allocator, v: []const u8) !void {
            const old_len = self.bytes.len;
            self.bytes = try allocator.realloc(self.bytes, self.bytes.len + v.len);
            @memcpy(self.bytes.ptr + old_len, v);
        }
    };
};

pub fn printValue(v: Value) void {
    switch (v) {
        .obj => |o| switch (o) {
            .string => |s| std.debug.print("{s}", .{s.bytes}),
        },
        else => std.debug.print("{}", .{v}),
    }
}
