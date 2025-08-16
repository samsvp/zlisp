const std = @import("std");
const Env = @import("env.zig").Env;
const LispType = @import("types.zig").LispType;
const errors = @import("errors.zig");
const LispError = errors.LispError;
const outOfMemory = @import("utils.zig").outOfMemory;

pub fn quote(
    _: std.mem.Allocator,
    s: []LispType,
    _: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (s.len != 1) {
        return err_ctx.wrongNumberOfArguments(1, s.len);
    }

    return s[0];
}

pub fn quasiquote(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    const isSpliceUnquote = struct {
        pub fn f(elt: LispType) bool {
            if (elt != .list) {
                return false;
            }

            const arr = elt.list;
            const items = arr.getItems();
            return items.len > 0 and
                items[0] == .symbol and
                std.mem.eql(u8, items[0].symbol.getStr(), "splice-unquote");
        }
    }.f;

    if (args_.len != 1) {
        return err_ctx.wrongNumberOfArguments(1, args_.len);
    }

    const ast = args_[0];

    if (ast != .list) {
        return ast;
    }

    const args_arr = ast.list;
    const args = args_arr.getItems();
    if (args.len == 2) {
        if (args[0] == .symbol and std.mem.eql(u8, args[0].symbol.getStr(), "unquote")) {
            return eval(allocator, args[1], env, err_ctx);
        }
    }

    var res_arr = std.ArrayListUnmanaged(LispType).initCapacity(allocator, args.len) catch outOfMemory();
    for (args) |elt| {
        if (!isSpliceUnquote(elt)) {
            var eltt = [_]LispType{elt};
            const res = try quasiquote(allocator, &eltt, env, err_ctx);
            res_arr.append(allocator, res) catch outOfMemory();
            continue;
        }

        const items = elt.list.getItems();
        if (items.len != 2) return err_ctx.wrongNumberOfArguments(2, items.len);

        const lst = try eval(allocator, items[1], env, err_ctx);

        if (lst != .list) {
            return err_ctx.wrongParameterType("'splice-unquote' argument", "list");
        }
        for (lst.list.getItems()) |*x| {
            res_arr.append(allocator, x.clone(allocator)) catch outOfMemory();
        }
    }

    return LispType.Array.initList(allocator, res_arr.items);
}

pub fn def(
    allocator: std.mem.Allocator,
    s: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (s.len != 2) {
        return err_ctx.wrongNumberOfArguments(2, s.len);
    }

    if (s[0] != .symbol) {
        return err_ctx.wrongParameterType("First argument", "symbol");
    }

    const val = try eval(allocator, s[1], env, err_ctx);
    return env.putClone(s[0].symbol.getStr(), val);
}

pub fn if_(
    allocator: std.mem.Allocator,
    s: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (s.len != 2 and s.len != 3) {
        return err_ctx.wrongNumberOfArgumentsTwoChoices(2, 3, s.len);
    }

    const cond = try eval(allocator, s[0], env, err_ctx);
    const new_s = switch (cond) {
        .nil => if (s.len == 3) s[2] else .nil,
        .boolean => if (cond.eql(LispType.lisp_true))
            s[1]
        else if (s.len == 3)
            s[2]
        else
            .nil,
        else => s[1],
    };
    return eval(allocator, new_s, env, err_ctx);
}

pub fn let(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len != 2) {
        return err_ctx.wrongNumberOfArguments(2, args.len);
    }

    var new_env = Env.initFromParent(env);

    defer new_env.deinit();

    const arr = switch (args[0]) {
        .list, .vector => |arr| blk: {
            if (arr.getItems().len % 2 != 0) {
                return err_ctx.wrongNumberOfArguments(args.len + 1, args.len);
            }

            break :blk arr;
        },

        else => return err_ctx.wrongParameterType("First argument", "vector"),
    };

    const args_items = arr.getItems();

    for (0..args_items.len / 2) |_i| {
        const i = 2 * _i;

        var arg_env = Env.initFromParent(new_env);

        defer arg_env.deinit();

        const key = args_items[i];

        const value = try eval(allocator, args_items[i + 1], arg_env, err_ctx);

        switch (key) {
            .symbol => |new_symbol| {
                _ = new_env.put(new_symbol.getStr(), value);
            },

            else => return err_ctx.wrongParameterType("'let' key", "symbol"),
        }
    }

    return eval(allocator, args[1], new_env, err_ctx);
}

pub fn fn_(
    allocator: std.mem.Allocator,
    s: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (s.len != 2 and s.len != 3) {
        return err_ctx.wrongNumberOfArgumentsTwoChoices(2, 3, s.len);
    }

    var args_symbol = if (s.len == 2) s[0] else s[1];
    if (args_symbol != .vector) {
        return err_ctx.wrongParameterType("Parameter list", "vector");
    }

    const items = args_symbol.vector.getItems();
    var args = std.ArrayListUnmanaged([]const u8).initCapacity(allocator, items.len) catch outOfMemory();
    for (items) |a| {
        if (a != .symbol) {
            return err_ctx.wrongParameterType("Parameter list arguments", "symbol");
        }

        args.appendAssumeCapacity(a.symbol.getStr());
    }

    var closure_names: std.ArrayListUnmanaged([]const u8) = .empty;
    var closure_vals: std.ArrayListUnmanaged(LispType) = .empty;
    if (s.len == 3) {
        const closure_symbols = s[0];
        if (closure_symbols != .vector) {
            return err_ctx.wrongParameterType("Parameter list", "vector");
        }

        const c_items = closure_symbols.vector.getItems();
        closure_names.ensureTotalCapacity(allocator, c_items.len) catch outOfMemory();
        closure_vals.ensureTotalCapacity(allocator, c_items.len) catch outOfMemory();
        for (c_items) |item| {
            if (item != .symbol) {
                return err_ctx.wrongParameterType("Parameter list arguments", "symbol");
            }

            closure_names.appendAssumeCapacity(item.symbol.getStr());
            closure_vals.appendAssumeCapacity(try eval(allocator, item, env, err_ctx));
        }
    }

    return LispType.Fn.init(
        allocator,
        s[s.len - 1],
        args.items,
        closure_names.items,
        closure_vals.items,
        env,
    );
}

pub fn eval(
    allocator: std.mem.Allocator,
    ast: LispType,
    root_env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    var s = ast;
    var env = root_env;

    var env_stack: std.ArrayListUnmanaged(*Env) = .empty;

    defer {
        for (env_stack.items) |m_env| {
            m_env.deinit();
        }
        env_stack.deinit(root_env.arena.child_allocator);
    }

    while (true) {
        const is_eval = env.get("DEBUG-EVAL");
        if (is_eval) |flag| {
            if (flag != .nil and !flag.eql(LispType.lisp_false)) {
                var buffer: [1000]u8 = undefined;
                std.debug.print("EVAL {s}\n", .{s.toString(&buffer)});
            }
        }

        switch (s) {
            .symbol => |symbol| {
                return if (env.getPtr(symbol.getStr())) |value|
                    return value.*
                else
                    return err_ctx.symbolNotFound(symbol.getStr());
            },
            .list => |v| {
                const items = v.getItems();
                if (items.len == 0) {
                    return s;
                }

                const function = switch (items[0]) {
                    .symbol => sym: {
                        const res = try eval(allocator, items[0], env, err_ctx);
                        if (res != .function) {
                            return err_ctx.wrongParameterType("First argument", "function");
                        }
                        break :sym res.function;
                    },
                    .function => |function| function,
                    else => return err_ctx.wrongParameterType("First argument", "function"),
                };

                switch (function) {
                    .builtin => |builtin| {
                        return try builtin(allocator, items[1..], env, err_ctx);
                    },
                    .fn_ => |func| {
                        if (func.args.len != items[1..].len) {
                            return err_ctx.wrongNumberOfArguments(func.args.len, items[1..].len);
                        }

                        var new_env = Env.initFromParent(func.env);
                        for (items[1..], func.args) |item, arg| {
                            const val = try eval(allocator, item, env, err_ctx);
                            _ = new_env.put(arg, val);
                        }

                        s = func.ast.*;
                        env = new_env;
                        continue;
                    },
                }
            },
            .vector => |v| {
                var new_v = LispType.Array.emptyVector();
                for (v.getItems()) |item| {
                    const new_item = try eval(allocator, item, env, err_ctx);
                    new_v.vector.append(allocator, new_item);
                }
                return new_v;
            },
            .dict => |dict| {
                var new_dict = LispType.Dict.init();

                var iter = dict.map.iterator();
                while (iter.next()) |entry| {
                    const key_value = try eval(allocator, entry.key_ptr.*, env, err_ctx);
                    const value = try eval(allocator, entry.value_ptr.*, env, err_ctx);

                    try new_dict.dict.add(allocator, key_value, value);
                }
                return new_dict;
            },
            else => return s,
        }
    }
}

pub fn evalWrapper(
    allocator: std.mem.Allocator,
    s: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (s.len != 1) {
        return err_ctx.wrongNumberOfArguments(1, s.len);
    }

    return eval(allocator, s[0], env, err_ctx);
}
