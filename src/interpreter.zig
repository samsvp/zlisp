const std = @import("std");
const eval = @import("eval.zig").eval;
const errors = @import("errors.zig");
const Reader = @import("reader.zig");
const outOfMemory = @import("utils.zig").outOfMemory;

pub const Interpreter = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    buffer: std.ArrayListUnmanaged(u8) = .empty,
    err_ctx: errors.Context,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        buffer_size: usize,
    ) Self {
        const arena = std.heap.ArenaAllocator.init(allocator);
        const err_ctx = errors.Context.init(allocator);
        const buffer = std.ArrayListUnmanaged(u8).initCapacity(allocator, buffer_size) catch outOfMemory();
        return .{
            .allocator = allocator,
            .arena = arena,
            .err_ctx = err_ctx,
            .buffer = buffer,
        };
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
        self.err_ctx.deinit();
        self.buffer.deinit(self.allocator);
    }

    pub fn rep(self: *Self, s: []const u8) ![]const u8 {
        const allocator = self.arena.allocator();
        var val = try Reader.readStr(allocator, s);
        defer val.deinit(allocator);

        var ret = try eval(allocator, val, &self.err_ctx);
        defer ret.deinit(allocator);

        self.buffer.clearRetainingCapacity();
        return ret.toString(self.buffer.allocatedSlice());
    }
};
