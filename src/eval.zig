const std = @import("std");
const Env = @import("env.zig").Env;
const LispType = @import("types.zig").LispType;
const errors = @import("errors.zig");
const LispError = errors.LispError;
const outOfMemory = @import("utils.zig").outOfMemory;

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
    return env.getRoot().put(s[0].symbol.getStr(), val);
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
    return switch (cond) {
        .nil => if (s.len == 3) s[2] else .nil,
        .boolean => if (cond.eql(LispType.lisp_true))
            s[1]
        else if (s.len == 3)
            s[2]
        else
            .nil,
        else => s[1],
    };
}

pub fn eval(
    allocator: std.mem.Allocator,
    ast: LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    var s = ast;
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
                    value.clone(allocator)
                else
                    err_ctx.symbolNotFound(symbol.getStr());
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
                        var args = std.ArrayListUnmanaged(LispType).initCapacity(allocator, items.len - 1) catch outOfMemory();
                        for (items[1..]) |item| {
                            args.appendAssumeCapacity(item);
                        }
                        var new_env = Env.initFromParent(env);
                        defer new_env.deinit();

                        s = try builtin(allocator, args.items, new_env, err_ctx);
                        s = s.clone(allocator);
                    },
                    .fn_ => @panic("Not implemented."),
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
