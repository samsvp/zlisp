const std = @import("std");
const Env = @import("env.zig").Env;
const LispType = @import("types.zig").LispType;
const errors = @import("errors.zig");
const LispError = errors.LispError;

pub fn eval(
    allocator: std.mem.Allocator,
    s: LispType,
    env: *Env,
    err_ctx: *errors.Context,
) LispError!LispType {
    _ = err_ctx;
    _ = env;
    return s.clone(allocator);
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
