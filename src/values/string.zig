const std = @import("std");
const Obj = @import("value.zig").Obj;

pub const String = struct {
    obj: Obj,
    items: []u8,

    const Self = @This();

    pub fn empty(allocator: std.mem.Allocator) !*Self {
        return Self.init(allocator, &.{});
    }

    pub fn init(allocator: std.mem.Allocator, vs: []const u8) !*Self {
        const ptr = try allocator.create(Self);

        ptr.* = Self{
            .obj = Obj.init(.string),
            .items = try allocator.dupe(u8, vs),
        };

        return ptr;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.items);
        allocator.destroy(self);
    }

    pub fn copy(self: Self, allocator: std.mem.Allocator) !*Self {
        return Self.init(allocator, self.items);
    }

    pub fn appendMut(self: *Self, allocator: std.mem.Allocator, vs: []const u8) !void {
        const old_len = self.items.len;
        self.items = try allocator.realloc(self.items, self.items.len + vs.len);
        @memcpy(self.items.ptr + old_len, vs);
    }

    pub fn toString(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        return allocator.dupe(u8, self.items);
    }
};
