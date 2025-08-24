const std = @import("std");
const Env = @import("env.zig").Env;
const errors = @import("errors.zig");
const Enum = @import("types.zig").Enum;
const LispType = @import("types.zig").LispType;
const LispError = errors.LispError;
const reader = @import("reader.zig");
const core = @import("core.zig");
const outOfMemory = @import("utils.zig").outOfMemory;

fn evalArgs(
    allocator: std.mem.Allocator,
    uneval_args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError![]LispType {
    var args_arr = std.ArrayListUnmanaged(LispType).initCapacity(allocator, uneval_args.len) catch outOfMemory();
    for (uneval_args) |arg| {
        const val = try core.eval(allocator, arg, env, err_ctx);
        args_arr.appendAssumeCapacity(val);
    }
    return args_arr.items;
}

pub fn not(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len != 1) {
        return err_ctx.wrongNumberOfArguments(1, args_.len);
    }

    const args = try evalArgs(allocator, args_, env, err_ctx);
    return switch (args[0]) {
        .boolean => |b| .{ .boolean = !b },
        .nil => LispType.lisp_true,
        else => LispType.lisp_false,
    };
}

pub fn trueQuestion(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len != 1) {
        return err_ctx.wrongNumberOfArguments(1, args_.len);
    }

    const args = try evalArgs(allocator, args_, env, err_ctx);
    return switch (args[0]) {
        .boolean => args[0],
        else => LispType.lisp_false,
    };
}

pub fn falseQuestion(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len != 1) {
        return err_ctx.wrongNumberOfArguments(1, args_.len);
    }

    const args = try evalArgs(allocator, args_, env, err_ctx);
    return switch (args[0]) {
        .boolean => |b| .{ .boolean = !b },
        else => LispType.lisp_false,
    };
}

pub fn eql(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len < 2) {
        return err_ctx.wrongNumberOfArguments(2, args.len);
    }

    const fst = try core.eval(allocator, args[0], env, err_ctx);

    return for (args[1..]) |a| {
        const val = try core.eval(allocator, a, env, err_ctx);
        if (!fst.eql(val)) break LispType.lisp_false;
    } else blk: {
        break :blk LispType.lisp_true;
    };
}

pub fn notEql(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    const ret = try eql(allocator, args, env, err_ctx);
    return .{ .boolean = !ret.boolean };
}

pub fn cmp(
    allocator: std.mem.Allocator,
    args: []LispType,
    err_ctx: *errors.Context,
    env: *Env,
    cmpFn: fn (f32, f32) bool,
) LispError!LispType {
    if (args.len < 2) {
        return err_ctx.wrongNumberOfArguments(2, args.len);
    }

    var args_eval = std.ArrayListUnmanaged(LispType).initCapacity(allocator, args.len) catch outOfMemory();
    for (args) |arg| {
        const val = try core.eval(allocator, arg, env, err_ctx);
        args_eval.appendAssumeCapacity(val);
    }

    const v1: f32 = switch (args_eval.items[0]) {
        .int => |i| @floatFromInt(i),
        .float => |f| f,
        else => return err_ctx.wrongParameterType("Operands", "int or float"),
    };

    return for (args_eval.items[1..]) |a| {
        const v2: f32 = switch (a) {
            .int => |i| @floatFromInt(i),
            .float => |f| f,
            else => return err_ctx.wrongParameterType("Operands", "int or float"),
        };
        if (!cmpFn(v1, v2)) break LispType.lisp_false;
    } else blk: {
        break :blk .{ .boolean = true };
    };
}

pub fn less(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    const lessFn = struct {
        pub fn f(v1: f32, v2: f32) bool {
            return v1 < v2;
        }
    }.f;
    return cmp(allocator, args, err_ctx, env, lessFn);
}

pub fn lessEql(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    const lessFn = struct {
        pub fn f(v1: f32, v2: f32) bool {
            return v1 <= v2;
        }
    }.f;
    return cmp(allocator, args, err_ctx, env, lessFn);
}

pub fn bigger(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    const lessFn = struct {
        pub fn f(v1: f32, v2: f32) bool {
            return v1 > v2;
        }
    }.f;
    return cmp(allocator, args, err_ctx, env, lessFn);
}

pub fn biggerEql(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    const lessFn = struct {
        pub fn f(v1: f32, v2: f32) bool {
            return v1 >= v2;
        }
    }.f;
    return cmp(allocator, args, err_ctx, env, lessFn);
}

/// Adds all elements of the list/vector.
/// The return type is based on the first argument of the function.
/// @argument &: int | float | string | list | vector
/// @return: int | float | string | list | vector
pub fn add(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    const args = try evalArgs(allocator, args_, env, err_ctx);

    if (args.len == 0) {
        return err_ctx.atLeastNArguments(1);
    }

    switch (args[0]) {
        .int => |i| {
            var acc: i32 = i;
            for (args[1..]) |value| switch (value) {
                .int => |i_val| acc += i_val,
                else => return err_ctx.wrongParameterType("'+' argument", "int"),
            };
            return .{ .int = acc };
        },
        .float => |f| {
            var acc: f32 = f;
            for (args[1..]) |value| switch (value) {
                .float => |f_val| acc += f_val,
                .int => |i_val| acc += @floatFromInt(i_val),
                else => return err_ctx.wrongParameterType("'+' argument", "float"),
            };
            return .{ .float = acc };
        },
        .string => {
            var acc = LispType.String.initString(allocator, "");
            for (args) |arg| switch (arg) {
                .string => |s| acc.string.addMut(allocator, s),
                else => return err_ctx.wrongParameterType("'+' argument", "string"),
            };
            return acc;
        },
        .list, .vector => |arr| {
            var acc = switch (arr.array_type) {
                .list => LispType.Array.emptyList(),
                .vector => LispType.Array.emptyVector(),
            };

            for (args) |arg| switch (arg) {
                .list, .vector => |vs| switch (acc) {
                    inline .list, .vector => |*l| l.addMut(allocator, vs),
                    else => unreachable,
                },
                else => return err_ctx.wrongParameterType("'+' argument", "list or vector"),
            };
            return acc;
        },
        else => return err_ctx.wrongParameterType("'+' argument", "int, float, string, list or vector"),
    }
}

/// Subtracts all element from the tail of the argument list from the head. If only one
/// argument is passed, then it will be negated and returned.
/// @argument &: int | float
/// @return: int | float
pub fn sub(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    const args = try evalArgs(allocator, args_, env, err_ctx);

    if (args.len == 0) {
        return err_ctx.atLeastNArguments(1);
    }

    if (args.len == 1) {
        return switch (args[0]) {
            .int => |i| .{ .int = -i },
            .float => |f| .{ .float = -f },
            else => err_ctx.wrongParameterType("'-' arguments", "int or float"),
        };
    }

    switch (args[0]) {
        .int => |i| {
            var acc: i32 = i;
            for (args[1..]) |value| switch (value) {
                .int => |i_val| acc -= i_val,
                else => return err_ctx.wrongParameterType("'-' arguments", "int or float"),
            };
            return .{ .int = acc };
        },
        .float => |f| {
            var acc: f32 = f;
            for (args[1..]) |value| switch (value) {
                .float => |f_val| acc -= f_val,
                .int => |i_val| acc -= @floatFromInt(i_val),
                else => return err_ctx.wrongParameterType("'-' arguments", "int or float"),
            };
            return .{ .float = acc };
        },
        else => return err_ctx.wrongParameterType("'-' arguments", "int or float"),
    }
}

/// Multiplies all arguments.
/// @argument &: int | float
/// @return: int | float
pub fn mul(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    const args = try evalArgs(allocator, args_, env, err_ctx);

    if (args.len == 0) {
        return err_ctx.atLeastNArguments(1);
    }

    switch (args[0]) {
        .int => |i| {
            var acc: i32 = i;
            for (args[1..]) |value|
                switch (value) {
                    .int => |i_val| acc *= i_val,
                    else => return err_ctx.wrongParameterType("'*' arguments", "int"),
                };
            return .{ .int = acc };
        },
        .float => |f| {
            var acc: f32 = f;
            for (args[1..]) |value|
                switch (value) {
                    .float => |f_val| acc *= f_val,
                    .int => |i_val| acc *= @floatFromInt(i_val),
                    else => return err_ctx.wrongParameterType("'*' arguments", "int or float"),
                };
            return .{ .float = acc };
        },
        else => return err_ctx.wrongParameterType("'*' arguments", "int or float"),
    }
}

/// Divides the head of the argument list to its tail. Raises a division by zero error if the tail
/// contains '0' as an element.
/// @argument &: int | float
/// @return: int | float
pub fn div(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    const args = try evalArgs(allocator, args_, env, err_ctx);

    if (args.len == 0) {
        return err_ctx.atLeastNArguments(1);
    }

    switch (args[0]) {
        .int => |i| {
            var acc: i32 = i;
            for (args[1..]) |value| switch (value) {
                .int => |i_val| {
                    if (i_val != 0) acc = @divFloor(acc, i_val) else return err_ctx.divisionByZero();
                },
                else => return err_ctx.wrongParameterType("'/' arguments", "int"),
            };
            return .{ .int = acc };
        },
        .float => |f| {
            var acc: f32 = f;
            for (args[1..]) |value| {
                var v: f32 = 0;
                switch (value) {
                    .float => |f_val| v = f_val,
                    .int => |i_val| v = @floatFromInt(i_val),
                    else => return err_ctx.wrongParameterType("'/' arguments", "int or float"),
                }
                if (v != 0) acc /= v else return err_ctx.divisionByZero();
            }
            return .{ .float = acc };
        },
        else => return err_ctx.wrongParameterType("'/' arguments", "int or float"),
    }
}

pub fn map(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len != 2) {
        return err_ctx.wrongNumberOfArguments(2, args_.len);
    }

    const args = try evalArgs(allocator, args_, env, err_ctx);

    const func = switch (args[0]) {
        .function => args[0],
        else => return err_ctx.wrongParameterType("'map' first argument", "function"),
    };

    const arr = switch (args[1]) {
        .list, .vector => |arr| arr.getItems(),
        else => return err_ctx.wrongParameterType("'map' second argument", "list or vector"),
    };

    var ast = LispType.Array.initList(allocator, &[2]LispType{ func, .nil });
    var res = std.ArrayListUnmanaged(LispType).initCapacity(allocator, arr.len) catch outOfMemory();
    for (arr) |val| {
        ast.list.array.items[1] = val.clone(allocator);
        const ret = try core.eval(allocator, ast, env, err_ctx);
        res.appendAssumeCapacity(ret);
    }
    return switch (args[1]) {
        .list => LispType{ .list = .{ .array = res, .array_type = .list } },
        .vector => LispType{ .vector = .{ .array = res, .array_type = .vector } },
        else => undefined,
    };
}

pub fn apply(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len < 2) {
        return err_ctx.atLeastNArguments(2);
    }

    const args = try evalArgs(allocator, args_, env, err_ctx);
    const func = switch (args[0]) {
        .function => args[0],
        else => return err_ctx.wrongParameterType("'map' first argument", "function"),
    };

    var new_args = std.ArrayListUnmanaged(LispType).initCapacity(allocator, args.len + 1) catch outOfMemory();
    new_args.appendAssumeCapacity(func);
    for (args[1 .. args.len - 1]) |arg| {
        new_args.appendAssumeCapacity(arg);
    }

    const last = args[args.len - 1];
    switch (last) {
        .list, .vector => |arr| for (arr.getItems()) |val| {
            new_args.append(allocator, val) catch outOfMemory();
        },
        else => new_args.appendAssumeCapacity(last),
    }

    const ast = LispType{ .list = .{ .array = new_args, .array_type = .list } };
    return core.eval(allocator, ast, env, err_ctx);
}

/// Returns the arguments as a dict.
/// @argument &: any
/// @return: dict
pub fn dict(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len % 2 != 0) {
        return err_ctx.wrongNumberOfArguments(args_.len + 1, args_.len);
    }

    const args = try evalArgs(allocator, args_, env, err_ctx);

    var dict_ = LispType.Dict.init();
    for (0..args.len / 2) |i_| {
        const i = 2 * i_;
        const key = args[i];
        const value = args[i + 1];
        if (dict_.dict.addMut(allocator, key, value)) |_| {} else |err| switch (err) {
            errors.LispError.UnhashableType => return err_ctx.unhashableType(),
            else => return err,
        }
    }
    return dict_;
}

/// Returns a new dict with the given key value pair.
/// @argument dict: dict
/// @argument &: any
/// @return: dict
pub fn assoc(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len < 3) {
        return err_ctx.atLeastNArguments(3);
    }
    if (args_.len % 2 != 1) {
        return err_ctx.wrongNumberOfArguments(args_.len + 1, args_.len);
    }

    const args = try evalArgs(allocator, args_, env, err_ctx);

    var dict_ = switch (args[0]) {
        .dict => |d| d.clone(allocator),
        else => return err_ctx.wrongParameterType("'assoc' first argument", "dict"),
    };
    for (0..args.len / 2) |i_| {
        const i = 2 * i_ + 1;
        const key = args[i];
        const value = args[i + 1];
        if (dict_.dict.addMut(allocator, key, value)) |_| {} else |err| switch (err) {
            errors.LispError.UnhashableType => return err_ctx.unhashableType(),
            else => return err,
        }
    }
    return dict_;
}

/// Returns a new dict without the given keys.
/// @argument dict: dict
/// @argument &: int, string, symbol, keyword
/// @return: dict
pub fn dissoc(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len < 2) {
        return err_ctx.atLeastNArguments(2);
    }

    const args = try evalArgs(allocator, args_, env, err_ctx);

    var dict_ = switch (args[0]) {
        .dict => |d| d.clone(allocator),
        else => return err_ctx.wrongParameterType("'assoc' first argument", "dict"),
    };
    for (args[1..]) |key| {
        try dict_.dict.remove(key);
    }
    return dict_;
}

/// Returns the value associated with the given key.
/// @argument dict: dict
/// @argument key: int, string, symbol, keyword
/// @return: any
pub fn get(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len < 2) {
        return err_ctx.wrongNumberOfArguments(2, args_.len);
    }

    const args = try evalArgs(allocator, args_, env, err_ctx);

    const dict_ = switch (args[0]) {
        .dict => args[0],
        else => return err_ctx.wrongParameterType("'assoc' first argument", "dict"),
    };

    if (!LispType.Dict.isHashable(args[1])) return err_ctx.unhashableType();

    return dict_.dict.map.get(args[1]) orelse .nil;
}

/// Returns true if the given key is present at the given dictionary.
/// @argument dict: dict
/// @argument key: int, string, symbol, keyword
/// @return: any
pub fn contains(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len < 2) {
        return err_ctx.wrongNumberOfArguments(2, args_.len);
    }

    const args = try evalArgs(allocator, args_, env, err_ctx);

    const dict_ = switch (args[0]) {
        .dict => args[0],
        else => return err_ctx.wrongParameterType("'assoc' first argument", "dict"),
    };

    if (!LispType.Dict.isHashable(args[1])) return err_ctx.unhashableType();

    return .{ .boolean = dict_.dict.map.contains(args[1]) };
}

fn dictIterator(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
    iterator: anytype,
) LispError!LispType {
    if (args_.len != 1) {
        return err_ctx.wrongNumberOfArguments(1, args_.len);
    }

    const args = try evalArgs(allocator, args_, env, err_ctx);

    const dict_ = switch (args[0]) {
        .dict => |d| d.map,
        else => return err_ctx.wrongParameterType("'keys' first argument", "dict"),
    };

    var list_ = std.ArrayListUnmanaged(LispType).initCapacity(allocator, dict_.count()) catch outOfMemory();
    var key_iter = iterator(dict_);
    while (key_iter.next()) |key| {
        list_.appendAssumeCapacity(key.*);
    }
    return .{ .list = .{ .array = list_, .array_type = .list } };
}

/// Returns a list with the given dict keys.
/// @argument dict: dict
/// @return: list
pub fn keys(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    return dictIterator(
        allocator,
        args_,
        env,
        err_ctx,
        LispType.Dict.Map.keyIterator,
    );
}

/// Returns a list with the given dict values.
/// @argument dict: dict
/// @return: list
pub fn values(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    return dictIterator(
        allocator,
        args_,
        env,
        err_ctx,
        LispType.Dict.Map.valueIterator,
    );
}

/// Returns the arguments as a list.
/// @argument &: any
/// @return: list
pub fn list(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    const args = try evalArgs(allocator, args_, env, err_ctx);
    return LispType.Array.initList(allocator, args);
}

/// Returns the arguments as a vector.
/// @argument &: any
/// @return: vector
pub fn vector(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    const args = try evalArgs(allocator, args_, env, err_ctx);
    return LispType.Array.initVector(allocator, args);
}

/// Converts the given list into a vector.
/// @argument 1: list
/// @return: vector
pub fn vec(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len != 1) {
        return err_ctx.wrongNumberOfArguments(1, args_.len);
    }
    const args = try evalArgs(allocator, args_, env, err_ctx);
    return switch (args[0]) {
        .list, .vector => |l| LispType.Array.initVector(allocator, l.getItems()),
        else => err_ctx.wrongParameterType("'vec' argument", "list or vector"),
    };
}

/// Returns the nth element of the list/vector.
/// @argument 1: list | vector
/// @argument 2: int
/// @return: any
pub fn nth(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len > 2) {
        return err_ctx.wrongNumberOfArguments(2, args_.len);
    }

    const args = try evalArgs(allocator, args_, env, err_ctx);
    switch (args[0]) {
        .list, .vector, .string => {},
        else => return err_ctx.wrongParameterType("'nth' first argument", "list or vector"),
    }

    if (args[1] != .int) {
        return err_ctx.wrongParameterType("'nth' second argument", "int");
    }

    const n: usize = @intCast(args[1].int);
    switch (args[0]) {
        .list, .vector => |arr| {
            const collection = arr.getItems();
            if (n >= collection.len) {
                return err_ctx.indexOutOfRange(n, collection.len);
            }
            return collection[n];
        },
        .string => |s| {
            const collection = s.getStr();
            if (n >= collection.len) {
                return err_ctx.indexOutOfRange(n, collection.len);
            }
            return LispType.String.initString(allocator, collection[n .. n + 1]);
        },
        else => unreachable,
    }
}

/// Returns the first element of the collection.
/// @argument 1: list | vector | string
/// @return: any
pub fn head(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    var new_args = [_]LispType{ args[0], .{ .int = 0 } };
    return if (nth(allocator, &new_args, env, err_ctx)) |v| v else |err| switch (err) {
        errors.LispError.IndexOutOfRange => err_ctx.emptyCollection(),
        else => err,
    };
}

/// Returns the last elements of the collection.
/// @argument 1: list | vector
/// @return: any
pub fn tail(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args_.len);
    }

    const args = try evalArgs(allocator, args_, env, err_ctx);
    return switch (args[0]) {
        inline .list, .vector, .string => |c| if (c.tail(allocator)) |tail_| tail_ else err_ctx.emptyCollection(),
        else => err_ctx.wrongParameterType("'tail' argument", "list, vector or string"),
    };
}

/// Returns true if the first argument is a list.
/// @argument 1: any
/// @return: bool
pub fn listQuestion(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len == 0) {
        return LispType.lisp_false;
    }

    if (args.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const arg = try core.eval(allocator, args[0], env, err_ctx);
    return .{ .boolean = arg == .list };
}

/// Returns true if the first argument is an empty collection. Returns false otherwise.
/// @argument 1: any
/// @return: bool
pub fn emptyQuestion(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len == 0) {
        return .{ .boolean = true };
    }

    if (args.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const arg = try core.eval(allocator, args[0], env, err_ctx);
    return switch (arg) {
        .list, .vector => |arr| .{ .boolean = arr.getItems().len == 0 },
        .dict => |d| .{ .boolean = d.map.size == 0 },
        else => LispType.lisp_false,
    };
}

/// Returns the amount of items in the collection.
/// @argument 1: list | vector | dict
/// @return: int
pub fn count(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len == 0) {
        return .{ .int = 0 };
    }

    if (args.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const arg = try core.eval(allocator, args[0], env, err_ctx);
    return switch (arg) {
        .list, .vector => |arr| .{ .int = @intCast(arr.getItems().len) },
        .dict => |d| .{ .int = @intCast(d.map.size) },
        else => .{ .int = 0 },
    };
}

/// Returns the first argument prepended to the second argument.
/// @argument 1: any
/// @argument 2: list | vector
/// @return: list | vector
pub fn cons(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len != 2) {
        return err_ctx.wrongNumberOfArguments(2, args_.len);
    }

    const args = try evalArgs(allocator, args_, env, err_ctx);

    const arr = switch (args[1]) {
        .list, .vector => |arr| arr,
        else => return err_ctx.wrongParameterType("'const' second argument", "list or vector"),
    };
    return LispType.Array.prepend(allocator, args[0], arr);
}

/// Concatenates all lists/vectors together.
/// @argument 1: list | vector
/// @return: list | vector
pub fn concat(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    const args = try evalArgs(allocator, args_, env, err_ctx);

    if (args.len == 0) {
        return LispType.Array.emptyList();
    }

    return switch (args[0]) {
        inline .list, .vector => add(allocator, args, env, err_ctx),
        else => return err_ctx.wrongParameterType("'concat' arguments", "list or vector"),
    };
}

/// Returns an atom holding the value of the first argument.
/// @argument 1: any
pub fn atom(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try core.eval(allocator, args[0], env, err_ctx);
    return LispType.Atom.init(allocator, val);
}

/// Returns true if the first argument is an atom.
/// @argument 1: any
/// @return: bool
pub fn atomQuestion(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try core.eval(allocator, args[0], env, err_ctx);
    return .{ .boolean = val == .atom };
}

/// Returns the value which the given atom currently holds.
/// @argument 1: atom
/// @return: any
pub fn deref(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try core.eval(allocator, args[0], env, err_ctx);
    return switch (val) {
        .atom => |a| a.get(),
        else => err_ctx.wrongParameterType("'deref' argument", "atom"),
    };
}

/// Switches the value which the given atom currently holds to the new passed value.
/// @argument 1: atom
/// @argument 2: any
/// @return: any
pub fn resetBang(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len != 2) {
        return err_ctx.wrongNumberOfArguments(2, args.len);
    }

    var val = try core.eval(allocator, args[0], env, err_ctx);
    return switch (val) {
        .atom => |*a| a.reset(allocator, args[1]),
        else => err_ctx.wrongParameterType("'reset!' first argument", "atom"),
    };
}

/// Switches the value which the given atom currently holds to the result of the passed function with
/// the atom's current value as the first argument. Any other arguments will be passed into the function in
/// order.
/// @argument 1: atom
/// @argument 2: function
/// @argument &: any
/// @return: any
pub fn swapBang(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len < 2) {
        return err_ctx.atLeastNArguments(2);
    }

    const args = try evalArgs(allocator, args_, env, err_ctx);
    if (args[0] != .atom) {
        return err_ctx.wrongParameterType("'swap!' first argument", "atom");
    }

    if (args[1] != .function) {
        return err_ctx.wrongParameterType("'swap!' second argument", "function");
    }

    var fn_arr = [_]LispType{ args[1], args[0].atom.get() };
    var fn_list = LispType.Array.initList(allocator, &fn_arr);

    for (args[2..]) |arg| {
        fn_list.list.appendMut(allocator, arg);
    }

    const val = try core.eval(allocator, fn_list, env, err_ctx);
    return args[0].atom.reset(allocator, val);
}

/// Returns a symbol named after the contents of the string.
/// @argument 1: str
/// @return: symbol
pub fn symbol(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len != 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try core.eval(allocator, args[0], env, err_ctx);
    return switch (val) {
        .string => |s| LispType.String.initSymbol(allocator, s.getStr()),
        else => err_ctx.wrongParameterType("'symbol' argument", "string"),
    };
}

/// Returns a keyword named after the contents of the string.
/// @argument 1: str | keyword
/// @return: keyword
pub fn keyword(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len != 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try core.eval(allocator, args[0], env, err_ctx);
    return switch (val) {
        .string => |s| blk: {
            var k = LispType.String.initKeyword(allocator, ":");
            k.keyword.addMut(allocator, s);
            break :blk k;
        },
        .keyword => val,
        else => err_ctx.wrongParameterType("'keyword' argument", "string or keyword"),
    };
}

/// Returns true if the first argument is nil.
/// @argument 1: any
/// @return: bool
pub fn nilQuestion(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try core.eval(allocator, args[0], env, err_ctx);
    return .{ .boolean = val == .nil };
}

/// Returns true if the first argument is a boolean.
/// @argument 1: any
/// @return: bool
pub fn boolQuestion(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try core.eval(allocator, args[0], env, err_ctx);
    return .{ .boolean = val == .boolean };
}

/// Returns true if the first argument is a symbol.
/// @argument 1: any
/// @return: bool
pub fn symbolQuestion(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    if (args[0] == .symbol) {
        return LispType.lisp_true;
    }
    const val = try core.eval(allocator, args[0], env, err_ctx);
    return .{ .boolean = val == .symbol };
}

/// Returns true if the first argument is a keyword.
/// @argument 1: any
/// @return: bool
pub fn keywordQuestion(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try core.eval(allocator, args[0], env, err_ctx);
    return .{ .boolean = val == .keyword };
}

/// Returns true if the first argument is an interger.
/// @argument 1: any
/// @return: bool
pub fn dictQuestion(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try core.eval(allocator, args[0], env, err_ctx);
    return .{ .boolean = val == .dict };
}

/// Returns true if the first argument is a vector.
/// @argument 1: any
/// @return: bool
pub fn vectorQuestion(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try core.eval(allocator, args[0], env, err_ctx);
    return .{ .boolean = val == .vector };
}

/// Returns true if the first argument is a list or vector.
/// @argument 1: any
/// @return: bool
pub fn sequentialQuestion(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try core.eval(allocator, args[0], env, err_ctx);
    return .{ .boolean = val == .vector or val == .list };
}

/// Returns true if the first argument is a float.
/// @argument 1: any
/// @return: bool
pub fn floatQuestion(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try core.eval(allocator, args[0], env, err_ctx);
    return .{ .boolean = val == .float };
}

/// Returns true if the first argument is an interger.
/// @argument 1: any
/// @return: bool
pub fn intQuestion(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try core.eval(allocator, args[0], env, err_ctx);
    return .{ .boolean = val == .int };
}

/// Transforms the given arguments to string and concatenates it.
/// @argument &: any
/// @return: string
pub fn str(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    const args = try evalArgs(allocator, args_, env, err_ctx);

    if (args.len == 0) {
        return LispType.String.initString(allocator, "");
    }

    var acc = LispType.String.initString(allocator, "");
    for (args) |arg| {
        const s = switch (arg) {
            .string => |s| s.getStr(),
            else => arg.toStringFull(allocator) catch outOfMemory(),
        };
        acc.string.addChars(allocator, s);
    }
    return acc;
}

/// Evaluates the given expression into a lisp value.
/// @argument 1: string
/// @return: any
pub fn readStr(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len != 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try core.eval(allocator, args[0], env, err_ctx);
    return switch (val) {
        .string => |s| reader.readStr(allocator, s.getStr()) catch |err| err_ctx.parserError(err),
        else => err_ctx.wrongParameterType("'read-str' argument", "string"),
    };
}

/// Returns the given file content as a string.
/// @argument 1: string
/// @return: string
pub fn slurp(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len != 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try core.eval(allocator, args[0], env, err_ctx);
    const path = switch (val) {
        .string => |s| s.getStr(),
        else => return err_ctx.wrongParameterType("'slurp' argument", "string"),
    };

    var file = std.fs.cwd().openFile(path, .{}) catch return err_ctx.fileDoesNotExit(path);
    defer file.close();

    const file_size = file.getEndPos() catch return err_ctx.ioError();
    const buffer = allocator.alloc(u8, file_size) catch outOfMemory();
    defer allocator.free(buffer);

    _ = file.readAll(buffer) catch return err_ctx.ioError();
    return LispType.String.initString(allocator, buffer);
}

pub fn loadFile(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    const ret = try slurp(allocator, args, env, err_ctx);
    const src = std.fmt.allocPrint(allocator, "(do {s} nil)", .{ret.string.getStr()}) catch outOfMemory();
    const ast = reader.readStr(allocator, src) catch |err| {
        return err_ctx.parserError(err);
    };
    return core.eval(allocator, ast, env, err_ctx);
}

//////////////////////////////////////////////////////////////////////////////////////////////////
/// These functions are examples on how to integrate a custom type (zig struct to lisp record) ///
//////////////////////////////////////////////////////////////////////////////////////////////////

/// Create an enum
/// @argument selected: int
/// @argument &: keyword
/// @return: the newly created enum.
pub fn enumInit(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len < 2) {
        return err_ctx.atLeastNArguments(2);
    }

    const args = try evalArgs(allocator, args_, env, err_ctx);
    const selected: usize = switch (args[0]) {
        .int => |i_| blk: {
            const i: usize = @intCast(i_);
            break :blk if (i < args.len) i else return err_ctx.indexOutOfRange(i, args.len - 1);
        },
        else => return err_ctx.wrongParameterType("'init-enum' first argument", "int"),
    };

    var option_array = std.ArrayListUnmanaged([]const u8).initCapacity(allocator, args.len - 1) catch outOfMemory();
    for (args[1..]) |v| {
        if (v != .keyword) {
            return err_ctx.wrongParameterType("'init-enum' options", "keyword");
        }
        option_array.appendAssumeCapacity(v.keyword.getStr());
    }

    const enum_ = Enum.init(option_array.items, selected) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Could not create enum: {any}.", .{err}) catch outOfMemory();
        return err_ctx.customError(msg);
    };
    return LispType.Record.init(allocator, enum_);
}

fn enumGet(
    allocator: std.mem.Allocator,
    arg_: LispType,
    env: *Env,
    err_ctx: *errors.Context,
    arg_name: []const u8,
) LispError!*Enum {
    const arg = try core.eval(allocator, arg_, env, err_ctx);
    return switch (arg) {
        .record => |r| r.as(Enum) orelse err_ctx.wrongParameterType(arg_name, "enum"),
        else => err_ctx.wrongParameterType(arg_name, "enum"),
    };
}

/// Get an enum selected value
/// @argument 1: record
/// @return: keyword
pub fn enumSelected(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len != 1) {
        return err_ctx.wrongNumberOfArguments(1, args_.len);
    }

    const enum_ = try enumGet(allocator, args_[0], env, err_ctx, "'enum-selected' argument");
    return LispType.String.initKeyword(allocator, enum_.getSelected());
}

/// Get an enum selected index
/// @argument 1: record
/// @return: int
pub fn enumIndex(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len != 1) {
        return err_ctx.wrongNumberOfArguments(1, args_.len);
    }

    const enum_ = try enumGet(allocator, args_[0], env, err_ctx, "'enum-index' argument");
    return .{ .int = @intCast(enum_.getSelectedIndex()) };
}

/// We can add mutability to our functions, although not recommended.
/// This changes the enum option.
/// @argument 1: record
/// @argument 2: keyword
/// @return: nil
pub fn enumSetSelected(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len != 2) {
        return err_ctx.wrongNumberOfArguments(2, args_.len);
    }

    const new_keyword = switch (try core.eval(allocator, args_[1], env, err_ctx)) {
        .keyword => |k| k.getStr(),
        else => return err_ctx.wrongParameterType("'enum-set-option' second argument", "keyword"),
    };

    var enum_ = try enumGet(allocator, args_[0], env, err_ctx, "'enum-index' argument");
    enum_.setSelected(new_keyword) catch {
        const msg = std.fmt.allocPrint(allocator, "Option does not exist on enum: {s}.", .{new_keyword}) catch outOfMemory();
        return err_ctx.customError(msg);
    };
    return .nil;
}

/// Changes the enum index.
/// @argument 1: record
/// @argument 2: int
/// @return: nil
pub fn enumSetIndex(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args_.len != 2) {
        return err_ctx.wrongNumberOfArguments(2, args_.len);
    }

    const new_index: usize = switch (try core.eval(allocator, args_[1], env, err_ctx)) {
        .int => |i| @intCast(i),
        else => return err_ctx.wrongParameterType("'enum-set-option' second argument", "keyword"),
    };

    var enum_ = try enumGet(allocator, args_[0], env, err_ctx, "'enum-index' argument");
    enum_.setIndex(new_index) catch {
        return err_ctx.indexOutOfRange(new_index, enum_.options.len);
    };
    return .nil;
}

const arrowPos = enum {
    first,
    last,
};

pub fn arrow(
    allocator: std.mem.Allocator,
    args: []LispType,
    pos: arrowPos,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len < 2) {
        return err_ctx.atLeastNArguments(2);
    }

    var ret = try core.eval(allocator, args[0], env, err_ctx);
    for (args[1..]) |arg| {
        const ast = switch (arg) {
            .symbol => try core.eval(allocator, arg, env, err_ctx),
            .list, .function => arg,
            else => return err_ctx.wrongParameterType("'->' tail arguments", "list or function"),
        };
        ret = switch (ast) {
            .function => try core.eval(
                allocator,
                LispType.Array.initList(allocator, &[_]LispType{ ast, ret }),
                env,
                err_ctx,
            ),
            .list => |l| switch (pos) {
                .first => try core.eval(allocator, l.insert(allocator, 1, ret), env, err_ctx),
                .last => try core.eval(allocator, l.append(allocator, ret), env, err_ctx),
            },
            else => return err_ctx.wrongParameterType("'arrow' tail arguments", "list or function"),
        };
    }

    return ret;
}

/// Applies the first argument to the subsequent functions at the last position.
/// @argument 1: any
/// @argument &: function
/// @return: any
pub fn arrowFirst(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    return arrow(allocator, args, .first, env, err_ctx);
}

/// Applies the first argument to the subsequent functions in the first position.
/// @argument 1: any
/// @argument &: function
/// @return: any
pub fn arrowLast(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    return arrow(allocator, args, .last, env, err_ctx);
}
