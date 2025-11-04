const std = @import("std");

pub const Value = union(enum) {
    int: i32,
    float: f32,
    boolean: bool,
    nil,
    obj: *const Obj,
};

pub const Obj = struct {
    kind: Kind,

    pub const Kind = enum {
        string,
    };

    pub fn as(self: *const Obj, comptime T: type) *const T {
        return @alignCast(@fieldParentPtr("obj", self));
    }

    /// Objects which live in the heap and must be garbage collected.
    pub const String = struct {
        obj: Obj,
        bytes: []u8,

        pub fn init(allocator: std.mem.Allocator, v: []const u8) !String {
            return .{
                .obj = .{ .kind = .string },
                .bytes = try allocator.dupe(u8, v),
            };
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
        .obj => |o| switch (o.kind) {
            .string => std.debug.print("{s}", .{o.as(Obj.String).bytes}),
        },
        else => std.debug.print("{}", .{v}),
    }
}
