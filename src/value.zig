const std = @import("std");
const pstructs = @import("pstruct");
const errors = @import("errors.zig");
const Chunk = @import("backend/chunk.zig").Chunk;

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
        closure,
        native_fn,
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
            .closure => self.as(Closure).deinit(allocator),
            .native_fn => self.as(NativeFunction).deinit(allocator),
        };
    }

    pub fn as(self: *Obj, comptime T: type) *T {
        return @alignCast(@fieldParentPtr("obj", self));
    }

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

    pub const PVector = struct {
        obj: Obj,
        vec: VecT,

        pub const VecT = pstructs.PVector(Value, IArrayFunc);

        pub fn init(allocator: std.mem.Allocator, items: []const Value) !*PVector {
            const pvec = try allocator.create(PVector);
            pvec.* = PVector{
                .obj = Obj.init(.vector),
                .vec = try VecT.init(allocator, items),
            };
            return pvec;
        }

        pub fn deinit(self: *PVector, allocator: std.mem.Allocator) void {
            self.vec.deinit(allocator);
            allocator.destroy(self);
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

    pub const PHashMap = struct {
        obj: Obj,
        hash_map: HashMapT,
        const HashMapT = pstructs.Hamt(Value, Value, HashCtx, KVContext.get());

        pub fn init(gpa: std.mem.Allocator, values: []const Value) !*PHashMap {
            const phash_map = try gpa.create(PHashMap);

            var hm = HashMapT.init();
            for (0..values.len / 2) |idx| {
                const i = 2 * idx;
                try hm.assocMut(gpa, values[i], values[i + 1]);
            }

            phash_map.* = PHashMap{
                .obj = Obj.init(.hash_map),
                .hash_map = hm,
            };

            return phash_map;
        }

        pub fn initFrom(gpa: std.mem.Allocator, hm: HashMapT) !*PHashMap {
            const phash_map = try gpa.create(PHashMap);

            phash_map.* = PHashMap{
                .obj = Obj.init(.hash_map),
                .hash_map = hm,
            };

            return phash_map;
        }

        pub fn deinit(self: *PHashMap, gpa: std.mem.Allocator) void {
            self.hash_map.deinit(gpa);
            gpa.destroy(self);
        }

        pub fn toString(self: PHashMap, gpa: std.mem.Allocator) ![]const u8 {
            var buffer: std.ArrayList(u8) = .empty;
            defer buffer.deinit(gpa);

            try buffer.append(gpa, '{');
            var writer = buffer.writer(gpa);

            var iter = self.hash_map.iterator();
            while (iter.next()) |kv| {
                const key_str = try kv.key.toString(gpa);
                defer gpa.free(key_str);

                const val_str = try kv.value.toString(gpa);
                defer gpa.free(val_str);

                try writer.print("{s}: {s}, ", .{ key_str, val_str });
            }
            try buffer.append(gpa, '}');
            const owned_str = try gpa.dupe(u8, buffer.items);

            return owned_str;
        }

        const HashCtx = pstructs.HashContext(Value){
            .eql = Value.eql,
            .hash = Value.hash,
        };

        const KV = pstructs.KV(Value, Value);

        const KVContext = struct {
            fn init(_: std.mem.Allocator, v: Value, k: Value) !KV {
                return .{ .key = v.borrow(), .value = k.borrow() };
            }

            fn deinit(gpa: std.mem.Allocator, kv: *KV) void {
                kv.key.deinit(gpa);
                kv.value.deinit(gpa);
            }

            fn clone(gpa: std.mem.Allocator, kv: *KV) !KV {
                return KVContext.init(gpa, kv.key, kv.value);
            }

            fn get() pstructs.KVContext(Value, Value) {
                return .{
                    .init = KVContext.init,
                    .deinit = KVContext.deinit,
                    .clone = KVContext.clone,
                };
            }
        };
    };

    pub const Function = struct {
        obj: Obj,
        chunk: *Chunk,
        arity: u32,
        is_variadic: bool,
        help: []const u8,

        pub fn init(
            allocator: std.mem.Allocator,
            chunk: *Chunk,
            arity: u8,
            is_variadic: bool,
            help: []const u8,
        ) !*Function {
            const func = try allocator.create(Function);
            func.* = Function{
                .obj = Obj.init(.function),
                .chunk = chunk,
                .arity = arity,
                .is_variadic = is_variadic,
                .help = help,
            };
            return func;
        }

        pub fn deinit(self: *Function, allocator: std.mem.Allocator) void {
            self.chunk.deinit(allocator);
            allocator.destroy(self.chunk);
            allocator.destroy(self);
        }

        pub fn native(allocator: std.mem.Allocator, arity: u32, is_variadic: bool, help: []const u8) !*Function {
            var chunk = try allocator.create(Chunk);
            chunk.* = .empty;
            try chunk.append(allocator, .ret, 0);

            const func = try allocator.create(Function);
            func.* = Function{
                .obj = Obj.init(.function),
                .arity = arity,
                .is_variadic = is_variadic,
                .chunk = chunk,
                .help = help,
            };
            return func;
        }
    };

    pub const Closure = struct {
        obj: Obj,
        function: *Function,
        args: []const Value,

        pub fn init(allocator: std.mem.Allocator, func: *Function, args: []Value) !*Closure {
            const closure = try allocator.create(Closure);
            closure.* = Closure{
                .obj = Obj.init(.closure),
                .function = func,
                .args = try allocator.dupe(Value, args),
            };

            func.obj.count += 1;
            return closure;
        }

        pub fn deinit(self: *Closure, allocator: std.mem.Allocator) void {
            defer allocator.destroy(self);
            defer allocator.free(self.args);

            self.function.deinit(allocator);
            for (self.args) |*v| {
                v.deinit(allocator);
            }
        }
    };

    pub const NativeFunction = struct {
        obj: Obj,
        native_fn: NativeFn,
        function: *Function,

        pub fn init(
            allocator: std.mem.Allocator,
            func: NativeFn,
            arity: u8,
            is_variadic: bool,
            help: []const u8,
        ) !*NativeFunction {
            const native_func = try allocator.create(NativeFunction);
            native_func.* = NativeFunction{
                .obj = Obj.init(.native_fn),
                .native_fn = func,
                .function = try Function.native(allocator, arity, is_variadic, help),
            };
            return native_func;
        }

        pub fn deinit(self: *NativeFunction, allocator: std.mem.Allocator) void {
            defer allocator.destroy(self);

            self.function.deinit(allocator);
        }
    };

    pub const NativeFn = *const fn (
        allocator: std.mem.Allocator,
        args: []const Value,
        err_ctx: *errors.Ctx,
    ) anyerror!Value;
};

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
