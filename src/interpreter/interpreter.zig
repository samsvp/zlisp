const std = @import("std");
const errors = @import("../errors.zig");
const reader = @import("../reader.zig");

const types = @import("../lisp_types/value.zig");
const Obj = types.Obj;
const AST = types.AST;
const Value = types.Value;
const NameSet = types.NameSet;
const MetaData = types.MetaData;

pub const Interpreter = struct {
    name_set: NameSet,
    err_ctx: errors.Ctx,
    filenames: std.ArrayList([]const u8),

    pub const main_file = "main";

    pub fn init(gpa: std.mem.Allocator) !Interpreter {
        var filenames: std.ArrayList([]const u8) = .empty;
        try filenames.append(gpa, main_file);

        var self: Interpreter = .{
            .name_set = .{},
            .err_ctx = undefined,
            .filenames = filenames,
        };
        self.err_ctx = errors.Ctx.init(&self.filenames);
        return self;
    }

    pub fn deinit(self: *Interpreter, gpa: std.mem.Allocator) void {
        self.name_set.deinit(gpa);
        self.err_ctx.deinit(gpa);
        self.filenames.deinit(gpa);
    }

    pub fn addFile(self: *Interpreter, gpa: std.mem.Allocator, filename: []const u8) !usize {
        try self.filenames.append(gpa, filename);
        return self.filenames.items.len - 1;
    }

    pub fn getByName(self: Interpreter, filename: []const u8) ?usize {
        return for (self.filenames.items, 0..) |f, i| {
            if (std.mem.eql(u8, f, filename)) break i;
        } else null;
    }

    pub fn interpretString(self: *Interpreter, gpa: std.mem.Allocator, subject: []const u8, filename: []const u8) !void {
        const file_id = self.getByName(filename) orelse return error.FileNotFound;
        var asts = try reader.readStr(gpa, subject, &self.name_set, &self.err_ctx, file_id);
        defer asts.deinit(gpa);

        for (asts.items(.value)) |*v| {
            defer v.deinit(gpa);

            const str = try v.toString(gpa);
            defer gpa.free(str);

            std.debug.print("{s}\n", .{str});
        }
    }
};
