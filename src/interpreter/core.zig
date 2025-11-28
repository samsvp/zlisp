const std = @import("std");

const errors = @import("../errors.zig");
const types = @import("../lisp_types/value.zig");
const MetaData = types.MetaData;
const Obj = types.Obj;
const AST = types.AST;
const Value = types.Value;
const Env = @import("env.zig").Env;
const math = @import("math_builtins.zig");

const Keywords = enum {
    def,
    let,
    @"if",
    do,
    @"+",
    @"-",
    @"*",
    @"/",
    list,
    vector,
};

const Errors = error{
    WrongNumberOfArguments,
    WrongArgumentType,
    UndefinedVariable,
};

pub const ErrorCtx = struct {
    pub fn wrongNumberOfArguments(
        err_ctx: *errors.Ctx,
        expected: usize,
        actual: usize,
        meta: MetaData,
    ) anyerror {
        try err_ctx.setMessage(
            "Wrong number of arguments, expected {}, got {}.",
            .{ expected, actual },
            meta,
        );
        return Errors.WrongNumberOfArguments;
    }

    pub fn wrongArgumentType(
        err_ctx: *errors.Ctx,
        expected: []const u8,
        actual: []const u8,
        meta: MetaData,
    ) anyerror {
        try err_ctx.setMessage(
            "Wrong argument type: expected {s}, got {s}",
            .{ expected, actual },
            meta,
        );
        return Errors.WrongArgumentType;
    }

    pub fn undefinedVariable(
        err_ctx: *errors.Ctx,
        name: []const u8,
        meta: MetaData,
    ) anyerror {
        try err_ctx.setMessage(
            "Undefined variable {s}",
            .{name},
            meta,
        );
        return Errors.UndefinedVariable;
    }
};

fn def(
    gpa: std.mem.Allocator,
    list: std.MultiArrayList(AST),
    env: *Env,
    err_ctx: *errors.Ctx,
) !Value {
    const slice = list.slice();
    const self = slice.get(0);

    if (list.len != 3) {
        return ErrorCtx.wrongNumberOfArguments(err_ctx, 3, list.len, self.meta);
    }

    const name = slice.get(1);
    const ast = slice.get(2);

    if (name.value != .symbol) {
        return ErrorCtx.wrongArgumentType(err_ctx, "symbol", @tagName(name.value), name.meta);
    }

    var value = eval(gpa, ast.value, env, err_ctx) catch |err| {
        try err_ctx.appendMessage("def function", .{}, ast.meta);
        return err;
    };
    defer value.deinit(gpa);

    const res = env.getGlobal().put(gpa, name.value.symbol, value) catch |err| {
        try err_ctx.appendMessage("def function", .{}, self.meta);
        return err;
    };
    return res;
}

pub fn let(
    gpa: std.mem.Allocator,
    list: std.MultiArrayList(AST),
    env: *Env,
    err_ctx: *errors.Ctx,
) !Value {
    const slice = list.slice();
    const self = slice.get(0);

    if (list.len != 3) {
        return ErrorCtx.wrongNumberOfArguments(err_ctx, 3, list.len, self.meta);
    }

    const bindings = slice.get(1);
    const ast = slice.get(2);

    if (bindings.value != .obj) {
        return ErrorCtx.wrongArgumentType(err_ctx, @tagName(Obj.Kind.vector), @tagName(bindings.value), bindings.meta);
    }

    const o = try bindings.value.obj.get();
    if (o.kind != .list) {
        return ErrorCtx.wrongArgumentType(err_ctx, @tagName(Obj.Kind.vector), @tagName(bindings.value), bindings.meta);
    }

    const args = o.as(Obj.List).vec.array;
    const arg_metas = args.items(.meta);
    const arg_values = args.items(.value);

    if (args.len == 0 or arg_values[0] != .symbol or !std.mem.eql(u8, arg_values[0].symbol, @tagName(Obj.Kind.vector))) {
        return ErrorCtx.wrongArgumentType(err_ctx, @tagName(Obj.Kind.vector), @tagName(Obj.Kind.list), bindings.meta);
    }

    if (args.len % 2 == 0) {
        return ErrorCtx.wrongNumberOfArguments(err_ctx, args.len, args.len - 1, bindings.meta);
    }

    var local_env = Env.initFromParent(env);
    defer local_env.deinit(gpa);

    // first argument is the keyword vector
    for (0..args.len / 2) |idx| {
        const i = 2 * idx + 1;

        const name = arg_values[i];
        const value = arg_values[i + 1];

        if (name != .symbol) {
            return ErrorCtx.wrongArgumentType(err_ctx, @tagName(Value.symbol), @tagName(name), arg_metas[i]);
        }

        var ret = eval(gpa, value, &local_env, err_ctx) catch |err| {
            try err_ctx.appendMessage("let function", .{}, arg_metas[i + 1]);
            return err;
        };
        defer ret.deinit(gpa);

        var ret_clone = local_env.put(gpa, name.symbol, ret) catch |err| {
            try err_ctx.appendMessage("let function", .{}, arg_metas[i + 1]);
            return err;
        };
        ret_clone.deinit(gpa);
    }

    return eval(gpa, ast.value, &local_env, err_ctx) catch |err| {
        try err_ctx.appendMessage("let function", .{}, self.meta);
        return err;
    };
}

fn createList(
    gpa: std.mem.Allocator,
    list: std.MultiArrayList(AST),
    env: *Env,
    err_ctx: *errors.Ctx,
) anyerror!Value {
    const values = try gpa.alloc(AST, list.len - 1);
    defer gpa.free(values);

    const slice = list.slice();
    for (slice.items(.value)[1..], slice.items(.meta)[1..], 0..) |v, m, i| {
        const value = eval(gpa, v, env, err_ctx) catch |err| {
            for (0..i) |j| {
                values[j].value.deinit(gpa);
            }

            try err_ctx.appendMessage("list", .{}, m);
            return err;
        };
        values[i] = .{ .value = value, .meta = m };
    }

    const new_list = try Obj.List.init(gpa, values);
    return Value.initObj(gpa, &new_list.obj);
}

fn createVector(
    gpa: std.mem.Allocator,
    list: std.MultiArrayList(AST),
    env: *Env,
    err_ctx: *errors.Ctx,
) anyerror!Value {
    const values = try gpa.alloc(Value, list.len - 1);
    defer gpa.free(values);

    var i: usize = 0;
    defer for (0..i) |j| {
        values[j].deinit(gpa);
    };

    const slice = list.slice();
    for (
        slice.items(.value)[1..],
        slice.items(.meta)[1..],
    ) |v, m| {
        const value = eval(gpa, v, env, err_ctx) catch |err| {
            try err_ctx.appendMessage("vector", .{}, m);
            return err;
        };

        values[i] = value;
        i += 1;
    }

    const new_vec = try Obj.PVector.init(gpa, values);
    return Value.initObj(gpa, &new_vec.obj);
}

const ListFn = *const fn (std.mem.Allocator, std.MultiArrayList(AST), *Env, *errors.Ctx) anyerror!Value;

pub fn evalList(
    gpa: std.mem.Allocator,
    list: std.MultiArrayList(AST),
    env: *Env,
    err_ctx: *errors.Ctx,
) anyerror!Value {
    const values = list.items(.value);
    const first = switch (values[0]) {
        .symbol => |s| blk: {
            if (std.meta.stringToEnum(Keywords, s)) |c| return switch (c) {
                .def => def(gpa, list, env, err_ctx),
                .let => let(gpa, list, env, err_ctx),
                .@"if" => if_(gpa, list, env, err_ctx),
                .do => do(gpa, list, env, err_ctx),
                .@"+" => math.add(gpa, list, env, err_ctx),
                .@"-" => math.sub(gpa, list, env, err_ctx),
                .@"*" => math.mult(gpa, list, env, err_ctx),
                .@"/" => math.div(gpa, list, env, err_ctx),
                .list => createList(gpa, list, env, err_ctx),
                .vector => createVector(gpa, list, env, err_ctx),
            };
            break :blk env.get(s).?;
        },
        else => return error.WrongArgumentType,
    };
    _ = first;
    @panic("not implemented");
}

fn if_(
    gpa: std.mem.Allocator,
    list: std.MultiArrayList(AST),
    env: *Env,
    err_ctx: *errors.Ctx,
) anyerror!Value {
    const slice = list.slice();
    const self = slice.get(0);

    if (list.len != 3 and list.len != 4) {
        const expected: usize = if (list.len < 3) 2 else 3;
        return ErrorCtx.wrongNumberOfArguments(err_ctx, expected, list.len, self.meta);
    }

    const cond_ast = slice.get(1);
    var cond = eval(gpa, cond_ast.value, env, err_ctx) catch |err| {
        try err_ctx.appendMessage("if function, err evaluating condition.", .{}, cond_ast.meta);
        return err;
    };
    defer cond.deinit(gpa);

    const true_branch = slice.get(2);
    const new_s = switch (cond) {
        .nil => if (list.len == 4) slice.get(3) else AST{ .meta = true_branch.meta, .value = Value.Nil },
        .boolean => blk: {
            break :blk if (cond.eql(Value.True))
                true_branch
            else if (list.len == 4)
                slice.get(3)
            else
                AST{ .meta = true_branch.meta, .value = Value.Nil };
        },
        else => true_branch,
    };
    return eval(gpa, new_s.value, env, err_ctx) catch |err| {
        try err_ctx.appendMessage("if function, error evaluating conditional branch.", .{}, new_s.meta);
        return err;
    };
}

pub fn do(
    gpa: std.mem.Allocator,
    list: std.MultiArrayList(AST),
    env: *Env,
    err_ctx: *errors.Ctx,
) anyerror!Value {
    const slice = list.slice();

    var ret = Value.Nil;
    const values = slice.items(.value)[1..];
    const metas = slice.items(.meta);
    for (values, 1..) |val, i| {
        const new_ret = eval(gpa, val, env, err_ctx) catch |err| {
            try err_ctx.appendMessage("if function, error evaluating conditional branch.", .{}, metas[i]);
            return err;
        };
        ret.deinit(gpa);
        ret = new_ret;
    }
    return ret;
}

pub fn eval(
    gpa: std.mem.Allocator,
    ast: Value,
    env: *Env,
    err_ctx: *errors.Ctx,
) anyerror!Value {
    var s = try ast.borrow();
    _ = &s;

    while (true) {
        switch (s) {
            .symbol => |symbol| return env.get(symbol) orelse Errors.UndefinedVariable,
            .obj => |o_ref| {
                const o = o_ref.getUnwrap();
                switch (o.kind) {
                    .list => {
                        const list = o.as(Obj.List);
                        const items = list.vec.array;
                        if (items.len == 0) {
                            return s;
                        }

                        var old_s = s;
                        defer old_s.deinit(gpa);

                        return evalList(gpa, items, env, err_ctx);
                    },
                    else => return s,
                }
            },
            else => return s,
        }
    }
}
