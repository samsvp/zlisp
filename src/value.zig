const std = @import("std");
const pvector = @import("pvector");
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

    pub fn print(v: Value) void {
        switch (v) {
            .obj => |o| switch (o.kind) {
                .string => std.debug.print("{s}", .{o.as(Obj.String).items}),
                .list => std.debug.print("List with len {}", .{o.as(Obj.List).vec.len()}),
                .vector => std.debug.print("Vector with len {}", .{o.as(Obj.PVector).vec.len}),
                .function => std.debug.print("<fn>", .{}),
                .closure => std.debug.print("<closure_fn>", .{}),
                .native_fn => std.debug.print("<native_fn>", .{}),
            },
            .symbol => |s| std.debug.print("{s}", .{s}),
            else => std.debug.print("{}", .{v}),
        }
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
                            // placeholder
                            break :blk false;
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

                            for (0..l_1.len) |i|
                                if (!l_1[i].eql(l_2[i]))
                                    break :blk false;

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

    pub fn toString(self: Value, allocator: std.mem.Allocator) anyerror![]const u8 {
        return switch (self) {
            .obj => |o| switch (o.kind) {
                .string => try std.fmt.allocPrint(allocator, "{s}", .{o.as(Obj.String).items}),
                .list => try o.as(Obj.List).toString(allocator),
                .vector => try o.as(Obj.PVector).toString(allocator),
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

        pub fn toString(self: List, allocator: std.mem.Allocator) ![]const u8 {
            return self.vec.toString(allocator, '(', ')');
        }
    };

    pub const PVector = struct {
        obj: Obj,
        vec: VecT,

        const VecT = pvector.PVector(Value, IArrayFunc);

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

        pub fn toString(self: PVector, gpa: std.mem.Allocator) ![]const u8 {
            return std.fmt.allocPrint(gpa, "PVector with size {}", .{self.vec.len});
        }
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

    pub fn toString(self: Self, gpa: std.mem.Allocator, open_icon: u8, close_icon: u8) ![]const u8 {
        var buffer: std.ArrayList(u8) = .empty;
        try buffer.append(gpa, open_icon);
        const lst = self.items;
        var writer = buffer.writer(gpa);
        for (lst) |v| {
            try writer.print("{s}, ", .{try v.toString(gpa)});
        }
        try buffer.append(gpa, close_icon);
        return buffer.items;
    }
};

pub fn IArrayFunc(comptime _: type) type {
    return IArray;
}
