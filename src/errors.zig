const std = @import("std");

pub const Ctx = struct {
    msg: []const u8,
    line: usize,

    pub const empty: Ctx = .{ .msg = "", .line = 0 };

    pub fn deinit(self: *Ctx, allocator: std.mem.Allocator) void {
        self.freeMsg(allocator);
    }

    pub fn setMsg(
        self: *Ctx,
        allocator: std.mem.Allocator,
        fn_name: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        self.freeMsg(allocator);
        self.msg = try std.fmt.allocPrint(
            allocator,
            "[ ERROR ON FUNCTION '{s}' - LINE {} ]" ++ fmt,
            .{ fn_name, self.line } ++ args,
        );
    }

    pub fn freeMsg(self: *Ctx, allocator: std.mem.Allocator) void {
        if (self.msg.len > 0) {
            allocator.free(self.msg);
        }
    }
};
