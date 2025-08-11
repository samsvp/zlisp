const std = @import("std");
const LispType = @import("types.zig").LispType;
const errors = @import("errors.zig");
const LispError = errors.LispError;

pub fn eval(allocator: std.mem.Allocator, s: LispType, err_ctx: *errors.Context) LispError!LispType {
    _ = err_ctx;
    return s.clone(allocator);
}

pub fn evalWrapper(allocator: std.mem.Allocator, s: []LispType, err_ctx: *errors.Context) LispError!LispType {
    if (s.len != 1) {
        return err_ctx.wrongNumberOfArguments(1, s.len);
    }

    return eval(allocator, s[0], err_ctx);
}
