const std = @import("std");
const Env = @import("env.zig").Env;
const LispType = @import("types.zig").LispType;
const errors = @import("errors.zig");
const LispError = errors.LispError;
const outOfMemory = @import("utils.zig").outOfMemory;

pub fn eval(
    allocator: std.mem.Allocator,
    ast: LispType,
    root_env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    var s = ast;
    var env = root_env;

    while (true) {
        const is_eval = env.get("DEBUG-EVAL");
        if (is_eval) |flag| {
            if (flag != .nil and !flag.eql(LispType.lisp_false)) {
                const str_value = s.toStringFull(allocator) catch outOfMemory();
                std.debug.print("EVAL {s}\n", .{str_value});
            }
        }

        switch (s) {
            .symbol => |symbol| {
                return if (env.getPtr(symbol.getStr())) |value|
                    value.*
                else
                    err_ctx.symbolNotFound(symbol.getStr());
            },
            .list => |v| {
                const items = v.getItems();
                if (items.len == 0) {
                    return s;
                }

                const fst = switch (items[0]) {
                    .symbol, .list => try eval(allocator, items[0], env, err_ctx),
                    else => items[0],
                };

                switch (fst) {
                    .function => |function| switch (function.*) {
                        .builtin => |builtin| {
                            return try builtin(allocator, items[1..], env, err_ctx);
                        },
                        .fn_ => |func| {
                            const args = items[1..];
                            env, s = try Fn.apply(allocator, args, func, env, err_ctx);
                            continue;
                        },
                    },
                    else => {
                        var new_lst = LispType.Array.emptyList();
                        new_lst.list.appendMut(allocator, fst);
                        for (items[1..]) |item| {
                            const new_item = try eval(allocator, item, env, err_ctx);
                            new_lst.list.appendMut(allocator, new_item);
                        }
                        return new_lst;
                    },
                }
            },
            .vector => |v| {
                var new_v = LispType.Array.emptyVector();
                for (v.getItems()) |item| {
                    const new_item = try eval(allocator, item, env, err_ctx);
                    new_v.vector.appendMut(allocator, new_item);
                }
                return new_v;
            },
            .dict => |dict| {
                var new_dict = LispType.Dict.init();

                var iter = dict.map.iterator();
                while (iter.next()) |entry| {
                    const key_value = try eval(allocator, entry.key_ptr.*, env, err_ctx);
                    const value = try eval(allocator, entry.value_ptr.*, env, err_ctx);

                    try new_dict.dict.addMut(allocator, key_value, value);
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

    const fst = try eval(allocator, s[0], env, err_ctx);
    return eval(allocator, fst, env, err_ctx);
}

const Fn = struct {
    const Ret = std.meta.Tuple(&.{ *Env, LispType });

    pub fn apply(
        allocator: std.mem.Allocator,
        args: []LispType,
        func: LispType.Fn,
        env: *Env,
        err_ctx: *errors.Context,
    ) LispError!Ret {
        const is_variadic = func.args.len > 0 and func.args[func.args.len - 1][0] == '&';
        const new_env = try if (is_variadic)
            apply_variadic(allocator, func, args, env, err_ctx)
        else
            apply_base(allocator, func, args, env, err_ctx);

        const ast = if (func.is_macro) try eval(allocator, func.ast.*, new_env, err_ctx) else func.ast.*;
        return .{ new_env, ast };
    }

    fn eval_arg(
        alloc: std.mem.Allocator,
        func: LispType.Fn,
        arg: LispType,
        env: *Env,
        err_ctx_: *errors.Context,
    ) LispError!LispType {
        return if (func.is_macro) arg else try eval(alloc, arg, env, err_ctx_);
    }

    fn apply_base(
        allocator: std.mem.Allocator,
        func: LispType.Fn,
        args: []LispType,
        env: *Env,
        err_ctx: *errors.Context,
    ) LispError!*Env {
        const fn_args_len = func.args.len;
        var new_env = Env.initFromParent(func.env);
        if (fn_args_len != args.len) {
            return err_ctx.wrongNumberOfArguments(fn_args_len, args.len);
        }

        for (args, func.args) |item, arg_name| {
            const val = try eval_arg(allocator, func, item, env, err_ctx);
            _ = new_env.put(arg_name, val);
        }
        return new_env;
    }

    fn apply_variadic(
        allocator: std.mem.Allocator,
        func: LispType.Fn,
        args: []LispType,
        env: *Env,
        err_ctx: *errors.Context,
    ) LispError!*Env {
        const fn_args_len = func.args.len;
        var new_env = Env.initFromParent(func.env);
        if (args.len < fn_args_len - 1) {
            return err_ctx.wrongNumberOfArguments(fn_args_len, args.len);
        }

        for (args[0 .. fn_args_len - 1], func.args[0 .. fn_args_len - 1]) |item, arg_name| {
            const val = try eval_arg(allocator, func, item, env, err_ctx);
            _ = new_env.put(arg_name, val);
        }

        const arg_name = func.args[fn_args_len - 1][1..]; // remove &
        const var_args = args[fn_args_len - 1 ..];

        var list = LispType.Array.emptyList();
        list.list.array.ensureTotalCapacity(allocator, var_args.len) catch outOfMemory();
        for (var_args) |item| {
            const val = if (func.is_macro) item else try eval(allocator, item, env, err_ctx);
            list.list.array.appendAssumeCapacity(val);
        }
        _ = new_env.put(arg_name, list);

        return new_env;
    }
};

pub fn try_(
    allocator: std.mem.Allocator,
    s: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (s.len != 2) {
        return err_ctx.wrongNumberOfArguments(2, s.len);
    }

    if (s[1] != .list) {
        return err_ctx.wrongParameterType("'try' second argument", "list");
    }

    const catch_form = s[1].list.getItems();
    if (catch_form.len != 3) {
        return err_ctx.wrongNumberOfArguments(3, catch_form.len);
    }

    if (catch_form[0] == .symbol) {
        if (!std.mem.eql(u8, catch_form[0].symbol.getStr(), "catch"))
            return err_ctx.missingCatch();
    } else {
        return err_ctx.missingCatch();
    }

    if (catch_form[1] != .symbol) {
        return err_ctx.wrongParameterType("'catch' first argument", "symbol");
    }

    const ret = eval(allocator, s[0], env, err_ctx) catch {
        const err_str = err_ctx.toLispString(allocator);
        const new_env = Env.initFromParent(env);

        _ = new_env.put(catch_form[1].symbol.getStr(), err_str);
        return eval(allocator, catch_form[2], new_env, err_ctx);
    };

    return ret;
}

pub fn throw(
    _: std.mem.Allocator,
    s: []LispType,
    _: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (s.len != 1) {
        return err_ctx.wrongNumberOfArguments(1, s.len);
    }

    if (s[0] != .string) {
        return err_ctx.wrongParameterType("'throw' first argument", "string");
    }

    return err_ctx.customError(s[0].string.getStr());
}

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
            const arr = switch (elt) {
                .list, .vector => |arr| arr,
                else => return false,
            };

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

    const args_arr = switch (ast) {
        .list, .vector => |arr| arr,
        else => return ast,
    };

    const args = args_arr.getItems();
    if (args.len == 2) {
        if (args[0] == .symbol and ast == .list and std.mem.eql(u8, args[0].symbol.getStr(), "unquote")) {
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

    return switch (ast) {
        .list => LispType.Array.initList(allocator, res_arr.items),
        .vector => LispType.Array.initVector(allocator, res_arr.items),
        else => unreachable,
    };
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
    return env.getRoot().putClone(s[0].symbol.getStr(), val);
}

pub fn defmacro(
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

    const err = err_ctx.wrongParameterType("'defmacro' second argument", "function");
    const val = try eval(allocator, s[1], env, err_ctx);
    return switch (val) {
        .function => |f| switch (f.*) {
            .fn_ => |*func| {
                func.is_macro = true;
                return env.putClone(s[0].symbol.getStr(), val);
            },
            else => err,
        },
        else => err,
    };
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

        const arg_env = Env.initFromParent(new_env);
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
    if (s.len != 2 and s.len != 3 and s.len != 4) {
        return err_ctx.wrongNumberOfArgumentsThreeChoices(2, 3, 4, s.len);
    }

    var args_symbol =
        if (s.len == 2)
            s[0]
        else if (s.len == 3)
            s[1]
        else
            s[2];
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
    if ((s.len == 3 and s[0] != .string) or s.len == 4) {
        const closure_symbols = if (s[0] == .string) s[1] else s[0];
        if (closure_symbols != .vector) {
            return err_ctx.wrongParameterType("'fn' parameter list", "vector");
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
    const docstring = if (s[0] == .string) s[0].string.getStr() else "";

    return LispType.Fn.init(
        allocator,
        s[s.len - 1],
        args.items,
        closure_names.items,
        closure_vals.items,
        docstring,
        env,
    );
}

pub fn do(
    allocator: std.mem.Allocator,
    s: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    var res: LispType = .nil;
    for (s) |item| {
        res = try eval(allocator, item, env, err_ctx);
    }
    return res;
}
