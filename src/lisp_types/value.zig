const std = @import("std");
const RefCounter = @import("pstruct").RefCounter;

const string = @import("string.zig");
const phash_map = @import("hash_map.zig");
const pvector = @import("vector.zig");
const lists = @import("list.zig");
const f = @import("function.zig");

pub const AST = struct {
    meta: MetaData,
    value: Value,
};

pub const MetaData = struct {
    line: usize,
    col: usize,
    file_id: usize,
};

pub const NameSet = struct {
    names: std.StringHashMapUnmanaged(void) = .empty,

    pub fn deinit(self: *NameSet, gpa: std.mem.Allocator) void {
        var keys_iter = self.names.keyIterator();
        while (keys_iter.next()) |key| {
            gpa.free(key.*);
        }

        self.names.deinit(gpa);
    }

    pub fn getOrPut(self: *NameSet, gpa: std.mem.Allocator, name: []const u8) ![]const u8 {
        if (self.names.getKey(name)) |key| {
            return key;
        }

        const owned_name = try gpa.dupe(u8, name);
        try self.names.put(gpa, owned_name, {});
        return owned_name;
    }
};

pub const Value = union(enum) {
    int: i32,
    float: f32,
    boolean: bool,
    symbol: []const u8,
    keyword: []const u8,
    nil,
    obj: RefCounter(*Obj).Ref,

    pub const True: Value = .{ .boolean = true };
    pub const False: Value = .{ .boolean = false };
    pub const Nil: Value = .nil;

    pub fn initObj(gpa: std.mem.Allocator, obj: *Obj) !Value {
        return .{ .obj = try RefCounter(*Obj).init(gpa, obj) };
    }

    pub fn initSymbol(gpa: std.mem.Allocator, symbol_set: *NameSet, symbol: []const u8) !Value {
        return .{ .symbol = try symbol_set.getOrPut(gpa, symbol) };
    }

    pub fn initKeyword(gpa: std.mem.Allocator, keyword_set: *NameSet, keyword: []const u8) !Value {
        return .{ .symbol = try keyword_set.getOrPut(gpa, keyword) };
    }

    pub fn deinit(self: *Value, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .obj => |*o| o.release(gpa),
            else => {},
        }
    }

    pub fn borrow(self: Value) !Value {
        return switch (self) {
            .obj => |o| .{ .obj = try o.borrow() },
            else => self,
        };
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
            .keyword => |k_1| switch (b) {
                .keyword => |k_2| std.mem.eql(u8, k_1, k_2),
                else => false,
            },
            .nil => switch (b) {
                .nil => true,
                else => false,
            },
            .obj => |o_1_ref| switch (b) {
                .obj => |o_2_ref| obj_blk: {
                    const o_1 = o_1_ref.getUnwrap();
                    const o_2 = o_2_ref.getUnwrap();

                    if (o_1.kind != o_2.kind) {
                        break :obj_blk false;
                    }

                    break :obj_blk switch (o_1.kind) {
                        .string => std.mem.eql(
                            u8,
                            o_1.as(Obj.String).items,
                            o_2.as(Obj.String).items,
                        ),
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
                        .list => blk: {
                            const l_1 = o_1.as(Obj.List).values();
                            const l_2 = o_2.as(Obj.List).values();
                            if (l_1.len != l_2.len) {
                                break :blk false;
                            }

                            const res = for (0..l_1.len) |i| {
                                if (!l_1[i].eql(l_2[i]))
                                    break false;
                            } else true;

                            break :blk res;
                        },
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
                        .function => false,
                    };
                },
                else => false,
            },
        };
    }

    pub fn hash(a: Value) u32 {
        var h: std.hash.Wyhash = .init(0);

        const b = switch (a) {
            inline .int, .float, .boolean => |v| std.mem.asBytes(&v),
            .symbol, .keyword => |s| s,
            .nil => &.{},
            .obj => |o_ref| blk: {
                const o = o_ref.getUnwrap();
                break :blk switch (o.kind) {
                    .string => o.as(Obj.String).items,
                    .list => std.mem.asBytes(&o.as(Obj.List).values()),
                    .vector => std.mem.asBytes(&o.as(Obj.PVector).vec),
                    else => std.mem.asBytes(&o),
                };
            },
        };

        h.update(b);
        return @truncate(h.final());
    }

    pub fn toString(self: Value, gpa: std.mem.Allocator) anyerror![]const u8 {
        return switch (self) {
            .obj => |o_ref| obj_blk: {
                const o = o_ref.getUnwrap();
                break :obj_blk switch (o.kind) {
                    .string => try std.fmt.allocPrint(gpa, "{s}", .{o.as(Obj.String).items}),
                    .list => try o.as(Obj.List).toString(gpa),
                    .vector => try o.as(Obj.PVector).toString(gpa),
                    .hash_map => try o.as(Obj.PHashMap).toString(gpa),
                    .function => @panic("not implemented"),
                };
            },
            .symbol, .keyword => |s| try std.fmt.allocPrint(gpa, "{s}", .{s}),
            .nil => try std.fmt.allocPrint(gpa, "nil", .{}),
            inline else => |v| try std.fmt.allocPrint(gpa, "{}", .{v}),
        };
    }
};

/// Heap allocated values.
pub const Obj = struct {
    kind: Kind,

    pub const Kind = enum {
        string,
        list,
        vector,
        hash_map,
        function,
    };

    pub fn init(kind: Kind) Obj {
        return .{ .kind = kind };
    }

    pub fn deinit(self: *Obj, gpa: std.mem.Allocator) void {
        switch (self.kind) {
            .string => self.as(String).deinit(gpa),
            .list => self.as(List).deinit(gpa),
            .vector => self.as(PVector).deinit(gpa),
            .hash_map => self.as(PHashMap).deinit(gpa),
            .function => self.as(Function).deinit(gpa),
        }
    }

    pub fn as(self: *Obj, comptime T: type) *T {
        return @alignCast(@fieldParentPtr("obj", self));
    }

    pub const String = string.String;
    pub const List = lists.List;
    pub const PVector = pvector.PVector;
    pub const PHashMap = phash_map.PHashMap;
    pub const Function = f.Fn;
};
