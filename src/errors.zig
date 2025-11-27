const std = @import("std");
const MetaData = @import("lisp_types/value.zig").MetaData;

pub const Ctx = struct {
    msg: []const u8,
    filenames: *std.ArrayList([]const u8),

    pub fn init(filenames: *std.ArrayList([]const u8)) Ctx {
        return .{
            .msg = "",
            .filenames = filenames,
        };
    }

    pub fn deinit(self: *Ctx, gpa: std.mem.Allocator) void {
        defer self.freeMsg(gpa);
    }

    pub fn freeMsg(self: *Ctx, gpa: std.mem.Allocator) void {
        if (self.msg.len != 0) {
            gpa.free(self.msg);
        }
    }

    pub fn setMessage(
        self: *Ctx,
        gpa: std.mem.Allocator,
        comptime fmt: []const u8,
        args: anytype,
        meta: MetaData,
    ) !void {
        const filename = self.filenames.items[meta.file_id];
        self.freeMsg(gpa);
        self.msg = try std.fmt.allocPrint(
            gpa,
            "[ FILE '{s}', LINE {}, COL {} ]" ++ fmt,
            .{ filename, meta.line, meta.col } ++ args,
        );
    }
};
