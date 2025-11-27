const std = @import("std");
const errors = @import("../errors.zig");
const reader = @import("../reader.zig");

const core = @import("core.zig");
const Env = @import("env.zig").Env;
const types = @import("../lisp_types/value.zig");
const Obj = types.Obj;
const AST = types.AST;
const Value = types.Value;
const NameSet = types.NameSet;
const MetaData = types.MetaData;

pub const Interpreter = struct {
    name_set: NameSet,
    err_ctx: errors.Ctx,
    env: Env,
    filenames: *FileNameArray,

    pub const FileNameArray = std.StringArrayHashMapUnmanaged(void);

    pub const main_file = "main";

    pub fn init(gpa: std.mem.Allocator) !Interpreter {
        var filenames = try gpa.create(FileNameArray);
        filenames.* = .empty;
        try filenames.put(gpa, main_file, {});

        return .{
            .name_set = .{},
            .err_ctx = errors.Ctx.init(gpa, filenames),
            .filenames = filenames,
            .env = .{},
        };
    }

    pub fn deinit(self: *Interpreter, gpa: std.mem.Allocator) void {
        self.name_set.deinit(gpa);
        self.err_ctx.deinit();
        self.filenames.deinit(gpa);
        self.env.deinit(gpa);
        gpa.destroy(self.filenames);
    }

    pub fn addFile(self: *Interpreter, gpa: std.mem.Allocator, filename: []const u8) !usize {
        try self.filenames.append(gpa, filename);
        return self.filenames.items.len - 1;
    }

    pub fn getByName(self: Interpreter, filename: []const u8) ?usize {
        return self.filenames.getIndex(filename);
    }

    pub fn interpretString(self: *Interpreter, gpa: std.mem.Allocator, subject: []const u8, filename: []const u8) !void {
        const file_id = self.getByName(filename) orelse return error.FileNotFound;
        var asts = reader.readStr(gpa, subject, &self.name_set, &self.err_ctx, file_id) catch |err| {
            std.debug.print("{any} {s}\n", .{ err, self.err_ctx.getMessage() });
            return;
        };
        defer asts.deinit(gpa);

        const metas = asts.items(.meta);
        const values = asts.items(.value);
        for (values, 0..) |*v, i| {
            defer v.deinit(gpa);

            self.err_ctx.freeMsg();
            var ret = core.eval(gpa, v.*, &self.env, &self.err_ctx) catch |err| {
                try self.err_ctx.appendMessage("{any}", .{err}, metas[i]);
                std.debug.print("{s}", .{self.err_ctx.getMessage()});
                return;
            };
            defer ret.deinit(gpa);

            const str = try ret.toString(gpa);
            defer gpa.free(str);

            std.debug.print("{s}", .{str});
        }
    }
};
