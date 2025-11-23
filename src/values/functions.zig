const std = @import("std");

const Value = @import("value.zig").Value;
const Obj = @import("value.zig").Obj;
const Chunk = @import("../backend/chunk.zig").Chunk;
const errors = @import("../errors.zig");

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

pub const Native = struct {
    obj: Obj,
    native_fn: NativeFn,
    function: *Function,

    pub fn init(
        allocator: std.mem.Allocator,
        func: NativeFn,
        arity: u8,
        is_variadic: bool,
        help: []const u8,
    ) !*Native {
        const native_func = try allocator.create(Native);
        native_func.* = Native{
            .obj = Obj.init(.native_fn),
            .native_fn = func,
            .function = try Function.native(allocator, arity, is_variadic, help),
        };
        return native_func;
    }

    pub fn deinit(self: *Native, allocator: std.mem.Allocator) void {
        defer allocator.destroy(self);

        self.function.deinit(allocator);
    }
};

pub const NativeFn = *const fn (
    allocator: std.mem.Allocator,
    args: []const Value,
    err_ctx: *errors.Ctx,
) anyerror!Value;
