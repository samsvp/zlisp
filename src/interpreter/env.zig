const std = @import("std");
const builtin = @import("builtin");

const core = @import("core.zig");
const errors = @import("../errors.zig");
const types = @import("../lisp_types/value.zig");
const Value = types.Value;

pub const Env = struct {
    mapping: std.StringArrayHashMapUnmanaged(Value) = .empty,
    parent: ?*Self = null,

    const Self = @This();

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        for (self.mapping.values()) |*v| {
            v.deinit(gpa);
        }
        self.mapping.deinit(gpa);
    }

    pub fn initFromParent(parent: *Self) Self {
        return .{ .parent = parent };
    }

    pub fn get(self: Self, key: []const u8) ?Value {
        return self.mapping.get(key) orelse {
            if (self.parent) |parent| {
                return parent.get(key);
            }
            return null;
        };
    }

    pub fn getPtr(self: Self, key: []const u8) ?*Value {
        return self.mapping.getPtr(key) orelse {
            if (self.parent) |parent| {
                return parent.getPtr(key);
            }
            return null;
        };
    }

    /// The local env is the environment before the global env
    /// or the global env if parent == null
    pub fn getLocal(self: *Self) *Self {
        var root = self;
        while (root.parent) |p| {
            if (p.parent == null) {
                return root;
            }

            root = p;
        }
        return root;
    }

    /// The global env is the innermost env
    pub fn getGlobal(self: *Self) *Self {
        var root = self;
        while (root.parent) |p| {
            root = p;
        }
        return root;
    }

    pub fn isRoot(self: Self) bool {
        return self.parent == null;
    }

    pub fn put(self: *Self, gpa: std.mem.Allocator, key: []const u8, val: Value) !Value {
        try self.mapping.ensureUnusedCapacity(gpa, 1);
        return self.putAssumeCapacity(key, val);
    }

    pub fn putAssumeCapacity(self: *Self, key: []const u8, val: Value) !Value {
        const b_val = try val.borrow();
        self.mapping.putAssumeCapacity(key, b_val);
        return b_val.borrow();
    }
};
