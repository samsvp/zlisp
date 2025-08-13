const std = @import("std");
const eval = @import("eval.zig").eval;
const errors = @import("errors.zig");
const Env = @import("env.zig").Env;
const Reader = @import("reader.zig");
const LispError = @import("errors.zig").LispError;
const LispType = @import("types.zig").LispType;
const outOfMemory = @import("utils.zig").outOfMemory;

pub const Interpreter = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    buffer: std.ArrayListUnmanaged(u8) = .empty,
    env: *Env,
    err_ctx: errors.Context,

    const Self = @This();

    pub fn init(
        allocator_: std.mem.Allocator,
        buffer_size: usize,
    ) Self {
        var arena = std.heap.ArenaAllocator.init(allocator_);
        const allocator = arena.allocator();

        const err_ctx = errors.Context.init(allocator);
        const buffer = std.ArrayListUnmanaged(u8).initCapacity(allocator, buffer_size) catch outOfMemory();
        const env = Env.init(allocator).setFunctions();
        return .{
            .allocator = allocator,
            .arena = arena,
            .err_ctx = err_ctx,
            .buffer = buffer,
            .env = env,
        };
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    pub fn run(self: *Self, value: LispType) LispError!LispType {
        return eval(self.arena.allocator(), value, self.env, &self.err_ctx);
    }

    pub fn print(self: *Self, value: LispType) []const u8 {
        self.buffer.clearRetainingCapacity();
        return value.toString(self.buffer.allocatedSlice());
    }

    pub fn rep(self: *Self, text: []const u8) ![]const u8 {
        const allocator = self.arena.allocator();
        const val = try Reader.readStr(allocator, text);
        const ret = try self.run(val);
        return self.print(ret);
    }
};
