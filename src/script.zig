const std = @import("std");
const eval = @import("core.zig").eval;
const errors = @import("errors.zig");
const Env = @import("env.zig").Env;
const reader = @import("reader.zig");
const LispError = @import("errors.zig").LispError;
const LispType = @import("types.zig").LispType;
const outOfMemory = @import("utils.zig").outOfMemory;

pub const Script = struct {
    arena: std.heap.ArenaAllocator,
    eval_arena: std.heap.ArenaAllocator,
    print_arena: std.heap.ArenaAllocator,
    env: *Env,
    err_ctx: errors.Context,

    const Self = @This();

    pub fn init(base_allocator: std.mem.Allocator, global_env: *Env) Self {
        const arena = std.heap.ArenaAllocator.init(base_allocator);

        const eval_arena = std.heap.ArenaAllocator.init(base_allocator);
        const print_arena = std.heap.ArenaAllocator.init(base_allocator);

        const err_ctx = errors.Context.init(base_allocator);
        var env = Env.init(base_allocator);
        env.parent = global_env;

        return Self{
            .arena = arena,
            .eval_arena = eval_arena,
            .print_arena = print_arena,
            .err_ctx = err_ctx,
            .env = env,
        };
    }

    pub fn deinit(self: *Self) void {
        self.err_ctx.deinit();
        self.env.deinit();
        self.arena.deinit();
        self.eval_arena.deinit();
        self.print_arena.deinit();
    }

    pub fn loadFile(self: *Self, path: []const u8) !void {
        self.env.loadFile(path);
    }

    pub fn evalString(self: *Self, str: []const u8) !void {
        self.env.evalString(str);
    }

    pub fn run(self: *Self, allocator: std.mem.Allocator, value: LispType) LispError!LispType {
        defer _ = self.eval_arena.reset(.retain_capacity);
        const s = try eval(self.eval_arena.allocator(), value, self.env, &self.err_ctx);
        return s.clone(allocator);
    }

    pub fn print(self: *Self, value: LispType) []const u8 {
        _ = self.print_arena.reset(.retain_capacity);
        return value.toStringFull(self.print_arena.allocator()) catch outOfMemory();
    }

    pub fn re(self: *Self, text: []const u8) !LispType {
        _ = self.arena.reset(.retain_capacity);
        const allocator = self.arena.allocator();
        const val = try reader.readStr(allocator, text);
        return self.run(allocator, val);
    }

    pub fn rep(self: *Self, text: []const u8) ![]const u8 {
        const allocator = self.arena.allocator();
        const ret = self.re(text) catch blk: {
            const err_str = std.fmt.allocPrint(
                allocator,
                "ERROR: {s}\n",
                .{self.err_ctx.buffer.items},
            ) catch outOfMemory();
            break :blk LispType.String.initString(allocator, err_str);
        };
        return self.print(ret);
    }
};
