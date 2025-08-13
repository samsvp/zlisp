const std = @import("std");
const eval = @import("eval.zig").eval;
const errors = @import("errors.zig");
const Env = @import("env.zig").Env;
const Reader = @import("reader.zig");
const LispError = @import("errors.zig").LispError;
const LispType = @import("types.zig").LispType;
const outOfMemory = @import("utils.zig").outOfMemory;

pub const Interpreter = struct {
    arena: std.heap.ArenaAllocator,
    eval_arena: std.heap.ArenaAllocator,
    buffer: std.ArrayListUnmanaged(u8) = .empty,
    env: *Env,
    err_ctx: errors.Context,

    const Self = @This();

    pub fn init(
        base_allocator: std.mem.Allocator,
        buffer_size: usize,
    ) Self {
        var arena = std.heap.ArenaAllocator.init(base_allocator);
        const buffer = std.ArrayListUnmanaged(u8).initCapacity(arena.allocator(), buffer_size) catch outOfMemory();

        const eval_arena = std.heap.ArenaAllocator.init(base_allocator);

        const err_ctx = errors.Context.init(base_allocator);
        const env = Env.init(base_allocator).setFunctions();
        return .{
            .arena = arena,
            .eval_arena = eval_arena,
            .err_ctx = err_ctx,
            .buffer = buffer,
            .env = env,
        };
    }

    pub fn deinit(self: *Self) void {
        self.err_ctx.deinit();
        self.env.deinit();
        self.arena.deinit();
        self.eval_arena.deinit();
    }

    pub fn run(self: *Self, value: LispType) LispError!LispType {
        defer _ = self.eval_arena.reset(.retain_capacity);
        const s = try eval(self.eval_arena.allocator(), value, self.env, &self.err_ctx);
        return s.clone(self.arena.allocator());
    }

    pub fn print(self: *Self, value: LispType) []const u8 {
        self.buffer.clearRetainingCapacity();
        return value.toString(self.buffer.allocatedSlice());
    }

    pub fn rep(self: *Self, text: []const u8) ![]const u8 {
        const allocator = self.arena.allocator();
        const val = try Reader.readStr(allocator, text);
        const ret = self.run(val) catch |err| {
            std.debug.print("ERROR: {s}\n", .{self.err_ctx.buffer.items});
            return err;
        };
        return self.print(ret);
    }
};
