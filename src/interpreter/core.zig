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

    const value = try evalAST(gpa, ast.value, env, err_ctx);
    const res = try env.put(gpa, name.value.symbol, value);
    return res;
}

pub fn let(
    gpa: std.mem.Allocator,
    list: std.MultiArrayList(AST),
    env: *Env,
    err_ctx: *errors.Ctx,
) !AST {
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

    var local_env = Env.initFromParent(env);
    _ = &local_env;
    for (args.items(.values)[1..], 1..) |v, i| {
        _ = v;
        _ = i;
    }

    return evalAST(gpa, ast, env, err_ctx);
}

pub fn evalList(
    gpa: std.mem.Allocator,
    list: std.MultiArrayList(AST),
    env: *Env,
    err_ctx: *errors.Ctx,
) anyerror!AST {
    const values = list.items(.values);
    const first = switch (values[0]) {
        .symbol => |s| {
            if (std.meta.stringToEnum(Keywords, s)) |c| return switch (c) {
                .def => def(gpa, list, env, err_ctx),
            };
            env.get(s);
        },
    };
    _ = first;
}

pub fn evalAST(
    gpa: std.mem.Allocator,
    ast: Value,
    env: *Env,
    err_ctx: *errors.Ctx,
) anyerror!AST {
    var s = ast;

    while (true) {
        switch (s) {
            .obj => |o_ref| {
                const o = o_ref.getUnwrap();
                switch (o.kind) {
                    .list => {
                        const list = o.as(Obj.List);
                        const items = list.vec.array;
                        if (items.len == 0) {
                            return s;
                        }

                        s = try evalList(gpa, items, env, err_ctx);
                    },
                }
            },
            else => return s,
        }
    }
}
