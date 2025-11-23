const std = @import("std");
const pstructs = @import("pstruct");
const Chunk = @import("../backend/chunk.zig").Chunk;
const string = @import("string.zig");
const phash_map = @import("hash_map.zig");
const pvector = @import("vector.zig");
const lists = @import("list.zig");
const f = @import("functions.zig");
const IArray = @import("array.zig").IArray;
const IArrayFunc = @import("array.zig").IArrayFunc;

pub const Value = union(enum) {
    int: i32,
    float: f32,
    boolean: bool,
    symbol: []const u8,
    nil,
    obj: *Obj,

    pub const True = Value{ .boolean = true };
    pub const False = Value{ .boolean = false };

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

    pub fn eql(a: Value, b: Value) bool {
        return switch (a) {
            .int => |i_1| switch (b) {
                .int => |i_2| i_1 == i_2,
                else => false,
            },
            .float => |f_1| switch (b) {
                .float => |f_2| f_1 == f_2,
                else => false,
            },
            .boolean => |b_1| switch (b) {
                .boolean => |b_2| b_1 == b_2,
                else => false,
            },
            .symbol => |s_1| switch (b) {
                .symbol => |s_2| std.mem.eql(u8, s_1, s_2),
                else => false,
            },
            .nil => switch (b) {
                .nil => true,
                else => false,
            },
            .obj => |o_1| switch (b) {
                .obj => |o_2| switch (o_1.kind) {
                    .string => switch (o_2.kind) {
                        .string => std.mem.eql(
                            u8,
                            o_1.as(Obj.String).items,
                            o_2.as(Obj.String).items,
                        ),
                        else => false,
                    },
                    .vector => switch (o_2.kind) {
                        .vector => blk: {
                            const vec_1 = o_1.as(Obj.PVector).vec;
                            const vec_2 = o_2.as(Obj.PVector).vec;
                            if (vec_1.len != vec_2.len) {
                                break :blk false;
                            }

                            var v1_iter = vec_1.iterator();
                            var v2_iter = vec_2.iterator();
                            const res = for (0..vec_1.len) |_| {
                                const v1 = v1_iter.next().?;
                                const v2 = v2_iter.next().?;
                                if (v1.eql(v2))
                                    break false;
                            } else true;

                            break :blk res;
                        },
                        else => false,
                    },
                    .list => switch (o_2.kind) {
                        .list => blk: {
                            const l_1 = o_1.as(Obj.List).vec.items;
                            const l_2 = o_2.as(Obj.List).vec.items;
                            if (l_1.len != l_2.len) {
                                break :blk false;
                            }

                            const res = for (0..l_1.len) |i| {
                                if (!l_1[i].eql(l_2[i]))
                                    break false;
                            } else true;

                            break :blk res;
                        },
                        else => false,
                    },
                    .hash_map => switch (o_2.kind) {
                        .hash_map => blk: {
                            var hm_1 = o_1.as(Obj.PHashMap).hash_map;
                            var hm_2 = o_2.as(Obj.PHashMap).hash_map;
                            if (hm_1.size != hm_2.size) {
                                break :blk false;
                            }

                            var iter = hm_1.iterator();
                            while (iter.next()) |kv| {
                                if (hm_2.get(kv.key)) |v_2| {
                                    if (!kv.value.eql(v_2)) {
                                        break :blk false;
                                    }
                                } else break :blk false;
                            }
                            break :blk true;
                        },
                        else => false,
                    },
                    .function => false,
                    .closure => false,
                    .native_fn => false,
                },
                else => false,
            },
        };
    }

    pub fn hash(a: Value) u32 {
        var h: std.hash.Wyhash = .init(0);

        const b = switch (a) {
            inline .int, .float, .boolean => |v| std.mem.asBytes(&v),
            .symbol => |s| s,
            .nil => &.{},
            .obj => switch (a.obj.kind) {
                .string => a.obj.as(Obj.String).items,
                .list => std.mem.asBytes(&a.obj.as(Obj.List).vec.items),
                .vector => std.mem.asBytes(&a.obj.as(Obj.PVector).vec),
                else => std.mem.asBytes(&a.obj),
            },
        };

        h.update(b);
        return @intCast(h.final() & 0xFFFFFFFF);
    }

    pub fn toString(self: Value, allocator: std.mem.Allocator) anyerror![]const u8 {
        return switch (self) {
            .obj => |o| switch (o.kind) {
                .string => try std.fmt.allocPrint(allocator, "{s}", .{o.as(Obj.String).items}),
                .list => try o.as(Obj.List).toString(allocator),
                .vector => try o.as(Obj.PVector).toString(allocator),
                .hash_map => try o.as(Obj.PHashMap).toString(allocator),
                .function => try std.fmt.allocPrint(allocator, "<fn>", .{}),
                .closure => try std.fmt.allocPrint(allocator, "<closure_fn>", .{}),
                .native_fn => try std.fmt.allocPrint(allocator, "<native_fn>", .{}),
            },
            .symbol => |s| try std.fmt.allocPrint(allocator, "{s}", .{s}),
            .nil => try std.fmt.allocPrint(allocator, "nil", .{}),
            inline else => |v| try std.fmt.allocPrint(allocator, "{}", .{v}),
        };
    }
};

pub const Obj = struct {
    kind: Kind,
    count: usize,

    pub const Kind = enum {
        string,
        list,
        vector,
        hash_map,
        function,
        native_fn,
        closure,
    };

    pub fn init(kind: Kind) Obj {
        return .{ .kind = kind, .count = 1 };
    }

    pub fn deinit(self: *Obj, allocator: std.mem.Allocator) void {
        if (self.count == 0) return;

        self.count -= 1;

        if (self.count == 0) switch (self.kind) {
            .string => self.as(String).deinit(allocator),
            .list => self.as(List).deinit(allocator),
            .vector => self.as(PVector).deinit(allocator),
            .hash_map => self.as(PHashMap).deinit(allocator),
            .function => self.as(Function).deinit(allocator),
            .closure => self.as(f.Closure).deinit(allocator),
            .native_fn => self.as(f.Native).deinit(allocator),
        };
    }

    pub fn as(self: *Obj, comptime T: type) *T {
        return @alignCast(@fieldParentPtr("obj", self));
    }

    pub const String = string.String;
    pub const List = lists.List;
    pub const PVector = pvector.PVector;
    pub const PHashMap = phash_map.PHashMap;
    pub const Function = f.Function;
    pub const Closure = f.Closure;
    pub const NativeFunction = f.Native;
};
