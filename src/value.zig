const std = @import("std");
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
                .list => std.debug.print("List with len {}", .{o.as(Obj.List).items.len}),
                .vector => std.debug.print("Vector with len {}", .{o.as(Obj.Vector).items.len}),
                .function => std.debug.print("<fn>", .{}),
                .closure => std.debug.print("<fn>", .{}),
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
                            const l_1 = o_1.as(Obj.Vector).items;
                            const l_2 = o_2.as(Obj.Vector).items;
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
                    .list => switch (o_2.kind) {
                        .list => blk: {
                            const l_1 = o_1.as(Obj.List).items;
                            const l_2 = o_2.as(Obj.List).items;
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
                .list => try o.as(Obj.List).toString(allocator, '(', ')'),
                .vector => try o.as(Obj.Vector).toString(allocator, '[', ']'),
                .function => try std.fmt.allocPrint(allocator, "<fn>", .{}),
                .closure => try std.fmt.allocPrint(allocator, "<fn>", .{}),
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
            .vector => self.as(Vector).deinit(allocator),
            .function => self.as(Function).deinit(allocator),
            .closure => self.as(Closure).deinit(allocator),
            .native_fn => self.as(NativeFunction).deinit(allocator),
        };
    }

    pub fn as(self: *Obj, comptime T: type) *T {
        return @alignCast(@fieldParentPtr("obj", self));
    }

    pub fn Array(comptime T: type, kind: Obj.Kind) type {
        return struct {
            obj: Obj,
            items: []T,

            const Self = @This();

            pub fn empty(allocator: std.mem.Allocator) !*Self {
                return Self.init(allocator, &.{});
            }

            pub fn init(allocator: std.mem.Allocator, vs: []const T) !*Self {
                const ptr = try allocator.create(Self);

                ptr.* = Self{
                    .obj = Obj.init(kind),
                    .items = try allocator.dupe(T, vs),
                };

                if (T == Value) for (ptr.items) |v| {
                    _ = v.borrow();
                };

                return ptr;
            }

            pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
                if (T == Value) for (self.items) |v| {
                    v.deinit(allocator);
                };

                allocator.free(self.items);
                allocator.destroy(self);
            }

            pub fn copy(self: Self, allocator: std.mem.Allocator) !*Self {
                return Self.init(allocator, self.items);
            }

            pub fn appendMut(self: *Self, allocator: std.mem.Allocator, v: T) !void {
                return self.appendManyMut(allocator, &[1]T{v});
            }

            pub fn appendManyMut(self: *Self, allocator: std.mem.Allocator, vs: []const T) !void {
                const old_len = self.items.len;

                if (T == Value) for (vs) |v| {
                    _ = v.borrow();
                };

                self.items = try allocator.realloc(self.items, self.items.len + vs.len);
                @memcpy(self.items.ptr + old_len, vs);
            }

            pub fn toString(self: Self, allocator: std.mem.Allocator, open_icon: u8, close_icon: u8) ![]const u8 {
                var buffer: std.ArrayList(u8) = .empty;
                try buffer.append(allocator, open_icon);
                const lst = self.items;
                var writer = buffer.writer(allocator);
                for (lst) |v| {
                    try writer.print("{s}, ", .{try v.toString(allocator)});
                }
                try buffer.append(allocator, close_icon);
                return buffer.items;
            }
        };
    }

    pub const String = Array(u8, .string);
    pub const List = Array(Value, .list);
    pub const Vector = Array(Value, .vector);

    pub const Function = struct {
        obj: Obj,
        arity: u32,
        chunk: *Chunk,
        help: []const u8,

        pub fn init(allocator: std.mem.Allocator, chunk: *Chunk, arity: u8, help: []const u8) !*Function {
            const func = try allocator.create(Function);
            func.* = Function{
                .obj = Obj.init(.function),
                .arity = arity,
                .chunk = chunk,
                .help = help,
            };
            return func;
        }

        pub fn deinit(self: *Function, allocator: std.mem.Allocator) void {
            self.chunk.deinit(allocator);
            allocator.destroy(self.chunk);
            allocator.destroy(self);
        }

        pub fn native(allocator: std.mem.Allocator, arity: u32, help: []const u8) !*Function {
            var chunk = try allocator.create(Chunk);
            chunk.* = .empty;
            try chunk.append(allocator, .ret, 0);

            const func = try allocator.create(Function);
            func.* = Function{
                .obj = Obj.init(.function),
                .arity = arity,
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
            return closure;
        }

        pub fn deinit(self: *Closure, allocator: std.mem.Allocator) void {
            self.function.deinit(allocator);
            for (self.args) |*v| {
                v.deinit(allocator);
            }
            allocator.free(self.args);
            allocator.destroy(self);
        }
    };

    pub const NativeFunction = struct {
        obj: Obj,
        arity: u32,
        native_fn: NativeFn,
        function: *Function,
        help: []const u8,

        pub fn init(allocator: std.mem.Allocator, func: NativeFn, arity: u8, help: []const u8) !*NativeFunction {
            const native_func = try allocator.create(NativeFunction);
            native_func.* = NativeFunction{
                .obj = Obj.init(.native_fn),
                .arity = arity,
                .native_fn = func,
                .help = help,
                .function = try Function.native(allocator, arity, help),
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
