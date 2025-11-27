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

    pub fn init(gpa: std.mem.Allocator) !Interpreter {
        return .{
            .name_set = .{},
            .err_ctx = try errors.Ctx.init(gpa, "main"),
        };
    }

    pub fn deinit(self: *Interpreter, gpa: std.mem.Allocator) void {
        self.name_set.deinit(gpa);
        self.err_ctx.deinit(gpa);
    }

    pub fn interpretString(self: *Interpreter, gpa: std.mem.Allocator, subject: []const u8) !void {
        var asts = try reader.readStr(gpa, subject, &self.name_set, &self.err_ctx, 0);
        defer asts.deinit(gpa);

        for (asts.items(.value)) |*v| {
            defer v.deinit(gpa);

            const str = try v.toString(gpa);
            defer gpa.free(str);

            std.debug.print("{s}\n", .{str});
        }
    }
};
