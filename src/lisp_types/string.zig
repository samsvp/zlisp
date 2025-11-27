const std = @import("std");
const Obj = @import("value.zig").Obj;

pub const String = struct {
    obj: Obj,
    items: []u8,

    const Self = @This();

    pub fn empty(gpa: std.mem.Allocator) !*Self {
        return Self.init(gpa, &.{});
    }

    pub fn init(gpa: std.mem.Allocator, vs: []const u8) !*Self {
        const ptr = try gpa.create(Self);

        ptr.* = Self{
            .obj = Obj.init(.string),
            .items = try gpa.dupe(u8, vs),
        };

        return ptr;
    }

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        gpa.free(self.items);
        gpa.destroy(self);
    }

    pub fn copy(self: Self, gpa: std.mem.Allocator) !*Self {
        return Self.init(gpa, self.items);
    }

    pub fn append(self: Self, gpa: std.mem.Allocator, vs: []const u8) !Self {
        const chars = try gpa.alloc(u8, self.items.len + vs.len);
        defer gpa.free(chars);

        @memcpy(chars[0..self.items.len], self.items);
        @memcpy(chars[self.items.len..], vs);
        return init(gpa, chars);
    }

    pub fn appendMut(self: *Self, gpa: std.mem.Allocator, vs: []const u8) !void {
        const old_len = self.items.len;
        self.items = try gpa.realloc(self.items, self.items.len + vs.len);
        @memcpy(self.items.ptr + old_len, vs);
    }

    pub fn toString(self: Self, gpa: std.mem.Allocator) ![]const u8 {
        return gpa.dupe(u8, self.items);
    }
};
