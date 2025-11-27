const std = @import("std");

const errors = @import("../errors.zig");
const types = @import("../lisp_types/value.zig");
const core = @import("core.zig");
const MetaData = types.MetaData;
const Obj = types.Obj;
const AST = types.AST;
const Value = types.Value;
const Env = @import("env.zig").Env;

const Error = error{
    MismatchedType,
    DivisionByZero,
};

fn wrongType(
    op_name: []const u8,
    type_name: []const u8,
    err_ctx: *errors.Ctx,
    meta: MetaData,
) anyerror {
    try err_ctx.setMessage("'{s}' mismatched types: {s} - ensure all types are the same.", .{ op_name, type_name }, meta);
    return Error.MismatchedType;
}

fn divisionByZero(
    err_ctx: *errors.Ctx,
    meta: MetaData,
) anyerror {
    try err_ctx.setMessage("Division by zero.", .{}, meta);
    return Error.DivisionByZero;
}

pub fn eql(
    gpa: std.mem.Allocator,
    list: std.MultiArrayList(AST),
    env: *Env,
    err_ctx: *errors.Ctx,
) Value {
    const values = list.items(.value);
    const metas = list.items(.meta);
    if (values.len == 1) {
        return Value.Nil;
    }

    var first = core.eval(gpa, values[1], env, err_ctx) catch |err| {
        try err_ctx.appendMessage("Error on '='", .{}, metas[1]);
        return err;
    };
    defer first.deinit(gpa);
    for (values[2..], 2..) |v, i| {
        var val = core.eval(gpa, v, env, err_ctx) catch |err| {
            try err_ctx.appendMessage("Error on '='", .{}, metas[i]);
            return err;
        };
        defer val.deinit(gpa);

        if (!first.eql(val)) {
            return Value.False;
        }
    }
    return Value.True;
}

pub fn not(
    gpa: std.mem.Allocator,
    list: std.MultiArrayList(AST),
    env: *Env,
    err_ctx: *errors.Ctx,
) !Value {
    const values = list.items(.value);
    const metas = list.items(.meta);
    if (values.len != 2) {
        return core.ErrorCtx.wrongNumberOfArguments(err_ctx, 1, values.len - 1, metas[0]);
    }

    var val = core.eval(gpa, values[1], env, err_ctx) catch |err| {
        try err_ctx.appendMessage("Error on '='", .{}, metas[1]);
        return err;
    };
    defer val.deinit(gpa);

    return switch (val) {
        .nil => Value.True,
        .boolean => |b| if (b) Value.False else Value.True,
        else => Value.False,
    };
}

pub const CmpKind = enum {
    lt,
    gt,
    leq,
    geq,

    pub fn toStr(kind: CmpKind) []const u8 {
        return switch (kind) {
            .lt => "<",
            .gt => ">",
            .leq => "<=",
            .geq => ">=",
        };
    }
};

pub fn add(
    gpa: std.mem.Allocator,
    list: std.MultiArrayList(AST),
    env: *Env,
    err_ctx: *errors.Ctx,
) !Value {
    const values = list.items(.value);
    const metas = list.items(.meta);
    if (values.len == 1) {
        return Value.Nil;
    }

    var first = core.eval(gpa, values[1], env, err_ctx) catch |err| {
        try err_ctx.appendMessage("Error on '+'", .{}, metas[1]);
        return err;
    };
    defer first.deinit(gpa);

    var acc = try first.borrow();
    for (values[2..], 2..) |v, i| {
        var val = core.eval(gpa, v, env, err_ctx) catch |err| {
            try err_ctx.appendMessage("Error on '+'", .{}, metas[i]);
            return err;
        };
        defer val.deinit(gpa);

        acc = switch (acc) {
            .int => |i_| if (val == .int) .{ .int = i_ + val.int } else return wrongType("+", @tagName(val), err_ctx, metas[i]),
            .float => |f| if (val == .float)
                .{ .float = f + val.float }
            else if (val == .int)
                .{ .float = f + @as(f32, @floatFromInt(val.int)) }
            else
                return wrongType("+", @tagName(val), err_ctx, metas[i]),
            else => return core.ErrorCtx.wrongArgumentType(err_ctx, "int or float", @tagName(acc), metas[1]),
        };
    }
    return acc;
}

pub fn sub(
    gpa: std.mem.Allocator,
    list: std.MultiArrayList(AST),
    env: *Env,
    err_ctx: *errors.Ctx,
) !Value {
    const values = list.items(.value);
    const metas = list.items(.meta);
    if (values.len == 1) {
        return Value.Nil;
    }

    var first = core.eval(gpa, values[1], env, err_ctx) catch |err| {
        try err_ctx.appendMessage("Error on '-'", .{}, metas[1]);
        return err;
    };
    defer first.deinit(gpa);

    if (first != .int and first != .float) {
        return core.ErrorCtx.wrongArgumentType(err_ctx, "int or float", @tagName(first), metas[1]);
    }

    if (values.len == 2) return switch (first) {
        .int => |i| .{ .int = -i },
        .float => |f| .{ .float = -f },
        else => unreachable,
    };

    var acc = first;
    for (values[2..], 2..) |v, i| {
        var val = core.eval(gpa, v, env, err_ctx) catch |err| {
            try err_ctx.appendMessage("Error on '-'", .{}, metas[i]);
            return err;
        };
        defer val.deinit(gpa);

        acc = switch (acc) {
            .int => |i_| if (val == .int) .{ .int = i_ - val.int } else return wrongType("-", @tagName(val), err_ctx, metas[i]),
            .float => |f| if (val == .float)
                .{ .float = f - val.float }
            else if (val == .int)
                .{ .float = f - @as(f32, @floatFromInt(val.int)) }
            else
                return wrongType("-", @tagName(val), err_ctx, metas[i]),
            else => unreachable,
        };
    }
    return acc;
}

pub fn mult(
    gpa: std.mem.Allocator,
    list: std.MultiArrayList(AST),
    env: *Env,
    err_ctx: *errors.Ctx,
) !Value {
    const values = list.items(.value);
    const metas = list.items(.meta);
    if (values.len == 1) {
        return Value.Nil;
    }

    var first = core.eval(gpa, values[1], env, err_ctx) catch |err| {
        try err_ctx.appendMessage("Error on '*'", .{}, metas[1]);
        return err;
    };
    defer first.deinit(gpa);

    if (first != .int and first != .float) {
        return core.ErrorCtx.wrongArgumentType(err_ctx, "int or float", @tagName(first), metas[1]);
    }

    var acc = try first.borrow();
    for (values[2..], 2..) |v, i| {
        var val = core.eval(gpa, v, env, err_ctx) catch |err| {
            try err_ctx.appendMessage("Error on '*'", .{}, metas[i]);
            return err;
        };
        defer val.deinit(gpa);

        acc = switch (acc) {
            .int => |i_| if (val == .int) .{ .int = i_ * val.int } else return wrongType("*", @tagName(val), err_ctx, metas[i]),
            .float => |f| if (val == .float)
                .{ .float = f * val.float }
            else if (val == .int)
                .{ .float = f * @as(f32, @floatFromInt(val.int)) }
            else
                return wrongType("*", @tagName(val), err_ctx, metas[i]),
            else => unreachable,
        };
    }
    return acc;
}

pub fn div(
    gpa: std.mem.Allocator,
    list: std.MultiArrayList(AST),
    env: *Env,
    err_ctx: *errors.Ctx,
) !Value {
    const values = list.items(.value);
    const metas = list.items(.meta);
    if (values.len == 1) {
        return Value.Nil;
    }

    var first = core.eval(gpa, values[1], env, err_ctx) catch |err| {
        try err_ctx.appendMessage("Error on '/'", .{}, metas[1]);
        return err;
    };
    defer first.deinit(gpa);

    if (first != .int and first != .float) {
        return core.ErrorCtx.wrongArgumentType(err_ctx, "int or float", @tagName(first), metas[1]);
    }

    var acc = try first.borrow();
    for (values[2..], 2..) |v, i| {
        var val = core.eval(gpa, v, env, err_ctx) catch |err| {
            try err_ctx.appendMessage("Error on '/'", .{}, metas[i]);
            return err;
        };
        defer val.deinit(gpa);

        acc = switch (acc) {
            .int => |i_| if (val == .int) blk: {
                break :blk if (val.int != 0)
                    .{ .int = @divTrunc(i_, val.int) }
                else
                    return divisionByZero(err_ctx, metas[i]);
            } else return wrongType("*", @tagName(val), err_ctx, metas[i]),
            .float => |f| if (val == .float) blk: {
                break :blk if (val.float != 0)
                    .{ .float = f / val.float }
                else
                    return divisionByZero(err_ctx, metas[i]);
            } else if (val == .int) blk: {
                break :blk if (val.int != 0)
                    .{ .float = f / @as(f32, @floatFromInt(val.int)) }
                else
                    return divisionByZero(err_ctx, metas[i]);
            } else return wrongType("*", @tagName(val), err_ctx, metas[i]),
            else => unreachable,
        };
    }
    return acc;
}
