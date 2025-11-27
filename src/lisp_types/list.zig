const std = @import("std");

const AST = @import("value.zig").AST;
const MetaData = @import("value.zig").MetaData;
const Value = @import("value.zig").Value;
const Obj = @import("value.zig").Obj;
const MultiIVector = @import("pstruct").MultiIVector;

/// An immutable list of AST values.
/// Because lists are also source code, we must carry meta data with it.
pub const List = struct {
    obj: Obj,
    vec: MultiIVector(AST),

    pub fn empty(gpa: std.mem.Allocator) !*List {
        return List.init(gpa, &.{});
    }

    pub fn init(gpa: std.mem.Allocator, items: []const AST) !*List {
        const pvec = try gpa.create(List);
        pvec.* = List{
            .obj = Obj.init(.list),
            .vec = try MultiIVector(AST).init(gpa, items),
        };
        return pvec;
    }

    pub fn initFromVec(gpa: std.mem.Allocator, vec: MultiIVector(AST)) !*List {
        const pvec = try gpa.create(List);
        pvec.* = List{
            .obj = Obj.init(.list),
            .vec = vec,
        };
        return pvec;
    }

    pub fn deinit(self: *List, gpa: std.mem.Allocator) void {
        for (self.values()) |*v| {
            v.deinit(gpa);
        }

        self.vec.deinit(gpa);
        gpa.destroy(self);
    }

    pub fn copy(self: List, gpa: std.mem.Allocator) !*List {
        return List.init(gpa, self.vec.items);
    }

    pub fn get(self: List, i: usize) AST {
        return self.vec.get(i);
    }

    pub fn getValue(self: List, i: usize) Value {
        return self.vec.getField(i, .value);
    }

    pub fn getMeta(self: List, i: usize) MetaData {
        return self.vec.getField(i, .meta);
    }

    pub fn values(self: List) []Value {
        return self.vec.array.items(.value);
    }

    pub fn metas(self: List) []MetaData {
        return self.vec.array.items(.meta);
    }

    pub fn update(self: List, gpa: std.mem.Allocator, i: usize, val: AST) !*List {
        const items = try self.vec.update(gpa, i, val);
        return List.initFromVec(gpa, items);
    }

    pub fn append(self: List, gpa: std.mem.Allocator, val: AST) !*List {
        const items = try self.vec.append(gpa, val);
        return List.initFromVec(gpa, items);
    }

    pub fn remove(self: List, gpa: std.mem.Allocator, idx: usize) !*List {
        const items = try self.vec.remove(gpa, idx);
        return List.initFromVec(gpa, items);
    }

    pub fn swapRemove(self: List, gpa: std.mem.Allocator, idx: usize) !*List {
        const items = try self.vec.swapRemove(gpa, idx);
        return List.initFromVec(gpa, items);
    }

    pub fn toString(self: List, gpa: std.mem.Allocator) ![]const u8 {
        var buffer: std.ArrayList(u8) = .empty;
        defer buffer.deinit(gpa);

        try buffer.append(gpa, '(');
        var writer = buffer.writer(gpa);

        for (self.values()) |v| {
            const str = try v.toString(gpa);
            defer gpa.free(str);

            try writer.print("{s}, ", .{str});
        }
        try buffer.append(gpa, ')');
        const owned_str = try gpa.dupe(u8, buffer.items);

        return owned_str;
    }
};
