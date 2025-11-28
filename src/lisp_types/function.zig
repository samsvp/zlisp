const std = @import("std");

const types = @import("value.zig");
const Obj = types.Obj;
const Value = types.Value;

const Closures = std.StringArrayHashMapUnmanaged(Value);

pub const Fn = struct {
    obj: Obj,
    ast: Value,
    args: [][]const u8,
    closures: Closures,
    docstring: []const u8,
    is_macro: bool = false,

    pub fn init(
        gpa: std.mem.Allocator,
        ast: Value,
        args: [][]const u8,
        closure_names: [][]const u8,
        closure_vals: []Value,
        docstring: []const u8,
        is_macro: bool,
    ) !Value {
        var args_owned = try gpa.alloc([]const u8, args.len);
        for (args, 0..) |arg, i| {
            args_owned[i] = try gpa.dupe(u8, arg);
        }

        var closures: Closures = .empty;
        try closures.ensureTotalCapacity(gpa, closure_vals.len);
        for (closure_names, closure_vals) |name, val| {
            closures.putAssumeCapacity(name, try val.borrow());
        }

        const m_fn = try gpa.create(Fn);
        m_fn.* = .{
            .obj = Obj.init(.function),
            .ast = try ast.borrow(),
            .args = args_owned,
            .closures = closures,
            .docstring = try gpa.dupe(u8, docstring),
            .is_macro = is_macro,
        };
        return m_fn;
    }

    pub fn deinit(self: *Fn, gpa: std.mem.Allocator) void {
        for (self.closures.values()) |*v| {
            v.deinit(gpa);
        }

        self.ast.deinit(gpa);
        self.closures.deinit(gpa);
        gpa.free(self.args);
    }
};
