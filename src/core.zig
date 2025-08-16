const std = @import("std");
const Env = @import("env.zig").Env;
const errors = @import("errors.zig");
const LispType = @import("types.zig").LispType;
const LispError = errors.LispError;
const reader = @import("reader.zig");
const eval = @import("eval.zig");
const outOfMemory = @import("utils.zig").outOfMemory;

pub fn eql(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len < 2) {
        return err_ctx.wrongNumberOfArguments(2, args.len);
    }

    const fst = try eval.eval(allocator, args[0], env, err_ctx);

    return for (args[1..]) |a| {
        const val = try eval.eval(allocator, a, env, err_ctx);
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
        const val = try eval.eval(allocator, arg, env, err_ctx);
        args_eval.appendAssumeCapacity(val);
    }

    const v1: f32 = switch (args[0]) {
        .int => |i| @floatFromInt(i),
        .float => |f| f,
        else => return err_ctx.wrongParameterType("Operands", "int or float"),
    };

    return for (args[1..]) |a| {
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

pub fn evalArgs(
    allocator: std.mem.Allocator,
    uneval_args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError![]LispType {
    var args_arr = std.ArrayListUnmanaged(LispType).initCapacity(allocator, uneval_args.len) catch outOfMemory();
    for (uneval_args) |arg| {
        const val = try eval.eval(allocator, arg, env, err_ctx);
        args_arr.appendAssumeCapacity(val);
    }
    return args_arr.items;
}

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

pub fn list(
    allocator: std.mem.Allocator,
    args_: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    const args = try evalArgs(allocator, args_, env, err_ctx);
    return LispType.Array.initList(allocator, args);
}

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

    const arg = try eval.eval(allocator, args[0], env, err_ctx);
    return .{ .boolean = arg == .list };
}

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

    const arg = try eval.eval(allocator, args[0], env, err_ctx);
    return switch (arg) {
        .list, .vector => |arr| .{ .boolean = arr.getItems().len == 0 },
        .dict => |d| .{ .boolean = d.map.size == 0 },
        else => LispType.lisp_false,
    };
}

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

    const arg = try eval.eval(allocator, args[0], env, err_ctx);
    return switch (arg) {
        .list, .vector => |arr| .{ .int = @intCast(arr.getItems().len) },
        .dict => |d| .{ .int = @intCast(d.map.size) },
        else => .{ .int = 0 },
    };
}

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

pub fn atom(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try eval.eval(allocator, args[0], env, err_ctx);
    return LispType.Atom.init(allocator, val);
}

pub fn atomQuestion(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try eval.eval(allocator, args[0], env, err_ctx);
    return .{ .boolean = val == .atom };
}

pub fn deref(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len > 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try eval.eval(allocator, args[0], env, err_ctx);
    return switch (val) {
        .atom => |a| a.get(),
        else => err_ctx.wrongParameterType("'deref' argument", "atom"),
    };
}

pub fn resetBang(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len != 2) {
        return err_ctx.wrongNumberOfArguments(2, args.len);
    }

    var val = try eval.eval(allocator, args[0], env, err_ctx);
    return switch (val) {
        .atom => |*a| a.reset(allocator, args[1]),
        else => err_ctx.wrongParameterType("'reset!' first argument", "atom"),
    };
}

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

pub fn readStr(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len != 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try eval.eval(allocator, args[0], env, err_ctx);
    return switch (val) {
        .string => |s| reader.readStr(allocator, s.getStr()) catch |err| err_ctx.parserError(err),
        else => err_ctx.wrongParameterType("'readStr' argument", "string"),
    };
}

pub fn slurp(
    allocator: std.mem.Allocator,
    args: []LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    if (args.len != 1) {
        return err_ctx.wrongNumberOfArguments(1, args.len);
    }

    const val = try eval.eval(allocator, args[0], env, err_ctx);
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
