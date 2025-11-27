const std = @import("std");
const MetaData = @import("lisp_types/value.zig").MetaData;
const FileNameArray = @import("interpreter/interpreter.zig").Interpreter.FileNameArray;

pub const Ctx = struct {
    writer: std.io.Writer.Allocating,
    filenames: *FileNameArray,

    pub fn init(gpa: std.mem.Allocator, filenames: *FileNameArray) Ctx {
        return .{
            .writer = .init(gpa),
            .filenames = filenames,
        };
    }

    pub fn deinit(self: *Ctx) void {
        self.writer.deinit();
    }

    pub fn freeMsg(self: *Ctx) void {
        self.writer.shrinkRetainingCapacity(0);
    }

    pub fn setMessage(
        self: *Ctx,
        comptime fmt: []const u8,
        args: anytype,
        meta: MetaData,
    ) !void {
        const filename = self.filenames.keys()[meta.file_id];
        self.freeMsg();
        try self.writer.writer.print(
            "[ FILE '{s}', LINE {}, COL {} ] " ++ fmt ++ "\n",
            .{ filename, meta.line, meta.col } ++ args,
        );
    }

    pub fn appendMessage(
        self: *Ctx,
        comptime fmt: []const u8,
        args: anytype,
        meta: MetaData,
    ) !void {
        const filename = self.filenames.keys()[meta.file_id];
        try self.writer.writer.print(
            "[ FILE '{s}', LINE {}, COL {} ] " ++ fmt ++ "\n",
            .{ filename, meta.line, meta.col } ++ args,
        );
    }

    pub fn getMessage(self: Ctx) []u8 {
        return self.writer.writer.buffered();
    }
};
