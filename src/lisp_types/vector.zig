const std = @import("std");

const pstructs = @import("pstruct");
const Value = @import("value.zig").Value;
const Obj = @import("value.zig").Obj;
const IArrayFunc = @import("iarray.zig").IArrayFunc;

/// A persistent vector of values. It owns the values inside the arrays passed to it.
pub const PVector = struct {
    obj: Obj,
    vec: VecT,

    pub const VecT = pstructs.PVector(Value, IArrayFunc);

    pub fn init(gpa: std.mem.Allocator, items: []const Value) !*PVector {
        const pvec = try gpa.create(PVector);
        pvec.* = PVector{
            .obj = Obj.init(.vector),
            .vec = try VecT.init(gpa, items),
        };
        return pvec;
    }

    pub fn deinit(self: *PVector, gpa: std.mem.Allocator) void {
        var iter = self.vec.iterator();
        while (iter.nextPtr()) |v| {
            v.deinit(gpa);
        }

        self.vec.deinit(gpa);
        gpa.destroy(self);
    }

    pub fn get(self: PVector, i: usize) Value {
        return self.vec.get(i);
    }

    pub fn append(self: *PVector, gpa: std.mem.Allocator, val: Value) !*PVector {
        const pvec = try gpa.create(PVector);
        pvec.* = PVector{
            .obj = Obj.init(.vector),
            .vec = try self.vec.append(gpa, val),
        };
        return pvec;
    }

    pub fn add(self: PVector, gpa: std.mem.Allocator, others: []VecT) !*PVector {
        const new_vec = try self.vec.concat(gpa, others);
        const pvec = try gpa.create(PVector);
        pvec.* = PVector{
            .obj = Obj.init(.vector),
            .vec = new_vec,
        };
        return pvec;
    }

    pub fn toString(self: PVector, gpa: std.mem.Allocator) ![]const u8 {
        var buffer: std.ArrayList(u8) = .empty;
        defer buffer.deinit(gpa);

        try buffer.append(gpa, '[');
        var writer = buffer.writer(gpa);

        var iter = self.vec.iterator();
        while (iter.next()) |v| {
            const str = try v.toString(gpa);
            defer gpa.free(str);

            try writer.print("{s}, ", .{str});
        }
        try buffer.append(gpa, ']');
        const owned_str = try gpa.dupe(u8, buffer.items);

        return owned_str;
    }
};
