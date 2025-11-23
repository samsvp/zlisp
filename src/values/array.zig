const std = @import("std");
const Value = @import("value.zig").Value;

pub const IArray = struct {
    items: []Value,

    const Self = @This();

    pub const empty = Self{ .items = &.{} };

    pub fn init(allocator: std.mem.Allocator, vs: []const Value) !Self {
        const self = Self{
            .items = try allocator.dupe(Value, vs),
        };

        for (self.items) |v| {
            _ = v.borrow();
        }

        return self;
    }

    pub fn initNoDupe(vs: []const Value) Self {
        const self = Self{ .items = vs };
        return self;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        for (self.items) |v| {
            v.deinit(allocator);
        }

        allocator.free(self.items);
    }

    pub fn len(self: Self) usize {
        return self.items.len;
    }

    pub fn get(self: Self, i: usize) Value {
        return self.items[i];
    }

    pub fn update(self: Self, gpa: std.mem.Allocator, idx: usize, val: Value) !Self {
        var items = try gpa.alloc(Value, self.items.len);
        for (self.items, 0..) |v, i| {
            items[i] = if (i != idx) v.borrow() else val.borrow();
        }
        return .{ .items = items };
    }

    pub fn append(self: Self, gpa: std.mem.Allocator, val: Value) !Self {
        const items = try gpa.alloc(Value, self.items.len + 1);

        for (self.items, 0..) |v, i| {
            items[i] = v.borrow();
        }
        items[items.len - 1] = val;

        return .{ .items = items };
    }

    pub fn remove(self: Self, gpa: std.mem.Allocator, idx: usize) !Self {
        var items = try gpa.alloc(Value, self.items.len - 1);

        var items_idx: usize = 0;
        for (0..self.items.len) |i| {
            if (i == idx) {
                continue;
            }

            items[items_idx] = self.items[i].borrow();
            items_idx += 1;
        }

        return .{ .items = items };
    }

    pub fn swapRemove(self: Self, gpa: std.mem.Allocator, idx: usize) !Self {
        var items = try gpa.alloc(Value, self.items.len - 1);

        for (0..self.items.len - 1) |i| {
            const item = if (i == idx) self.items[items.len] else self.items[i];
            items[i] = item.borrow();
        }

        return .{ .items = items };
    }

    pub fn copy(self: Self, gpa: std.mem.Allocator) !*Self {
        return Self.init(gpa, self.items);
    }

    pub fn appendMut(self: *Self, gpa: std.mem.Allocator, v: Value) !void {
        return self.appendManyMut(gpa, &[1]Value{v});
    }

    pub fn appendManyMut(self: *Self, gpa: std.mem.Allocator, vs: []const Value) !void {
        const old_len = self.items.len;

        for (vs) |v| {
            _ = v.borrow();
        }

        self.items = try gpa.realloc(self.items, self.items.len + vs.len);
        @memcpy(self.items.ptr + old_len, vs);
    }

    pub fn toArray(self: Self, gpa: std.mem.Allocator) ![]const Value {
        const arr = try gpa.alloc(Value, self.items.len);
        for (self.items, 0..) |v, i| {
            arr[i] = v.borrow();
        }
        return arr;
    }

    pub fn toBuffer(self: Self, buffer: []Value) void {
        for (self.items, 0..) |v, i| {
            buffer[i] = v.borrow();
        }
    }
};

pub fn IArrayFunc(comptime _: type) type {
    return IArray;
}
