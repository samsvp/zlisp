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
        gpa: std.mem.Allocator,
        chunk: *Chunk,
        arity: u8,
        is_variadic: bool,
        help: []const u8,
    ) !*Function {
        const func = try gpa.create(Function);
        func.* = Function{
            .obj = Obj.init(.function),
            .chunk = chunk,
            .arity = arity,
            .is_variadic = is_variadic,
            .help = help,
        };
        return func;
    }

    pub fn deinit(self: *Function, gpa: std.mem.Allocator) void {
        self.chunk.deinit(gpa);
        gpa.destroy(self.chunk);
        gpa.destroy(self);
    }

    pub fn native(gpa: std.mem.Allocator, arity: u32, is_variadic: bool, help: []const u8) !*Function {
        var chunk = try gpa.create(Chunk);
        chunk.* = .empty;
        try chunk.append(gpa, .ret, 0);

        const func = try gpa.create(Function);
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

    pub fn init(gpa: std.mem.Allocator, func: *Function, args: []Value) !*Closure {
        const closure = try gpa.create(Closure);
        closure.* = Closure{
            .obj = Obj.init(.closure),
            .function = func,
            .args = try gpa.dupe(Value, args),
        };

        func.obj.count += 1;
        return closure;
    }

    pub fn deinit(self: *Closure, gpa: std.mem.Allocator) void {
        defer gpa.destroy(self);
        defer gpa.free(self.args);

        self.function.deinit(gpa);
        for (self.args) |*v| {
            v.deinit(gpa);
        }
    }
};

pub const Native = struct {
    obj: Obj,
    native_fn: NativeFn,
    function: *Function,

    pub fn init(
        gpa: std.mem.Allocator,
        func: NativeFn,
        arity: u8,
        is_variadic: bool,
        help: []const u8,
    ) !*Native {
        const native_func = try gpa.create(Native);
        native_func.* = Native{
            .obj = Obj.init(.native_fn),
            .native_fn = func,
            .function = try Function.native(gpa, arity, is_variadic, help),
        };
        return native_func;
    }

    pub fn deinit(self: *Native, gpa: std.mem.Allocator) void {
        defer gpa.destroy(self);

        self.function.deinit(gpa);
    }
};

pub const NativeFn = *const fn (
    gpa: std.mem.Allocator,
    args: []const Value,
    err_ctx: *errors.Ctx,
) anyerror!Value;
