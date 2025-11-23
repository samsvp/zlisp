const std = @import("std");

const IArray = @import("array.zig").IArray;
const Value = @import("value.zig").Value;
const Obj = @import("value.zig").Obj;

pub const List = struct {
    obj: Obj,
    vec: IArray,

    pub fn empty(gpa: std.mem.Allocator) !*List {
        return List.init(gpa, &.{});
    }

    pub fn init(allocator: std.mem.Allocator, items: []const Value) !*List {
        const pvec = try allocator.create(List);
        pvec.* = List{
            .obj = Obj.init(.list),
            .vec = try IArray.init(allocator, items),
        };
        return pvec;
    }

    pub fn initNoDupe(allocator: std.mem.Allocator, items: []const Value) !*List {
        const pvec = try allocator.create(List);
        pvec.* = List{
            .obj = Obj.init(.list),
            .vec = try IArray.initNoDupe(items),
        };
        return pvec;
    }

    pub fn deinit(self: *List, allocator: std.mem.Allocator) void {
        self.vec.deinit(allocator);
        allocator.destroy(self);
    }

    pub fn copy(self: List, gpa: std.mem.Allocator) !*List {
        return List.init(gpa, self.vec.items);
    }

    pub fn get(self: List, i: usize) Value {
        return self.vec.get(i);
    }

    pub fn update(self: List, gpa: std.mem.Allocator, i: usize, val: Value) !*List {
        const items = try self.vec.update(gpa, i, val);
        return List.initNoDupe(gpa, items);
    }

    pub fn append(self: List, gpa: std.mem.Allocator, val: Value) !*List {
        const items = try self.vec.append(gpa, val);
        return List.initNoDupe(gpa, items);
    }

    pub fn remove(self: List, gpa: std.mem.Allocator, idx: usize) !*List {
        const items = try self.vec.remove(gpa, idx);
        return List.initNoDupe(gpa, items);
    }

    pub fn swapRemove(self: List, gpa: std.mem.Allocator, idx: usize) !*List {
        const items = try self.vec.swapRemove(gpa, idx);
        return List.initNoDupe(gpa, items);
    }

    pub fn appendMut(self: *List, gpa: std.mem.Allocator, v: Value) !void {
        return self.vec.appendMut(gpa, v);
    }

    pub fn appendManyMut(self: *List, gpa: std.mem.Allocator, vs: []const Value) !void {
        return self.vec.appendManyMut(gpa, vs);
    }

    pub fn toString(self: List, gpa: std.mem.Allocator) ![]const u8 {
        var buffer: std.ArrayList(u8) = .empty;
        defer buffer.deinit(gpa);

        try buffer.append(gpa, '(');
        var writer = buffer.writer(gpa);

        for (self.vec.items) |v| {
            const str = try v.toString(gpa);
            defer gpa.free(str);

            try writer.print("{s}, ", .{str});
        }
        try buffer.append(gpa, ')');
        const owned_str = try gpa.dupe(u8, buffer.items);

        return owned_str;
    }
};
