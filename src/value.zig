const std = @import("std");

pub const Value = union(enum) {
    int: i32,
    float: f32,
    boolean: bool,
    symbol: []const u8,
    nil,
    obj: *Obj,

    pub fn deinit(self: Value, allocator: std.mem.Allocator) void {
        switch (self) {
            .obj => |o| o.deinit(allocator),
            else => {},
        }
    }

    pub fn borrow(self: Value) Value {
        switch (self) {
            .obj => |o| o.count += 1,
            else => {},
        }
        return self;
    }
};

pub const Obj = struct {
    kind: Kind,
    count: usize,

    pub const Kind = enum {
        string,
    };

    pub fn deinit(self: *Obj, allocator: std.mem.Allocator) void {
        if (self.count == 0) return;

        self.count -= 1;

        if (self.count == 0) switch (self.kind) {
            .string => self.as(String).deinit(allocator),
        };
    }

    pub fn as(self: *Obj, comptime T: type) *T {
        return @alignCast(@fieldParentPtr("obj", self));
    }

    /// Objects which live in the heap and must be garbage collected.
    pub const String = struct {
        obj: Obj,
        bytes: []u8,

        pub fn init(allocator: std.mem.Allocator, v: []const u8) !*String {
            const string_ptr = try allocator.create(String);
            string_ptr.* = String{
                .obj = .{ .kind = .string, .count = 1 },
                .bytes = try allocator.dupe(u8, v),
            };
            return string_ptr;
        }

        pub fn deinit(self: *String, allocator: std.mem.Allocator) void {
            allocator.free(self.bytes);
            allocator.destroy(self);
        }

        pub fn copy(self: String, allocator: std.mem.Allocator) !*String {
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
