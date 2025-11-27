const std = @import("std");
const MetaData = @import("lisp_types/value.zig").MetaData;

pub const Ctx = struct {
    msg: []const u8,
    filenames: std.ArrayList([]const u8),

    pub fn init(gpa: std.mem.Allocator, filename: []const u8) !Ctx {
        var filenames: std.ArrayList([]const u8) = .empty;
        try filenames.append(gpa, filename);
        return .{
            .msg = "",
            .filenames = filenames,
        };
    }

    pub fn deinit(self: *Ctx, gpa: std.mem.Allocator) void {
        self.freeMsg(gpa);
        self.filenames.deinit(gpa);
    }

    pub fn freeMsg(self: *Ctx, gpa: std.mem.Allocator) void {
        if (self.msg.len != 0) {
            gpa.free(self.msg);
        }
    }

    pub fn addFile(self: *Ctx, gpa: std.mem.Allocator, filename: []const u8) !usize {
        try self.filenames.append(gpa, filename);
        return self.filenames.items.len - 1;
    }

    pub fn getByName(self: Ctx, filename: []const u8) ?usize {
        return for (self.filenames, 0..) |f, i| {
            if (std.mem.eql(u8, f, filename)) break i;
        } else null;
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
