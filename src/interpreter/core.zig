const std = @import("std");

const errors = @import("../errors.zig");
const types = @import("../lisp_types/value.zig");
const Obj = types.Obj;
const AST = types.AST;
const Value = types.Value;
const Env = @import("env.zig").Env;

const Keywords = enum {
    def,
    let,
};

pub fn def(
    gpa: std.mem.Allocator,
    list: std.MultiArrayList(AST),
    env: *Env,
    err_ctx: *errors.Ctx,
) !Value {
    if (list.len != 3) {
        return error.WrongNumberOfArguments;
    }

    const slice = list.slice();
    const name = slice.get(1);
    const ast = slice.get(2);

    if (name.value != .symbol) {
        return error.WrongArgumentType;
    }

    var value = try eval(gpa, ast.value, env, err_ctx);
    defer value.deinit(gpa);

    const res = try env.getGlobal().put(gpa, name.value.symbol, value);
    return res;
}

pub fn let(
    gpa: std.mem.Allocator,
    list: std.MultiArrayList(AST),
    env: *Env,
    err_ctx: *errors.Ctx,
) !Value {
    if (list.len != 3) {
        return error.WrongNumberOfArguments;
    }

    const slice = list.slice();
    const bindings = slice.get(1);
    const ast = slice.get(2);

    if (bindings.value != .obj) {
        return error.WrongArgumentType;
    }

    const o = try bindings.value.obj.get();
    if (o.kind != .list) {
        return error.WrongArgumentType;
    }

    const args = o.as(Obj.List).vec.array;
    if (args.len % 2 == 0) {
        return error.WrongNumberOfArguments;
    }

    const arg_metas = args.items(.meta);
    _ = arg_metas;
    const arg_values = args.items(.value);

    var local_env = Env.initFromParent(env);
    defer local_env.deinit(gpa);

    // first argument is the keyword vector
    for (0..args.len / 2) |idx| {
        const i = 2 * idx + 1;

        const name = arg_values[i];
        const value = arg_values[i + 1];

        if (name != .symbol) {
            return error.WrongArgumentType;
        }

        var ret = try eval(gpa, value, &local_env, err_ctx);
        defer ret.deinit(gpa);

        var ret_clone = try local_env.put(gpa, name.symbol, ret);
        ret_clone.deinit(gpa);
    }

    return eval(gpa, ast.value, &local_env, err_ctx);
}

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
            };
            break :blk env.get(s).?;
        },
        else => return error.WrongArgumentType,
    };
    _ = first;
    @panic("not implemented");
}

pub fn eval(
    gpa: std.mem.Allocator,
    ast: Value,
    env: *Env,
    err_ctx: *errors.Ctx,
) anyerror!Value {
    var s = try ast.borrow();

    while (true) {
        switch (s) {
            .symbol => |symbol| return env.get(symbol) orelse error.UndefinedVariable,
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

                        s = try evalList(gpa, items, env, err_ctx);
                    },
                    else => return s,
                }
            },
            else => return s,
        }
    }
}
